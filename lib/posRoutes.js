const {
  normalizePosRoles,
  findRoleById,
  PERMISSION_KEYS,
} = require('./posPermissions');
const {
  sanitizeStaffPublic,
  createStaffRecord,
  updateStaffRecord,
  findStaffByPin,
  resolveStaffPermissions,
  verifyManagerOverride,
} = require('./staffUsers');
const {
  normalizeShiftSession,
  findOpenShift,
  createOpenShift,
  closeShift,
  computeShiftSummary,
} = require('./shiftSessions');
const { buildAuditEvent } = require('./auditLog');
const {
  computePlatformDualTotals,
  isPlatformOrder,
  money,
  normalizeCashierSettlementMethod,
} = require('./platformOrderFinance');
const { assignTargetKitchen } = require('./kitchenRouting');
const { enqueueDeliveryForAcceptedOrder } = require('./deliveryRoutes');
const { computeSmartUpsell } = require('./smartUpsell');
const {
  DEFAULT_RESTAURANT_ID,
  isCashier,
  isRestaurantAdmin,
} = require('./adminAuth');
const { enforceShiftClosePendingGuard } = require('./shiftPendingOrders');
const {
  isPendingPaymentOrder,
  normalizePaymentStatus,
} = require('./orderPaymentStatus');
const {
  normalizeKitchenLine,
  stampKitchenSent,
  enforceKitchenItemMutation,
  stampOrderKitchenVoidNotice,
} = require('./kitchenDispatchLock');

function parsePosSettings(settings = {}) {
  return {
    posRoles: normalizePosRoles(settings.posRoles || settings.pos_roles),
    posAutoLockMinutes:
      Number(settings.posAutoLockMinutes ?? settings.pos_auto_lock_minutes ?? 5) ||
      5,
  };
}

async function appendAudit(deps, event) {
  await deps.appendAuditEvents([buildAuditEvent(event)]);
}

function frozenOrderFinancials(order) {
  return {
    totalPrice: order.totalPrice,
    total_price: order.total_price,
    subtotal: order.subtotal,
    deliveryFee: order.deliveryFee,
    delivery_fee: order.delivery_fee,
    discountAmount: order.discountAmount,
    discount_amount: order.discount_amount,
    customerPayableTotal: order.customerPayableTotal,
    customer_payable_total: order.customer_payable_total,
    netMerchantSales: order.netMerchantSales,
    net_merchant_sales: order.net_merchant_sales,
    items: order.items,
    paymentMethod: order.paymentMethod,
    payment_method: order.payment_method,
    priceLocked: order.priceLocked,
  };
}

async function applyCashierDeliveryZone(order, zoneId, { restaurantId, auth, readDeliveryZones }) {
  const id = String(zoneId || '').trim();
  if (!id) return order;
  const zones = typeof readDeliveryZones === 'function' ? await readDeliveryZones() : [];
  const zone = (zones || []).find((row) => String(row.id) === id);
  if (!zone) {
    const error = new Error('Delivery zone not found');
    error.statusCode = 404;
    throw error;
  }
  const zoneRestaurant = String(zone.restaurant_id || zone.restaurantId || '').trim();
  if (zoneRestaurant && zoneRestaurant !== String(restaurantId)) {
    const error = new Error('Delivery zone does not belong to this restaurant');
    error.statusCode = 403;
    throw error;
  }
  const assignment = await assignTargetKitchen({
    body: {
      orderType: order.orderType || order.order_type || 'delivery',
    },
    restaurantId,
    auth,
    deliveryZoneId: zone.id,
  });
  const areaName = String(zone.areaName || zone.area_name || '').trim();
  return {
    ...order,
    deliveryZoneId: zone.id,
    delivery_zone_id: zone.id,
    governorate: String(zone.governorate || order.governorate || '').trim(),
    areaName,
    area_name: areaName,
    ...(assignment || {}),
    ...frozenOrderFinancials(order),
  };
}

async function syncZoneDriverDispatch(order, deps) {
  const status = String(order.status || '').trim().toLowerCase();
  if (['cancelled', 'delivered', 'rejected'].includes(status)) return;
  const zoneId = String(order.deliveryZoneId || order.delivery_zone_id || '').trim();
  if (!zoneId) return;
  if (
    typeof deps.readDeliveryRequests !== 'function' ||
    typeof deps.writeDeliveryRequests !== 'function'
  ) {
    return;
  }
  const list = await deps.readDeliveryRequests();
  const index = (list || []).findIndex((row) => {
    if (String(row.order_id || row.orderId) !== String(order.id)) return false;
    return !['delivered', 'cancelled'].includes(String(row.status || ''));
  });
  if (index >= 0) {
    const next = [...list];
    next[index] = {
      ...next[index],
      region_id: zoneId,
      destination_region_id: zoneId,
      region_name: order.areaName || order.area_name || next[index].region_name || '',
      customer_address: order.address || next[index].customer_address || '',
      customer_phone: order.phone || next[index].customer_phone || '',
      updated_at: new Date().toISOString(),
    };
    await deps.writeDeliveryRequests(next);
    return;
  }
  if (typeof deps.readRestaurants !== 'function') return;
  await enqueueDeliveryForAcceptedOrder(order, {
    readRestaurants: deps.readRestaurants,
    readDeliveryZones: deps.readDeliveryZones,
    readDeliveryRequests: deps.readDeliveryRequests,
    writeDeliveryRequests: deps.writeDeliveryRequests,
    readDrivers: deps.readDrivers,
  });
}

