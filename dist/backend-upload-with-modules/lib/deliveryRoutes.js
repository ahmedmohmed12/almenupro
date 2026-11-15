'use strict';

const {
  normalizeDriver,
  publicDriver,
  normalizeDeliveryRequest,
  publicRequest,
  feesFromZone,
  restaurantLocation,
  tickPending,
  geoPoint,
  driverCoversRegion,
  idleDriver,
  isDriverSuspended,
} = require('./deliveryDispatch');
const { isDeliveryManagementEnabled } = require('./diningTables');
const { notifyDriverJob, notifyDriverJobTaken } = require('./fcmDriverNotify');
const { stampTimeline } = require('./orderTimeline');
const { buildFleetSnapshot, driverHasActiveTrip } = require('./fleetOps');
const {
  applyHandshake,
  dualConfirmed,
  ledgerEntry,
  appendDriverLedger,
  filterLedger,
} = require('./driverFinance');

async function handleDeliveryRoutes(req, res, url, ctx) {
  const {
    readBody,
    sendJson,
    parseJson,
    requireAuth,
    authError,
    isDriver,
    isKitchen,
    isSuperAdmin,
    resolveScopedRestaurantId,
    assertRestaurantAccess,
    readDrivers,
    writeDrivers,
    readDeliveryRequests,
    writeDeliveryRequests,
    readDeliveryZones,
    readRestaurants,
    readOrders,
    patchOrderById,
  } = ctx;

  function findDriverForAuth(drivers, auth) {
    if (!auth || !isDriver(auth)) return null;
    const staffId = String(auth.staffId || '');
    const byId = drivers.find((row) => String(row.id) === staffId);
    if (byId) return byId;
    const byStaff = drivers.find((row) => String(row.staff_id || '') === staffId);
    if (byStaff) return byStaff;
    const name = String(auth.staffName || '').trim().toLowerCase();
    if (!name) return null;
    return (
      drivers.find((row) => String(row.name || '').trim().toLowerCase() === name) || null
    );
  }

  function driverFieldsFromRequest(request, drivers = []) {
    const id = String(request?.assigned_driver_id || '');
    const driver = drivers.find((row) => String(row.id) === id);
    return {
      assigned_driver_id: request?.assigned_driver_id || null,
      assigned_driver_name: request?.assigned_driver_name || driver?.name || null,
      assigned_driver_phone: request?.assigned_driver_phone || driver?.phone || null,
    };
  }

  async function stampLinkedOrder(request, eventKey, extra = {}) {
    const orderId = String(request?.order_id || request?.orderId || '').trim();
    if (!orderId || typeof readOrders !== 'function' || typeof patchOrderById !== 'function') {
      return;
    }
    try {
      const orders = await readOrders();
      const index = orders.findIndex((row) => String(row.id) === orderId);
      if (index < 0) return;
      let drivers = [];
      try {
        drivers = await readDrivers();
      } catch (_) {}
      const contact = driverFieldsFromRequest(request, drivers);
      const driverFee = Number(request?.driver_fee ?? request?.driverFee ?? 0) || 0;
      let next = stampTimeline(orders[index], eventKey);
      const nowIso = new Date().toISOString();
      if (eventKey === 'driver_assigned_at') {
        next = {
          ...next,
          status: 'preparing',
          delivery_status: 'driver_accepted',
          driver_fee: driverFee,
          assigned_driver_fee: driverFee,
          ...contact,
          updatedAt: nowIso,
        };
      }
      if (eventKey === 'picked_up_at') {
        next = {
          ...next,
          status: 'preparing',
          delivery_status: 'picked_up',
          driver_fee: driverFee,
          assigned_driver_fee: driverFee,
          ...contact,
          updatedAt: nowIso,
        };
      }
      if (eventKey === 'on_the_way_at') {
        next = {
          ...next,
          status: 'preparing',
          delivery_status: 'on_the_way',
          driver_fee: driverFee,
          assigned_driver_fee: driverFee,
          ...contact,
          updatedAt: nowIso,
        };
      }
      if (eventKey === 'delivered_at') {
        next = stampTimeline(next, 'on_the_way_at');
        next = {
          ...next,
          status: 'delivered',
          delivery_status: 'delivered',
          driver_fee: driverFee,
          assigned_driver_fee: driverFee,
          ...contact,
          updatedAt: nowIso,
        };
      }
      next = { ...next, ...extra };
      await patchOrderById(orderId, next, orders);
    } catch (_) {}
  }

  async function linkedOrder(request) {
    const orderId = String(request?.order_id || request?.orderId || '').trim();
    if (!orderId || typeof readOrders !== 'function') return {};
    try {
      const orders = await readOrders();
      return orders.find((row) => String(row.id) === orderId) || {};
    } catch (_) {
      return {};
    }
  }

  async function withHandshake(request) {
    return applyHandshake(request, await linkedOrder(request));
  }

  async function completePickup(requests, index, drivers, now, actorName) {
    let next = await withHandshake({
      ...requests[index],
      status: 'picked_up',
      picked_up_at: now,
      updated_at: now,
    });
    if (!next.driver_handoff_confirmed_at) {
      next.driver_handoff_confirmed_at = now;
      next.driver_handoff_by = actorName;
    }
    requests[index] = next;
    const assignedId = String(next.assigned_driver_id || '');
    const order = await linkedOrder(next);
    const entry = ledgerEntry(next, order, now);
    const di = drivers.findIndex((row) => String(row.id) === assignedId);
    if (di >= 0) {
      drivers[di] = appendDriverLedger(drivers[di], entry);
    }
    await writeDrivers(drivers);
    await writeDeliveryRequests(requests);
    await stampLinkedOrder(next, 'picked_up_at', {
      cashier_handoff_confirmed_at: next.cashier_handoff_confirmed_at,
      driver_handoff_confirmed_at: next.driver_handoff_confirmed_at,
      ...require('./driverFinance').handshakePublicFields(next),
    });
    return next;
  }

  async function tickAll(restaurantId) {
    const nowMs = Date.now();
    const drivers = await readDrivers();
    const list = await readDeliveryRequests();
    let changed = false;
    const fcmJobs = [];
    const next = list.map((row) => {
      if (restaurantId && String(row.restaurant_id || row.restaurantId) !== String(restaurantId)) {
        return row;
      }
      const result = tickPending(row, drivers, nowMs);
      if (result.changed) changed = true;
      if (Array.isArray(result.newlyNotified) && result.newlyNotified.length) {
        fcmJobs.push({ request: result.request, ids: result.newlyNotified });
      }
      return result.request;
    });
    if (changed) await writeDeliveryRequests(next);
    await Promise.all(
      fcmJobs.flatMap((job) =>
        job.ids.map((id) => {
          const driver = drivers.find((row) => String(row.id) === String(id));
          return driver ? notifyDriverJob(driver, job.request) : Promise.resolve();
        }),
      ),
    );
    return next;
  }

  if (url.pathname === '/api/master-regions' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const { regionKey } = require('./deliveryDispatch');
    const zones = await readDeliveryZones();
    const byKey = new Map();
    for (const zone of zones || []) {
      if (zone.isActive === false || zone.is_active === false) continue;
      const name = String(zone.areaName || zone.area_name || '').trim();
      if (!name) continue;
      const id = regionKey(name);
      if (!id || byKey.has(id)) continue;
      byKey.set(id, {
        id,
        name,
        governorate: String(zone.governorate || '').trim(),
      });
    }
    const list = [...byKey.values()].sort((a, b) => a.name.localeCompare(b.name, 'ar'));
    sendJson(res, 200, list);
    return true;
  }

  if (url.pathname === '/api/fleet/ops' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      sendJson(res, 403, { error: 'مركز الأسطول متاح للسوبر أدمن فقط' });
      return true;
    }
    const requests = await tickAll(null);
    sendJson(res, 200, buildFleetSnapshot(await readDrivers(), requests));
    return true;
  }

  const ledgerMatch = url.pathname.match(/^\/api\/drivers\/([^/]+)\/ledger$/);
  if (ledgerMatch && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      sendJson(res, 403, { error: 'السجل المالي متاح للسوبر أدمن فقط' });
      return true;
    }
    const id = decodeURIComponent(ledgerMatch[1]);
    const list = await readDrivers();
    const driver = list.find((row) => String(row.id) === id);
    if (!driver) {
      sendJson(res, 404, { error: 'السائق غير موجود' });
      return true;
    }
    const query = url.searchParams || new URLSearchParams(url.search || '');
    const entries = filterLedger(driver.financial_ledger || [], {
      from: query.get('from'),
      to: query.get('to'),
      restaurant: query.get('restaurant') || query.get('restaurant_name'),
      orderId: query.get('order_id') || query.get('orderId') || query.get('q'),
    });
    sendJson(res, 200, { driver_id: driver.id, driver_name: driver.name, entries });
    return true;
  }

  if (url.pathname === '/api/drivers' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (isKitchen(auth)) {
      sendJson(res, 403, { error: 'غير مسموح' });
      return true;
    }
    const list = (await readDrivers()).map(publicDriver);
    sendJson(res, 200, list);
    return true;
  }

  if (url.pathname === '/api/drivers' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      sendJson(res, 403, { error: 'إضافة السائقين متاحة للسوبر أدمن فقط' });
      return true;
    }
    const body = parseJson(await readBody(req));
    const record = normalizeDriver(body);
    if (record.name.length < 2) {
      sendJson(res, 400, { error: 'اسم السائق مطلوب' });
      return true;
    }
    if (!record.pin_hash) {
      sendJson(res, 400, { error: 'رمز PIN المكون من 4 أرقام مطلوب لتطبيق السائق' });
      return true;
    }
    const list = await readDrivers();
    list.push(record);
    await writeDrivers(list);
    sendJson(res, 201, publicDriver(record));
    return true;
  }

  const driverMatch = url.pathname.match(/^\/api\/drivers\/([^/]+)$/);
  if (driverMatch && (req.method === 'PATCH' || req.method === 'DELETE')) {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const id = decodeURIComponent(driverMatch[1]);
    const list = await readDrivers();
    const index = list.findIndex((row) => String(row.id) === id);
    if (index < 0) {
      sendJson(res, 404, { error: 'السائق غير موجود' });
      return true;
    }
    if (req.method === 'DELETE') {
      if (!isSuperAdmin(auth)) {
        sendJson(res, 403, { error: 'حذف السائقين متاح للسوبر أدمن فقط' });
        return true;
      }
      list.splice(index, 1);
      await writeDrivers(list);
      sendJson(res, 200, { ok: true });
      return true;
    }
    const body = parseJson(await readBody(req));
    if (isDriver(auth)) {
      const own =
        String(list[index].id) === String(auth.staffId || '') ||
        String(list[index].staff_id || '') === String(auth.staffId || '');
      if (!own) {
        sendJson(res, 403, { error: 'غير مسموح' });
        return true;
      }
    } else if (!isSuperAdmin(auth)) {
      sendJson(res, 403, { error: 'تعديل السائقين متاح للسوبر أدمن أو السائق نفسه' });
      return true;
    }
    const loc = geoPoint(body.current_location || body.currentLocation) || list[index].current_location;
    const nextBody = { ...list[index], ...body, current_location: loc,     last_updated: new Date().toISOString() };
    if (isDriver(auth) && !isSuperAdmin(auth)) {
      nextBody.allowed_delivery_regions = list[index].allowed_delivery_regions;
      nextBody.assigned_regions = list[index].assigned_regions;
      nextBody.staff_id = list[index].staff_id;
      nextBody.name = list[index].name;
      nextBody.civil_id = list[index].civil_id;
      nextBody.civil_id_photo_url = list[index].civil_id_photo_url;
      nextBody.license_photo_url = list[index].license_photo_url;
      nextBody.pin_hash = list[index].pin_hash;
      nextBody.pin = undefined;
      nextBody.suspended_until = list[index].suspended_until;
    }
    const goingIdle =
      (nextBody.is_online === true || nextBody.isOnline === true) &&
      nextBody.is_busy !== true &&
      nextBody.isBusy !== true;
    if (goingIdle && (!list[index].available_since || list[index].is_online !== true)) {
      nextBody.available_since = new Date().toISOString();
    }
    list[index] = normalizeDriver(nextBody);
    await writeDrivers(list);
    sendJson(res, 200, publicDriver(list[index]));
    return true;
  }

  const controlMatch = url.pathname.match(/^\/api\/drivers\/([^/]+)\/control$/);
  if (controlMatch && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      sendJson(res, 403, { error: 'تحكم الأسطول متاح للسوبر أدمن فقط' });
      return true;
    }
    const id = decodeURIComponent(controlMatch[1]);
    const list = await readDrivers();
    const index = list.findIndex((row) => String(row.id) === id);
    if (index < 0) {
      sendJson(res, 404, { error: 'السائق غير موجود' });
      return true;
    }
    const body = parseJson(await readBody(req));
    const action = String(body.action || '').trim();
    const now = new Date().toISOString();
    let next = { ...list[index], last_updated: now };
    if (action === 'suspend') {
      const minutes = Math.max(1, Number(body.minutes) || 15);
      next.suspended_until = new Date(Date.now() + minutes * 60 * 1000).toISOString();
      next.is_busy = true;
      next.available_since = null;
    } else if (action === 'unsuspend') {
      next.suspended_until = null;
      if (!driverHasActiveTrip(await readDeliveryRequests(), id)) {
        next = idleDriver(next, now);
        next.is_online = next.is_online === true;
      }
    } else if (action === 'status') {
      const status = String(body.status || '').trim();
      if (status === 'available') {
        next.suspended_until = null;
        next.is_online = true;
        next.is_busy = false;
        next.available_since = now;
      } else if (status === 'busy') {
        next.is_online = true;
        next.is_busy = true;
        next.available_since = null;
      } else if (status === 'offline') {
        next.is_online = false;
        next.is_busy = false;
      } else {
        sendJson(res, 400, { error: 'حالة غير صالحة' });
        return true;
      }
    } else {
      sendJson(res, 400, { error: 'إجراء غير صالح' });
      return true;
    }
    list[index] = normalizeDriver(next);
    await writeDrivers(list);
    sendJson(res, 200, publicDriver(list[index]));
    return true;
  }

  if (url.pathname === '/api/me/driver' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isDriver(auth)) {
      sendJson(res, 403, { error: 'حساب سائق مطلوب' });
      return true;
    }
    const list = await readDrivers();
    let driver = findDriverForAuth(list, auth);
    if (!driver) {
      driver = normalizeDriver({
        name: auth.staffName || 'سائق',
        staff_id: auth.staffId,
        is_online: false,
        assigned_regions: {},
      });
      list.push(driver);
      await writeDrivers(list);
    } else if (!driver.staff_id && auth.staffId) {
      const index = list.findIndex((row) => String(row.id) === String(driver.id));
      if (index >= 0) {
        list[index] = normalizeDriver({ ...driver, staff_id: auth.staffId });
        driver = list[index];
        await writeDrivers(list);
      }
    }
    const requests = await tickAll(null);
    const incoming = requests.filter(
      (row) =>
        !isDriverSuspended(driver) &&
        row.status === 'pending' &&
        (row.notified_driver_ids || []).includes(driver.id) &&
        driverCoversRegion(driver, row.destination_region_id || row.region_id, row.region_name),
    );
    const active = requests.find(
      (row) =>
        String(row.assigned_driver_id) === String(driver.id) &&
        ['accepted', 'picked_up', 'on_the_way'].includes(row.status),
    );
    sendJson(res, 200, {
      driver: publicDriver(driver),
      incoming: incoming.map((row) => publicRequest(row, { forDriver: true })),
      active: active ? publicRequest(active, { forDriver: true }) : null,
      history: requests
        .filter(
          (row) =>
            String(row.assigned_driver_id) === String(driver.id) &&
            ['delivered', 'cancelled'].includes(String(row.status || '')),
        )
        .sort(
          (a, b) =>
            Date.parse(b.updated_at || b.created_at || 0) -
            Date.parse(a.updated_at || a.created_at || 0),
        )
        .slice(0, 50)
        .map((row) => publicRequest(row, { forDriver: true })),
    });
    return true;
  }

  if (url.pathname === '/api/delivery-requests' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (isDriver(auth)) {
      sendJson(res, 403, { error: 'استخدم /api/me/driver' });
      return true;
    }
    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const list = (await tickAll(restaurantId)).filter(
      (row) => String(row.restaurant_id || row.restaurantId) === String(restaurantId),
    );
    sendJson(res, 200, list.map((row) => publicRequest(row)));
    return true;
  }

  if (url.pathname === '/api/delivery-requests' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (isDriver(auth) || isKitchen(auth)) {
      sendJson(res, 403, { error: 'غير مسموح' });
      return true;
    }
    const body = parseJson(await readBody(req));
    const restaurantId =
      body.restaurantId || body.restaurant_id || (await resolveScopedRestaurantId(req, url, auth));
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const restaurants = await readRestaurants();
    const restaurant = restaurants.find((entry) => String(entry.id) === String(restaurantId)) || {};
    if (!isDeliveryManagementEnabled(restaurant)) {
      sendJson(res, 403, {
        error: 'اشتراك توصيل سائقي المنيو برو غير مفعّل لهذا المطعم',
        code: 'DELIVERY_MANAGEMENT_DISABLED',
      });
      return true;
    }
    const zones = await readDeliveryZones();
    const zone = zones.find(
      (entry) =>
        String(entry.id) === String(body.destination_region_id || body.region_id || body.regionId || body.deliveryZoneId || ''),
    );
    const fees = feesFromZone(zone || body);
    const record = normalizeDeliveryRequest(
      {
        ...body,
        restaurantName: restaurant.name || body.restaurantName,
        restaurant_location: geoPoint(body.restaurant_location) || restaurantLocation(restaurant),
        customer_fee: fees.customer_fee,
        driver_fee: body.driver_fee != null ? body.driver_fee : fees.driver_fee,
        platform_margin: fees.platform_margin,
        region_id: body.destination_region_id || body.region_id || zone?.id,
        destination_region_id: body.destination_region_id || body.region_id || zone?.id,
        region_name: body.region_name || zone?.areaName || zone?.area_name || '',
        offer_expires_at: new Date(Date.now() + 45000).toISOString(),
      },
      restaurantId,
    );
    if (!record.customer_phone) {
      sendJson(res, 400, { error: 'رقم هاتف العميل مطلوب' });
      return true;
    }
    if (!record.destination_region_id) {
      sendJson(res, 400, { error: 'منطقة التوصيل مطلوبة' });
      return true;
    }
    const list = await readDeliveryRequests();
    list.unshift(record);
    await writeDeliveryRequests(list.slice(0, 800));
    await tickAll(restaurantId);
    const stored = (await readDeliveryRequests()).find((row) => row.id === record.id) || record;
    sendJson(res, 201, publicRequest(stored));
    return true;
  }

  const actionMatch = url.pathname.match(
    /^\/api\/delivery-requests\/([^/]+)\/(accept|decline|pickup|on_the_way|deliver|cancel|assign|unassign|admin-deliver|cashier-confirm|driver-confirm)$/,
  );
  if (actionMatch && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const id = decodeURIComponent(actionMatch[1]);
    const action = actionMatch[2];
    const body = parseJson(await readBody(req));
    const requests = await readDeliveryRequests();
    const index = requests.findIndex((row) => String(row.id) === id);
    if (index < 0) {
      sendJson(res, 404, { error: 'طلب التوصيل غير موجود' });
      return true;
    }
    const restaurantId = requests[index].restaurant_id || requests[index].restaurantId;
    const drivers = await readDrivers();
    const now = new Date().toISOString();
    const driverForAuth = findDriverForAuth(drivers, auth);

    if (action === 'assign') {
      if (isDriver(auth) || isKitchen(auth)) {
        sendJson(res, 403, { error: 'غير مسموح' });
        return true;
      }
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
      const driverId = String(body.driver_id || body.driverId || '').trim();
      const driverIndex = drivers.findIndex((row) => String(row.id) === driverId);
      if (driverIndex < 0) {
        sendJson(res, 404, { error: 'السائق غير موجود' });
        return true;
      }
      if (isDriverSuspended(drivers[driverIndex])) {
        sendJson(res, 409, { error: 'السائق محظور مؤقتاً' });
        return true;
      }
      if (
        !driverCoversRegion(
          drivers[driverIndex],
          requests[index].destination_region_id || requests[index].region_id,
          requests[index].region_name,
        )
      ) {
        sendJson(res, 403, { error: 'السائق غير مفعّل لمنطقة هذا الطلب' });
        return true;
      }
      const currentStatus = String(requests[index].status || '');
      const canAssign =
        currentStatus === 'pending' ||
        currentStatus === 'rejected_by_all' ||
        (isSuperAdmin(auth) && ['accepted', 'picked_up', 'on_the_way'].includes(currentStatus));
      if (!canAssign) {
        sendJson(res, 409, { error: 'لا يمكن تعيين هذا الطلب' });
        return true;
      }
      const previousDriverId = String(requests[index].assigned_driver_id || '');
      const losers = (requests[index].notified_driver_ids || []).filter((entry) => entry !== driverId);
      requests[index] = await withHandshake({
        ...requests[index],
        status: currentStatus === 'picked_up' || currentStatus === 'on_the_way' ? currentStatus : 'accepted',
        assigned_driver_id: drivers[driverIndex].id,
        assigned_driver_name: drivers[driverIndex].name,
        assigned_driver_phone: drivers[driverIndex].phone || null,
        accepted_at: requests[index].accepted_at || now,
        updated_at: now,
      });
      drivers[driverIndex] = { ...drivers[driverIndex], is_busy: true, last_updated: now, available_since: null };
      if (previousDriverId && previousDriverId !== driverId) {
        const prev = drivers.findIndex((row) => String(row.id) === previousDriverId);
        if (prev >= 0 && !driverHasActiveTrip(requests, previousDriverId)) {
          drivers[prev] = idleDriver(drivers[prev], now);
        }
      }
      await writeDrivers(drivers);
      await writeDeliveryRequests(requests);
      const loserDrivers = drivers.filter((row) => losers.includes(String(row.id)));
      notifyDriverJobTaken(loserDrivers, requests[index], driverId);
      await stampLinkedOrder(requests[index], 'driver_assigned_at', {
        ...require('./driverFinance').handshakePublicFields(requests[index]),
      });
      sendJson(res, 200, publicRequest(requests[index]));
      return true;
    }

    if (action === 'unassign' || action === 'admin-deliver') {
      if (!isSuperAdmin(auth) && (isDriver(auth) || isKitchen(auth))) {
        sendJson(res, 403, { error: 'غير مسموح' });
        return true;
      }
      if (!isSuperAdmin(auth) && !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }
      const assignedId = String(requests[index].assigned_driver_id || '');
      if (action === 'unassign') {
        if (!['accepted', 'picked_up', 'on_the_way'].includes(String(requests[index].status || ''))) {
          sendJson(res, 409, { error: 'لا يوجد طلب نشط لسحبه' });
          return true;
        }
        const declined = [...new Set([...(requests[index].declined_driver_ids || []), assignedId])].filter(
          Boolean,
        );
        requests[index] = {
          ...requests[index],
          status: 'pending',
          assigned_driver_id: null,
          assigned_driver_name: null,
          assigned_driver_phone: null,
          notified_driver_ids: [],
          declined_driver_ids: declined,
          offer_expires_at: new Date(Date.now() + 45000).toISOString(),
          updated_at: now,
        };
        const di = drivers.findIndex((row) => String(row.id) === assignedId);
        if (di >= 0 && !driverHasActiveTrip(requests, assignedId)) {
          drivers[di] = idleDriver(drivers[di], now);
        }
        await writeDrivers(drivers);
        await writeDeliveryRequests(requests);
        await tickAll(null);
        sendJson(res, 200, publicRequest(requests[index]));
        return true;
      }
      const tripStatus = String(requests[index].status || '');
      const canAdminDeliver = isSuperAdmin(auth)
        ? !['delivered', 'cancelled'].includes(tripStatus)
        : ['accepted', 'picked_up', 'on_the_way'].includes(tripStatus);
      if (!canAdminDeliver) {
        sendJson(res, 409, { error: 'الطلب ليس قيد التوصيل' });
        return true;
      }
      const adminName = String(auth.staffName || auth.username || auth.role || 'super_admin');
      requests[index] = {
        ...requests[index],
        status: 'delivered',
        delivered_at: now,
        admin_delivered: true,
        admin_delivered_at: now,
        admin_delivered_by: adminName,
        updated_at: now,
      };
      const di = drivers.findIndex((row) => String(row.id) === assignedId);
      if (di >= 0 && !driverHasActiveTrip(requests, assignedId)) {
        drivers[di] = idleDriver(
          { ...drivers[di], is_online: drivers[di].is_online === true },
          now,
        );
      }
      await writeDrivers(drivers);
      await writeDeliveryRequests(requests);
      await stampLinkedOrder(requests[index], 'delivered_at', {
        admin_delivered: true,
        admin_delivered_at: now,
        admin_delivered_by: adminName,
      });
      sendJson(res, 200, publicRequest(requests[index]));
      return true;
    }

    if (action === 'cashier-confirm') {
      if (isDriver(auth) || isKitchen(auth)) {
        sendJson(res, 403, { error: 'غير مسموح' });
        return true;
      }
      if (!isSuperAdmin(auth) && !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }
      if (String(requests[index].status || '') !== 'accepted') {
        sendJson(res, 409, { error: 'التأكيد المالي متاح بعد قبول السائق وقبل الاستلام' });
        return true;
      }
      const cashierName = String(auth.staffName || auth.username || 'cashier');
      requests[index] = await withHandshake({
        ...requests[index],
        cashier_handoff_confirmed_at: now,
        cashier_handoff_by: cashierName,
        updated_at: now,
      });
      if (dualConfirmed(requests[index])) {
        const picked = await completePickup(
          requests,
          index,
          drivers,
          now,
          requests[index].driver_handoff_by || requests[index].assigned_driver_name,
        );
        sendJson(res, 200, publicRequest(picked));
        return true;
      }
      await writeDeliveryRequests(requests);
      await stampLinkedOrder(requests[index], 'driver_assigned_at', {
        cashier_handoff_confirmed_at: now,
        cashier_handoff_by: cashierName,
        ...require('./driverFinance').handshakePublicFields(requests[index]),
      });
      sendJson(res, 200, publicRequest(requests[index]));
      return true;
    }

    if (!isDriver(auth) || !driverForAuth) {
      sendJson(res, 403, { error: 'حساب سائق مطلوب' });
      return true;
    }

    if (isDriverSuspended(driverForAuth) && action !== 'deliver' && action !== 'cancel') {
      sendJson(res, 403, { error: 'حسابك محظور مؤقتاً' });
      return true;
    }

    if (action === 'accept') {
      if (requests[index].status !== 'pending') {
        sendJson(res, 409, { error: 'الطلب لم يعد متاحاً' });
        return true;
      }
      const notified = (requests[index].notified_driver_ids || []).map(String);
      if (notified.length && !notified.includes(String(driverForAuth.id))) {
        sendJson(res, 403, { error: 'هذا العرض غير موجّه لك' });
        return true;
      }
      if (
        !driverCoversRegion(
          driverForAuth,
          requests[index].destination_region_id || requests[index].region_id,
          requests[index].region_name,
        )
      ) {
        sendJson(res, 403, { error: 'منطقتك غير مفعّلة لهذا الطلب' });
        return true;
      }
      const losers = notified.filter((entry) => entry !== String(driverForAuth.id));
      requests[index] = await withHandshake({
        ...requests[index],
        status: 'accepted',
        assigned_driver_id: driverForAuth.id,
        assigned_driver_name: driverForAuth.name,
        assigned_driver_phone: driverForAuth.phone || null,
        accepted_at: now,
        updated_at: now,
      });
      const di = drivers.findIndex((row) => row.id === driverForAuth.id);
      if (di >= 0) drivers[di] = { ...drivers[di], is_busy: true, last_updated: now, available_since: null };
      await writeDrivers(drivers);
      await writeDeliveryRequests(requests);
      const loserDrivers = drivers.filter((row) => losers.includes(String(row.id)));
      notifyDriverJobTaken(loserDrivers, requests[index], driverForAuth.id);
      await stampLinkedOrder(requests[index], 'driver_assigned_at', {
        ...require('./driverFinance').handshakePublicFields(requests[index]),
      });
      sendJson(res, 200, publicRequest(requests[index], { forDriver: true }));
      return true;
    }

    if (action === 'decline') {
      const notified = (requests[index].notified_driver_ids || []).filter(
        (entry) => entry !== driverForAuth.id,
      );
      const declined = [...new Set([...(requests[index].declined_driver_ids || []), driverForAuth.id])];
      requests[index] = {
        ...requests[index],
        notified_driver_ids: notified,
        declined_driver_ids: declined,
        updated_at: now,
      };
      await writeDeliveryRequests(requests);
      await tickAll(null);
      sendJson(res, 200, { ok: true });
      return true;
    }

    if (String(requests[index].assigned_driver_id) !== String(driverForAuth.id)) {
      sendJson(res, 403, { error: 'هذا الطلب غير معيّن لك' });
      return true;
    }

    if (action === 'pickup' || action === 'driver-confirm') {
      if (String(requests[index].status || '') !== 'accepted') {
        sendJson(res, 409, { error: 'لا يمكن تأكيد الاستلام في هذه الحالة' });
        return true;
      }
      const driverName = String(driverForAuth.name || auth.staffName || 'driver');
      requests[index] = await withHandshake({
        ...requests[index],
        driver_handoff_confirmed_at: now,
        driver_handoff_by: driverName,
        updated_at: now,
      });
      if (dualConfirmed(requests[index])) {
        const picked = await completePickup(requests, index, drivers, now, driverName);
        sendJson(res, 200, publicRequest(picked, { forDriver: true }));
        return true;
      }
      await writeDeliveryRequests(requests);
      await stampLinkedOrder(requests[index], 'driver_assigned_at', {
        driver_handoff_confirmed_at: now,
        driver_handoff_by: driverName,
        ...require('./driverFinance').handshakePublicFields(requests[index]),
      });
      sendJson(res, 200, publicRequest(requests[index], { forDriver: true }));
      return true;
    }

    if (action === 'on_the_way') {
      if (requests[index].status !== 'picked_up' && requests[index].status !== 'on_the_way') {
        sendJson(res, 409, { error: 'استلم الطلب أولاً' });
        return true;
      }
      requests[index] = {
        ...requests[index],
        status: 'on_the_way',
        on_the_way_at: now,
        updated_at: now,
      };
      await writeDeliveryRequests(requests);
      await stampLinkedOrder(requests[index], 'on_the_way_at');
      sendJson(res, 200, publicRequest(requests[index], { forDriver: true }));
      return true;
    }

    if (action === 'deliver') {
      requests[index] = {
        ...requests[index],
        status: 'delivered',
        delivered_at: now,
        updated_at: now,
      };
      const di = drivers.findIndex((row) => row.id === driverForAuth.id);
      if (di >= 0 && !driverHasActiveTrip(requests, driverForAuth.id)) {
        drivers[di] = idleDriver({ ...drivers[di], is_online: true }, now);
      }
      await writeDrivers(drivers);
      await writeDeliveryRequests(requests);
      await stampLinkedOrder(requests[index], 'delivered_at');
      sendJson(res, 200, publicRequest(requests[index], { forDriver: true }));
      return true;
    }

    if (action === 'cancel') {
      const declined = [...new Set([...(requests[index].declined_driver_ids || []), driverForAuth.id])];
      requests[index] = {
        ...requests[index],
        status: 'pending',
        assigned_driver_id: null,
        assigned_driver_name: null,
        assigned_driver_phone: null,
        notified_driver_ids: [],
        declined_driver_ids: declined,
        offer_expires_at: new Date(Date.now() + 45000).toISOString(),
        updated_at: now,
      };
      const di = drivers.findIndex((row) => row.id === driverForAuth.id);
      if (di >= 0 && !driverHasActiveTrip(requests, driverForAuth.id)) {
        drivers[di] = idleDriver({ ...drivers[di], is_online: drivers[di].is_online === true }, now);
      }
      await writeDrivers(drivers);
      await writeDeliveryRequests(requests);
      await tickAll(null);
      sendJson(res, 200, publicRequest(requests[index], { forDriver: true }));
      return true;
    }
  }

  return false;
}