async function handlePosRoutes(req, res, url, deps) {
  const {
    readBody,
    sendJson,
    authError,
    parseAuthHeader,
    requireAuth,
    isSuperAdmin,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readSettings,
    readRestaurants,
    readStaffUsers,
    writeStaffUsers,
    readShiftSessions,
    writeShiftSessions,
    readOrders,
    writeOrders,
    readDeliveryRequests,
    readDeliveryZones,
    appendAuditEvents,
    readItemsPage,
  } = deps;

  if (url.pathname === '/api/pos/smart-upsell' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = parseAuthHeader(req);
      let restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        url.searchParams.get('restaurantId') ||
        url.searchParams.get('restaurant_id') ||
        req.headers['x-restaurant-id'] ||
        req.headers['X-Restaurant-Id'] ||
        '';

      if (auth) {
        const scoped = await resolveScopedRestaurantId(req, url, auth);
        if (scoped) restaurantId = scoped;
        if (
          restaurantId &&
          !assertRestaurantAccess(auth, restaurantId, authError, res)
        ) {
          return true;
        }
      }

      restaurantId = restaurantId || DEFAULT_RESTAURANT_ID;
      const settings = await readSettings(restaurantId);
      const cartItems = Array.isArray(body.cartItems)
        ? body.cartItems
        : Array.isArray(body.cart_items)
          ? body.cart_items
          : [];
      const page =
        typeof readItemsPage === 'function'
          ? await readItemsPage({
              restaurantId,
              limit: 200,
              offset: 0,
              lite: true,
            })
          : { items: [] };
      const result = computeSmartUpsell({
        cartItems,
        menuItems: page.items || [],
        cartTotal: body.cartTotal ?? body.cart_total,
        enabled: settings.smartCartUpsellEnabled !== false,
        suggestDrinks: settings.smartUpsellDrinksEnabled !== false,
        suggestSides: settings.smartUpsellSidesEnabled !== false,
        suggestDesserts: settings.smartUpsellDessertsEnabled !== false,
        dessertThreshold:
          Number(settings.dessertUpsellThreshold ?? settings.dessert_upsell_threshold) ||
          5,
      });
      sendJson(res, 200, result);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  if (url.pathname === '/api/pos/staff/login' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const pin = String(body.pin || body.pinCode || '').trim();
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const staff = findStaffByPin(staffUsers, restaurantId, pin, posRoles);
      if (!staff) {
        sendJson(res, 401, { error: 'Invalid PIN' });
        return true;
      }

      sendJson(res, 200, {
        staff: sanitizeStaffPublic(staff),
        permissions: resolveStaffPermissions(staff, posRoles),
        role: findRoleById(posRoles, staff.roleId || staff.role_id),
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  if (url.pathname === '/api/pos/override' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const pin = String(body.pin || body.pinCode || '').trim();
      const action = String(body.action || 'manager_override').trim();
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const restaurants = await readRestaurants();
      const restaurantRecord = restaurants.find((entry) => entry.id === restaurantId);
      const result = verifyManagerOverride({
        staffUsers,
        restaurantId,
        pin,
        roles: posRoles,
        restaurantRecord,
      });

      if (!result.authorized) {
        sendJson(res, 403, { error: 'Manager authorization failed' });
        return true;
      }

      await appendAudit(deps, {
        restaurantId,
        action,
        entityType: 'pos_override',
        entityId: body.entityId || body.entity_id || '',
        performedById: String(body.performedById || body.performed_by_id || auth.restaurantId || 'admin'),
        performedByName: String(body.performedByName || body.performed_by_name || 'Admin'),
        authorizedById: result.staffId,
        authorizedByName: result.staffName,
        metadata: {
          source: result.source,
          roleId: result.roleId,
        },
      });

      sendJson(res, 200, {
        authorized: true,
        authorizedById: result.staffId,
        authorizedByName: result.staffName,
        expiresAt: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  if (url.pathname === '/api/pos/shifts/current' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }

    const cashierId = url.searchParams.get('cashierId') || url.searchParams.get('cashier_id');
    const shifts = filterByRestaurant(await readShiftSessions(), restaurantId);
    const openShift = findOpenShift(shifts, restaurantId, cashierId || null);
    if (!openShift) {
      sendJson(res, 200, { shift: null });
      return true;
    }
    const orders = filterByRestaurant(await readOrders(), restaurantId);
    const requests =
      typeof readDeliveryRequests === 'function' ? await readDeliveryRequests() : [];
    sendJson(res, 200, {
      shift: {
        ...openShift,
        summary: computeShiftSummary(orders, openShift, null, requests),
      },
    });
    return true;
  }

  if (url.pathname === '/api/pos/shifts' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }

    const cashierId = url.searchParams.get('cashierId') || url.searchParams.get('cashier_id');
    const from = url.searchParams.get('from');
    const to = url.searchParams.get('to');
    let shifts = filterByRestaurant(await readShiftSessions(), restaurantId);
    if (cashierId) {
      shifts = shifts.filter(
        (shift) => String(shift.cashierId || shift.cashier_id) === String(cashierId),
      );
    }
    if (from) {
      const fromMs = Date.parse(from);
      shifts = shifts.filter((shift) => Date.parse(shift.openedAt || 0) >= fromMs);
    }
    if (to) {
      const toMs = Date.parse(to);
      shifts = shifts.filter((shift) => Date.parse(shift.openedAt || 0) <= toMs);
    }
    shifts.sort((a, b) => Date.parse(b.openedAt || 0) - Date.parse(a.openedAt || 0));

    // Recompute live summaries so open + historical shifts include payment/channel details.
    const orders = filterByRestaurant(await readOrders(), restaurantId);
    const requests =
      typeof readDeliveryRequests === 'function' ? await readDeliveryRequests() : [];
    const enriched = shifts.map((shift) => {
      const isClosed = String(shift.status || '').toLowerCase() === 'closed';
      const counted = isClosed
        ? shift.closingCashCounted ?? shift.closing_cash_counted ?? null
        : null;
      return {
        ...shift,
        summary: computeShiftSummary(orders, shift, counted, requests),
      };
    });
    sendJson(res, 200, enriched);
    return true;
  }

  if (url.pathname === '/api/pos/shifts/open' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const allShifts = await readShiftSessions();
      const existing = findOpenShift(
        allShifts,
        restaurantId,
        body.cashierId || body.cashier_id || null,
      );
      if (existing) {
        sendJson(res, 409, { error: 'Shift already open for this cashier', shift: existing });
        return true;
      }

      const shift = createOpenShift(body, restaurantId);
      allShifts.unshift(shift);
      await writeShiftSessions(allShifts);
      await appendAudit(deps, {
        restaurantId,
        action: 'shift_open',
        entityType: 'shift',
        entityId: shift.id,
        performedById: shift.cashierId,
        performedByName: shift.cashierName,
        metadata: { openingFloat: shift.openingFloat },
      });
      sendJson(res, 201, shift);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const closeShiftMatch = url.pathname.match(/^\/api\/pos\/shifts\/([^/]+)\/close$/);
  if (closeShiftMatch && req.method === 'POST') {
    try {
      const shiftId = decodeURIComponent(closeShiftMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const shifts = await readShiftSessions();
      let index = shifts.findIndex((shift) => String(shift.id) === shiftId);
      if (index === -1) {
        const cashierId = body.cashierId || body.cashier_id || body.closedById || null;
        const open = findOpenShift(shifts, restaurantId, cashierId);
        if (open) {
          index = shifts.findIndex((shift) => String(shift.id) === String(open.id));
        }
      }
      if (index === -1) {
        try {
          const recovered = createOpenShift(
            {
              id: shiftId,
              cashierId: body.cashierId || body.closedById || body.cashier_id,
              cashierName: body.cashierName || body.closedByName || body.cashier_name,
              openingFloat: body.openingFloat ?? body.opening_float ?? 0,
              roleId: body.roleId || body.role_id,
            },
            restaurantId,
          );
          recovered.id = shiftId;
          shifts.unshift(recovered);
          index = 0;
        } catch (_) {
          sendJson(res, 404, { error: 'Shift not found' });
          return true;
        }
      }
      const current = shifts[index];
      if (String(current.restaurantId || current.restaurant_id) !== String(restaurantId)) {
        authError(res, 403, 'Access denied for this shift');
        return true;
      }
      if (String(current.status || '').toLowerCase() === 'closed') {
        sendJson(res, 409, { error: 'Shift already closed', shift: current });
        return true;
      }

      const orders = filterByRestaurant(await readOrders(), restaurantId);
      const requests =
        typeof readDeliveryRequests === 'function' ? await readDeliveryRequests() : [];
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const restaurants = await readRestaurants();
      const restaurantRecord = restaurants.find((entry) => String(entry.id) === String(restaurantId));
      const guard = enforceShiftClosePendingGuard({
        shift: current,
        orders,
        body,
        auth,
        staffUsers,
        roles: posRoles,
        restaurantRecord,
        isCashier,
        isRestaurantAdmin,
      });
      if (!guard.ok) {
        sendJson(res, guard.status || 403, {
          error: guard.error,
          code: guard.code,
          pendingSummary: guard.summary,
        });
        return true;
      }

      const closed = closeShift(current, body, orders, requests);
      if (guard.summary?.total > 0) {
        closed.pendingCloseGuard = {
          pendingCount: guard.summary.total,
          pickupCount: guard.summary.pickup,
          dineInCount: guard.summary.dineIn,
          onlineCount: guard.summary.online,
          orderIds: guard.summary.orderIds,
          reason: guard.reason,
          authorizedById:
            guard.override?.staffId ||
            (guard.bypassRole ? closed.closedById : null),
          authorizedByName:
            guard.override?.staffName ||
            (guard.bypassRole ? closed.closedByName : null),
          authorizedByRole: guard.override?.roleId || body.roleId || body.role_id || null,
          approvedAt: new Date().toISOString(),
        };
      }
      shifts[index] = closed;
      await writeShiftSessions(shifts);
      await appendAudit(deps, {
        restaurantId,
        action: 'shift_close',
        entityType: 'shift',
        entityId: closed.id,
        performedById: closed.closedById,
        performedByName: closed.closedByName,
        authorizedById: closed.pendingCloseGuard?.authorizedById || null,
        authorizedByName: closed.pendingCloseGuard?.authorizedByName || null,
        metadata: {
          ...(closed.summary || {}),
          pendingCloseGuard: closed.pendingCloseGuard || null,
        },
      });
      sendJson(res, 200, closed);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  if (url.pathname === '/api/pos/staff' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;

    const restaurants = await readRestaurants();
    const nameById = Object.fromEntries(
      (restaurants || []).map((entry) => [String(entry.id), entry.name || entry.id]),
    );
    const withRestaurantName = (entry) => {
      const restaurantId = String(entry.restaurantId || entry.restaurant_id || '');
      return {
        ...sanitizeStaffPublic(entry),
        restaurantId,
        restaurant_id: restaurantId,
        restaurantName: nameById[restaurantId] || restaurantId,
      };
    };

    const wantsAll = isSuperAdmin(auth) && url.searchParams.get('all') === '1';
    if (wantsAll) {
      const staffUsers = (await readStaffUsers()).map(withRestaurantName);
      sendJson(res, 200, staffUsers);
      return true;
    }

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }

    const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId).map(
      withRestaurantName,
    );
    sendJson(res, 200, staffUsers);
    return true;
  }

  if (url.pathname === '/api/pos/staff' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const staffUsers = await readStaffUsers();
      const record = createStaffRecord(body, restaurantId);
      if (
        staffUsers.some(
          (entry) =>
            String(entry.restaurantId || entry.restaurant_id) === String(restaurantId) &&
            String(entry.name).toLowerCase() === String(record.name).toLowerCase(),
        )
      ) {
        sendJson(res, 409, { error: 'Staff name already exists' });
        return true;
      }
      staffUsers.unshift(record);
      await writeStaffUsers(staffUsers);
      sendJson(res, 201, sanitizeStaffPublic(record));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const staffMatch = url.pathname.match(/^\/api\/pos\/staff\/([^/]+)$/);
  if (staffMatch && req.method === 'PATCH') {
    try {
      const staffId = decodeURIComponent(staffMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const staffUsers = await readStaffUsers();
      const index = staffUsers.findIndex((entry) => String(entry.id) === staffId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Staff user not found' });
        return true;
      }
      if (
        String(staffUsers[index].restaurantId || staffUsers[index].restaurant_id) !==
        String(restaurantId)
      ) {
        authError(res, 403, 'Access denied');
        return true;
      }

      staffUsers[index] = updateStaffRecord(staffUsers[index], body);
      await writeStaffUsers(staffUsers);
      sendJson(res, 200, sanitizeStaffPublic(staffUsers[index]));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const deliveryContactMatch = url.pathname.match(
    /^\/api\/orders\/([^/]+)\/delivery-contact$/,
  );
  if (deliveryContactMatch && req.method === 'PATCH') {
    try {
      const orderId = decodeURIComponent(deliveryContactMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;
      const financialKeys = [
        'totalPrice',
        'total_price',
        'subtotal',
        'items',
        'unitPrice',
        'unit_price',
        'deliveryFee',
        'delivery_fee',
        'discountAmount',
        'discount_amount',
        'customerPayableTotal',
        'customer_payable_total',
        'netMerchantSales',
        'net_merchant_sales',
        'priceLocked',
        'zoneDeliveryFee',
        'zone_delivery_fee',
      ];
      if (financialKeys.some((key) => Object.prototype.hasOwnProperty.call(body, key))) {
        sendJson(res, 400, {
          error: 'Delivery contact updates cannot change financial amounts',
        });
        return true;
      }
      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }
      const restaurantId =
        orders[index].restaurant_id ||
        orders[index].restaurantId ||
        deps.DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
      const text = (value, max) =>
        String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, max);
      const previous = orders[index];
      const next = {
        ...previous,
        customerName:
          body.customerName == null
            ? previous.customerName
            : text(body.customerName, 200) || previous.customerName,
        phone: body.phone == null ? previous.phone : text(body.phone, 60),
        address:
          body.address == null ? previous.address : text(body.address, 500),
        deliveryInstructions:
          body.deliveryInstructions == null && body.delivery_instructions == null
            ? previous.deliveryInstructions || previous.delivery_instructions || ''
            : text(body.deliveryInstructions ?? body.delivery_instructions, 500),
        updatedAt: new Date().toISOString(),
      };
      next.delivery_instructions = next.deliveryInstructions;
      const zoneId = text(body.deliveryZoneId ?? body.delivery_zone_id, 80);
      const routed =
        body.deliveryZoneId == null && body.delivery_zone_id == null
          ? next
          : await applyCashierDeliveryZone(next, zoneId, {
              restaurantId,
              auth,
              readDeliveryZones,
            });
      const saved = {
        ...routed,
        ...frozenOrderFinancials(previous),
      };
      const linked =
        typeof deps.rememberMenuProCustomer === 'function'
          ? await deps.rememberMenuProCustomer(saved, restaurantId)
          : saved;
      const stored = {
        ...linked,
        ...frozenOrderFinancials(previous),
      };
      orders[index] = stored;
      await writeOrders(orders);
      await syncZoneDriverDispatch(stored, deps);
      await appendAudit(deps, {
        restaurantId,
        action: 'delivery_contact_updated',
        entityType: 'order_audit_events',
        entityId: orderId,
        performedById: String(body.performedById || auth.staffId || 'cashier'),
        performedByName: String(body.performedByName || auth.staffName || 'Cashier'),
        metadata: {
          address: stored.address,
          phone: stored.phone,
          deliveryInstructions: stored.deliveryInstructions,
          deliveryZoneId: stored.deliveryZoneId || '',
          targetKitchenId: stored.targetKitchenId || '',
          financialsUnchanged: true,
        },
      });
      sendJson(res, 200, stored);
    } catch (error) {
      sendJson(res, Number(error.statusCode) || 400, {
        error: error.message || 'Invalid payload',
      });
    }
    return true;
  }

  const settlementMatch = url.pathname.match(
    /^\/api\/orders\/([^/]+)\/settlement-correction$/,
  );
  if (settlementMatch && req.method === 'PATCH') {
    try {
      const orderId = decodeURIComponent(settlementMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;
      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }
      const previous = orders[index];
      if (!isPlatformOrder(previous)) {
        sendJson(res, 400, { error: 'Settlement correction is for platform orders only' });
        return true;
      }
      const restaurantId =
        previous.restaurant_id || previous.restaurantId || deps.DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
      const paymentMethod = normalizeCashierSettlementMethod(
        body.paymentMethod || body.payment_method,
      );
      if (!paymentMethod) {
        sendJson(res, 400, { error: 'Payment method must be Cash or KNET' });
        return true;
      }
      const invoiceAmount = money(body.invoiceAmount ?? body.invoice_amount, NaN);
      if (!Number.isFinite(invoiceAmount) || invoiceAmount > 100000) {
        sendJson(res, 400, { error: 'Invoice amount is invalid' });
        return true;
      }
      let fee = money(previous.deliveryFee ?? previous.delivery_fee);
      let discount = money(previous.discountAmount ?? previous.discount_amount);
      let subtotal = Number((invoiceAmount - fee + discount).toFixed(3));
      if (subtotal < 0) {
        fee = 0;
        discount = 0;
        subtotal = invoiceAmount;
      }
      const netMerchant = Number(Math.max(0, subtotal - discount).toFixed(3));
      const now = new Date().toISOString();
      const next = {
        ...previous,
        paymentMethod,
        payment_method: paymentMethod,
        subtotal,
        deliveryFee: fee,
        delivery_fee: fee,
        discountAmount: discount,
        discount_amount: discount,
        customerPayableTotal: invoiceAmount,
        customer_payable_total: invoiceAmount,
        netMerchantSales: netMerchant,
        net_merchant_sales: netMerchant,
        totalPrice: invoiceAmount,
        total_price: invoiceAmount,
        priceLocked: true,
        settlementCorrectedByCashier: true,
        settlement_corrected_by_cashier: true,
        settlementCorrectedAt: now,
        updatedAt: now,
      };
      orders[index] = next;
      await writeOrders(orders);
      if (
        typeof deps.readDeliveryRequests === 'function' &&
        typeof deps.writeDeliveryRequests === 'function'
      ) {
        const requests = await deps.readDeliveryRequests();
        const requestIndex = (requests || []).findIndex((row) => {
          if (String(row.order_id || row.orderId) !== orderId) return false;
          return !['delivered', 'cancelled'].includes(String(row.status || ''));
        });
        if (requestIndex >= 0) {
          const updatedRequests = [...requests];
          updatedRequests[requestIndex] = {
            ...updatedRequests[requestIndex],
            payment_method: paymentMethod,
            cash_to_collect: paymentMethod === 'Cash' ? invoiceAmount : 0,
            updated_at: now,
          };
          await deps.writeDeliveryRequests(updatedRequests);
        }
      }
      await appendAudit(deps, {
        restaurantId,
        action: 'platform_settlement_corrected',
        entityType: 'order_audit_events',
        entityId: orderId,
        performedById: String(body.performedById || auth.staffId || 'cashier'),
        performedByName: String(body.performedByName || auth.staffName || 'Cashier'),
        metadata: {
          previousPayment: previous.paymentMethod || previous.payment_method || '',
          paymentMethod,
          previousTotal: previous.totalPrice ?? previous.total_price,
          invoiceAmount,
        },
      });
      sendJson(res, 200, next);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const priceAdjustMatch = url.pathname.match(
    /^\/api\/orders\/([^/]+)\/price-adjustment$/,
  );
  if (priceAdjustMatch && req.method === 'PATCH') {
    try {
      const orderId = decodeURIComponent(priceAdjustMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;
      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }
      const previous = orders[index];
      if (!isPlatformOrder(previous)) {
        sendJson(res, 400, { error: 'Price lock applies to platform orders only' });
        return true;
      }
      const restaurantId =
        previous.restaurant_id || previous.restaurantId || deps.DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
      const pin = String(body.managerPin || body.manager_pin || body.pin || '').trim();
      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const restaurants = await readRestaurants();
      const restaurantRecord = restaurants.find((entry) => entry.id === restaurantId);
      const override = verifyManagerOverride({
        staffUsers,
        restaurantId,
        pin,
        roles: posRoles,
        restaurantRecord,
      });
      if (!override.authorized) {
        sendJson(res, 403, {
          error: 'Manager PIN required to change platform order prices',
        });
        return true;
      }
      const items = Array.isArray(body.items) ? body.items : previous.items;
      const itemsTotal = (Array.isArray(items) ? items : []).reduce((sum, item) => {
        const line = Number(item?.lineTotal ?? item?.line_total);
        if (Number.isFinite(line)) return sum + line;
        const qty = Math.max(1, Number(item?.quantity) || 1);
        return sum + (Number(item?.unitPrice ?? item?.unit_price) || 0) * qty;
      }, 0);
      const dual = computePlatformDualTotals({
        itemsTotal,
        deliveryFee:
          body.deliveryFee ?? body.delivery_fee ?? previous.deliveryFee ?? previous.delivery_fee,
        discount:
          body.discountAmount ??
          body.discount_amount ??
          previous.discountAmount ??
          previous.discount_amount,
      });
      const next = {
        ...previous,
        items,
        subtotal: dual.itemsTotal,
        deliveryFee: dual.deliveryFee,
        delivery_fee: dual.deliveryFee,
        discountAmount: dual.discountAmount,
        discount_amount: dual.discountAmount,
        customerPayableTotal: dual.customerPayableTotal,
        customer_payable_total: dual.customerPayableTotal,
        netMerchantSales: dual.netMerchantSales,
        net_merchant_sales: dual.netMerchantSales,
        totalPrice: dual.customerPayableTotal,
        total_price: dual.customerPayableTotal,
        priceLocked: true,
        updatedAt: new Date().toISOString(),
      };
      orders[index] = next;
      await writeOrders(orders);
      await appendAudit(deps, {
        restaurantId,
        action: 'platform_price_adjustment',
        entityType: 'order_audit_events',
        entityId: orderId,
        performedById: String(body.performedById || 'cashier'),
        performedByName: String(body.performedByName || 'Cashier'),
        authorizedById: override.staffId,
        authorizedByName: override.staffName,
        metadata: {
          reason: String(body.reason || '').slice(0, 300),
          previousTotal: previous.totalPrice ?? previous.total_price,
          customerPayableTotal: dual.customerPayableTotal,
          netMerchantSales: dual.netMerchantSales,
        },
      });
      sendJson(res, 200, next);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const pickupSettleMatch = url.pathname.match(
    /^\/api\/orders\/([^/]+)\/pickup-settle$/,
  );
  if (pickupSettleMatch && req.method === 'PATCH') {
    try {
      const orderId = decodeURIComponent(pickupSettleMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }

      const restaurantId =
        orders[index].restaurant_id ||
        orders[index].restaurantId ||
        deps.DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      if (!isPendingPaymentOrder(orders[index])) {
        sendJson(res, 409, { error: 'الطلب ليس معلّق دفع استلام' });
        return true;
      }

      const paymentMethod = normalizeCashierSettlementMethod(
        body.paymentMethod || body.payment_method || '',
      );
      if (!paymentMethod) {
        sendJson(res, 400, { error: 'طريقة الدفع مطلوبة' });
        return true;
      }

      const shiftId = String(body.shiftId || body.shift_id || '').trim();
      const cashierId = String(body.cashierId || body.cashier_id || '').trim();
      const cashierName = String(
        body.cashierName || body.cashier_name || '',
      ).trim();
      const now = new Date().toISOString();
      const heldShift =
        orders[index].heldShiftId ||
        orders[index].held_shift_id ||
        orders[index].shiftId ||
        orders[index].shift_id ||
        null;

      let next = {
        ...orders[index],
        paymentMethod: paymentMethod,
        payment_method: paymentMethod,
        paymentStatus: 'paid',
        payment_status: 'paid',
        paidAt: now,
        paid_at: now,
        status: 'delivered',
        shiftId: shiftId || orders[index].shiftId || orders[index].shift_id,
        shift_id: shiftId || orders[index].shiftId || orders[index].shift_id,
        cashierId: cashierId || orders[index].cashierId,
        cashier_id: cashierId || orders[index].cashier_id,
        cashierName: cashierName || orders[index].cashierName,
        cashier_name: cashierName || orders[index].cashier_name,
        heldShiftId: heldShift,
        held_shift_id: heldShift,
        updatedAt: now,
      };

      const previousItems = orders[index].items || [];
      if (Array.isArray(body.items) && body.items.length > 0) {
        const lock = await enforceKitchenItemMutation({
          previousItems,
          nextItems: body.items,
          body,
          auth,
          restaurantId,
          deps,
          context: {
            entityType: 'order',
            entityId: orderId,
            orderType: 'pickup',
          },
        });
        if (!lock.ok) {
          sendJson(res, lock.status || 403, {
            error: lock.error,
            code: lock.code,
            violations: lock.violations,
          });
          return true;
        }
        next.items = body.items.map((line) => normalizeKitchenLine(line));
        if (lock.auditEvents?.length) {
          for (const event of lock.auditEvents) {
            await appendAudit(deps, event);
          }
          next = stampOrderKitchenVoidNotice(next, lock.violations);
        }
      }
      const total = Number(body.totalPrice ?? body.total_price);
      if (Number.isFinite(total) && total >= 0) {
        next.totalPrice = money(total);
        next.total_price = money(total);
      }
      const subtotal = Number(body.subtotal);
      if (Number.isFinite(subtotal) && subtotal >= 0) {
        next.subtotal = money(subtotal);
      }

      orders[index] = next;
      await writeOrders(orders);
      await appendAudit(deps, {
        restaurantId,
        action: 'pickup_settle',
        entityType: 'order',
        entityId: orderId,
        performedById: cashierId || 'cashier',
        performedByName: cashierName || 'Cashier',
        metadata: {
          paymentMethod,
          shiftId: next.shiftId,
          totalPrice: next.totalPrice,
        },
      });
      sendJson(res, 200, next);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const pickupHoldUpdateMatch = url.pathname.match(
    /^\/api\/orders\/([^/]+)\/pickup-hold$/,
  );
  if (pickupHoldUpdateMatch && req.method === 'PATCH') {
    try {
      const orderId = decodeURIComponent(pickupHoldUpdateMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }

      const restaurantId =
        orders[index].restaurant_id ||
        orders[index].restaurantId ||
        deps.DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      if (!isPendingPaymentOrder(orders[index])) {
        sendJson(res, 409, { error: 'الطلب ليس معلّق دفع استلام' });
        return true;
      }

      const now = new Date().toISOString();
      let next = { ...orders[index], updatedAt: now };
      const previousItems = orders[index].items || [];
      if (Array.isArray(body.items) && body.items.length > 0) {
        const lock = await enforceKitchenItemMutation({
          previousItems,
          nextItems: body.items,
          body,
          auth,
          restaurantId,
          deps,
          context: {
            entityType: 'order',
            entityId: orderId,
            orderType: 'pickup',
          },
        });
        if (!lock.ok) {
          sendJson(res, lock.status || 403, {
            error: lock.error,
            code: lock.code,
            violations: lock.violations,
          });
          return true;
        }
        let normalized = body.items.map((line) => normalizeKitchenLine(line));
        if (
          body.markKitchenSent === true ||
          body.kitchenDispatched === true ||
          body.kitchen_dispatched === true
        ) {
          normalized = stampKitchenSent(normalized, { sentAt: now, onlyUnsent: true });
        }
        next.items = normalized;
        if (lock.auditEvents?.length) {
          for (const event of lock.auditEvents) {
            await appendAudit(deps, event);
          }
          next = stampOrderKitchenVoidNotice(next, lock.violations);
        }
      } else if (
        body.markKitchenSent === true ||
        body.kitchenDispatched === true ||
        body.kitchen_dispatched === true
      ) {
        next.items = stampKitchenSent(previousItems, { sentAt: now, onlyUnsent: true });
      }
      const total = Number(body.totalPrice ?? body.total_price);
      if (Number.isFinite(total) && total >= 0) {
        next.totalPrice = money(total);
        next.total_price = money(total);
      }
      const subtotal = Number(body.subtotal);
      if (Number.isFinite(subtotal) && subtotal >= 0) {
        next.subtotal = money(subtotal);
      }
      if (body.paymentStatus) {
        const normalized = normalizePaymentStatus(body.paymentStatus);
        if (normalized) {
          next.paymentStatus = normalized;
          next.payment_status = normalized;
        }
      }

      orders[index] = next;
      await writeOrders(orders);
      sendJson(res, 200, next);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const voidOrderMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/void$/);
  if (voidOrderMatch && req.method === 'PATCH') {
    try {
      const orderId = decodeURIComponent(voidOrderMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      if (isSuperAdmin(auth)) {
        authError(res, 403, 'Orders are managed by restaurant admins only');
        return true;
      }

      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }

      const restaurantId =
        orders[index].restaurant_id || orders[index].restaurantId || deps.DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      if (String(orders[index].status || '').toLowerCase() === 'cancelled') {
        sendJson(res, 409, { error: 'Order already voided' });
        return true;
      }

      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const performedById = String(body.performedById || body.performed_by_id || '').trim();
      const performedByName = String(body.performedByName || body.performed_by_name || '').trim();
      const performer = staffUsers.find((entry) => String(entry.id) === performedById);
      const performerAllowed =
        performer &&
        resolveStaffPermissions(performer, posRoles)[PERMISSION_KEYS.VOID_ORDERS] === true;
      const platformOrder = isPlatformOrder(orders[index]);

      let authorizedById = body.authorizedById || body.authorized_by_id || null;
      let authorizedByName = body.authorizedByName || body.authorized_by_name || null;

      if (!performerAllowed || platformOrder) {
        const pin = String(body.managerPin || body.manager_pin || body.pin || '').trim();
        const restaurants = await readRestaurants();
        const restaurantRecord = restaurants.find((entry) => entry.id === restaurantId);
        const override = verifyManagerOverride({
          staffUsers,
          restaurantId,
          pin,
          roles: posRoles,
          restaurantRecord,
        });
        if (!override.authorized) {
          sendJson(res, 403, { error: 'Manager override required to void order' });
          return true;
        }
        authorizedById = override.staffId;
        authorizedByName = override.staffName;
      }

      const now = new Date().toISOString();
      orders[index] = {
        ...orders[index],
        status: 'cancelled',
        voidedAt: now,
        voidReason: String(body.reason || body.voidReason || '').trim(),
        voidedById: performedById || null,
        voidedByName: performedByName || null,
        voidAuthorizedById: authorizedById,
        voidAuthorizedByName: authorizedByName,
      };
      await writeOrders(orders);
      await appendAudit(deps, {
        restaurantId,
        action: 'order_void',
        entityType: 'order',
        entityId: orderId,
        performedById: performedById || 'admin',
        performedByName: performedByName || 'Admin',
        authorizedById,
        authorizedByName,
        metadata: { reason: orders[index].voidReason },
      });
      sendJson(res, 200, orders[index]);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const refundOrderMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/refund$/);
  if (refundOrderMatch && req.method === 'PATCH') {
    try {
      const orderId = decodeURIComponent(refundOrderMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      if (isSuperAdmin(auth)) {
        authError(res, 403, 'Orders are managed by restaurant admins only');
        return true;
      }

      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }

      const restaurantId =
        orders[index].restaurant_id || orders[index].restaurantId || deps.DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const refundAmount = Number(body.refundAmount ?? body.refund_amount ?? 0) || 0;
      if (refundAmount <= 0) {
        sendJson(res, 400, { error: 'refundAmount must be greater than zero' });
        return true;
      }

      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const performedById = String(body.performedById || body.performed_by_id || '').trim();
      const performedByName = String(body.performedByName || body.performed_by_name || '').trim();
      const performer = staffUsers.find((entry) => String(entry.id) === performedById);
      const performerAllowed =
        performer &&
        resolveStaffPermissions(performer, posRoles)[PERMISSION_KEYS.PROCESS_REFUNDS] === true;

      let authorizedById = body.authorizedById || body.authorized_by_id || null;
      let authorizedByName = body.authorizedByName || body.authorized_by_name || null;

      if (!performerAllowed) {
        const pin = String(body.managerPin || body.manager_pin || body.pin || '').trim();
        const restaurants = await readRestaurants();
        const restaurantRecord = restaurants.find((entry) => entry.id === restaurantId);
        const override = verifyManagerOverride({
          staffUsers,
          restaurantId,
          pin,
          roles: posRoles,
          restaurantRecord,
        });
        if (!override.authorized) {
          sendJson(res, 403, { error: 'Manager override required to process refund' });
          return true;
        }
        authorizedById = override.staffId;
        authorizedByName = override.staffName;
      }

      const now = new Date().toISOString();
      const existingRefund = Number(orders[index].refundAmount ?? orders[index].refund_amount ?? 0) || 0;
      orders[index] = {
        ...orders[index],
        refundAmount: existingRefund + refundAmount,
        refundReason: String(body.reason || body.refundReason || '').trim(),
        refundedAt: now,
        refundedById: performedById || null,
        refundedByName: performedByName || null,
        refundAuthorizedById: authorizedById,
        refundAuthorizedByName: authorizedByName,
      };
      await writeOrders(orders);
      await appendAudit(deps, {
        restaurantId,
        action: 'order_refund',
        entityType: 'order',
        entityId: orderId,
        performedById: performedById || 'admin',
        performedByName: performedByName || 'Admin',
        authorizedById,
        authorizedByName,
        metadata: { refundAmount, reason: orders[index].refundReason },
      });
      sendJson(res, 200, orders[index]);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  return false;
}

module.exports = {
  handlePosRoutes,
  parsePosSettings,
  PERMISSION_KEYS,
};