function resolveOrderZone(zones, order) {
  const id = String(order.deliveryZoneId || order.delivery_zone_id || '').trim();
  if (id) {
    const byId = (zones || []).find((zone) => String(zone.id) === id);
    if (byId) return byId;
  }
  const name = String(order.areaName || order.area_name || '').trim().toLowerCase();
  if (!name) return null;
  return (
    (zones || []).find((zone) => {
      const zoneName = String(zone.areaName || zone.area_name || '').trim().toLowerCase();
      return zoneName && zoneName === name;
    }) || null
  );
}

async function enqueueDeliveryForAcceptedOrder(order, ctx = {}) {
  if (!order || typeof order !== 'object') return null;
  const type = String(order.orderType || order.order_type || 'delivery')
    .trim()
    .toLowerCase()
    .replace(/[_-]/g, '');
  if (type && type !== 'delivery') return null;
  const restaurantId = String(order.restaurant_id || order.restaurantId || '').trim();
  const orderId = String(order.id || '').trim();
  if (!restaurantId || !orderId) return null;
  const {
    readRestaurants,
    readDeliveryZones,
    readDeliveryRequests,
    writeDeliveryRequests,
    readDrivers,
  } = ctx;
  if (
    typeof readRestaurants !== 'function' ||
    typeof readDeliveryRequests !== 'function' ||
    typeof writeDeliveryRequests !== 'function'
  ) {
    return null;
  }
  const restaurants = await readRestaurants();
  const restaurant = restaurants.find((row) => String(row.id) === restaurantId) || {};
  if (!isDeliveryManagementEnabled(restaurant)) return null;
  const list = await readDeliveryRequests();
  const existing = list.find((row) => {
    if (String(row.order_id || row.orderId) !== orderId) return false;
    const status = String(row.status || '');
    return !['delivered', 'cancelled'].includes(status);
  });
  if (existing) return existing;
  const zones = typeof readDeliveryZones === 'function' ? await readDeliveryZones() : [];
  const zone = resolveOrderZone(zones, order);
  const regionId = String(zone?.id || order.deliveryZoneId || order.delivery_zone_id || '').trim();
  if (!regionId) return null;
  const fees = feesFromZone(zone || { deliveryFee: order.deliveryFee || order.delivery_fee });
  const pay = String(order.paymentMethod || order.payment_method || '');
  const cashToCollect = /كاش|cash/i.test(pay) ? Number(order.totalPrice || order.total_price || 0) || 0 : 0;
  const record = normalizeDeliveryRequest(
    {
      restaurantName: restaurant.name || '',
      restaurant_location: restaurantLocation(restaurant),
      order_id: orderId,
      customer_phone: order.phone,
      customer_address: order.address,
      customer_fee: fees.customer_fee,
      driver_fee: fees.driver_fee,
      platform_margin: fees.platform_margin,
      cash_to_collect: cashToCollect,
      payment_method: pay,
      region_id: regionId,
      destination_region_id: regionId,
      region_name: order.areaName || order.area_name || zone?.areaName || zone?.area_name || '',
      offer_expires_at: new Date(Date.now() + 45000).toISOString(),
    },
    restaurantId,
  );
  const withMoney = applyHandshake(record, order);
  list.unshift(withMoney);
  await writeDeliveryRequests(list.slice(0, 800));
  if (typeof readDrivers !== 'function') return withMoney;
  const drivers = await readDrivers();
  const ticked = tickPending(withMoney, drivers, Date.now());
  if (ticked.changed) {
    const nextList = await readDeliveryRequests();
    const index = nextList.findIndex((row) => String(row.id) === String(withMoney.id));
    if (index >= 0) {
      nextList[index] = ticked.request;
      await writeDeliveryRequests(nextList);
    }
    await Promise.all(
      (ticked.newlyNotified || []).map((id) => {
        const driver = drivers.find((row) => String(row.id) === String(id));
        return driver ? notifyDriverJob(driver, ticked.request) : Promise.resolve();
      }),
    );
    return ticked.request;
  }
  return withMoney;
}

module.exports = { handleDeliveryRoutes, enqueueDeliveryForAcceptedOrder };
