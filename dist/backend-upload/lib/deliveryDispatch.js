'use strict';

const { randomUUID } = require('crypto');

const STATUSES = [
  'pending',
  'accepted',
  'rejected_by_all',
  'picked_up',
  'on_the_way',
  'delivered',
  'cancelled',
];

const FLEET_NOTIFY_LIMIT = 5;
const OFFER_MS = 45000;
const SEARCH_TIMEOUT_MS = 90000;

function toNum(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function haversineKm(a, b) {
  if (!a || !b) return null;
  const lat1 = toNum(a.lat ?? a.latitude, NaN);
  const lng1 = toNum(a.lng ?? a.longitude, NaN);
  const lat2 = toNum(b.lat ?? b.latitude, NaN);
  const lng2 = toNum(b.lng ?? b.longitude, NaN);
  if (![lat1, lng1, lat2, lng2].every(Number.isFinite)) return null;
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}

function geoPoint(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const lat = toNum(raw.lat ?? raw.latitude, NaN);
  const lng = toNum(raw.lng ?? raw.longitude, NaN);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

function restaurantLocation(restaurant = {}) {
  return geoPoint(restaurant.location) || geoPoint(restaurant) || null;
}

function regionKey(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_');
}

function allowedRegionList(raw) {
  const src = raw.allowed_delivery_regions || raw.allowedDeliveryRegions || [];
  if (!Array.isArray(src)) {
    const asString = String(src || '').trim();
    if (!asString) return [];
    return [...new Set(asString.split(/[,،]/).map((part) => regionKey(part)).filter(Boolean))];
  }
  return [...new Set(src.map((entry) => regionKey(entry)).filter(Boolean))];
}

function assignedRegionMap(raw = {}) {
  const map = {};
  const incoming = raw.assigned_regions || raw.assignedRegions;
  if (incoming && typeof incoming === 'object' && !Array.isArray(incoming)) {
    for (const [key, value] of Object.entries(incoming)) {
      const normalized = regionKey(key);
      if (normalized) map[normalized] = value === true;
    }
    return map;
  }
  for (const key of allowedRegionList(raw)) {
    map[key] = true;
  }
  return map;
}

function allowedFromAssigned(map = {}) {
  return Object.keys(map).filter((key) => map[key] === true);
}

function regionAliases(regionId, regionName) {
  const id = regionKey(regionId);
  const name = regionKey(regionName);
  const parts = id.split(/[_\-/]/).filter((part) => part.length > 1);
  return new Set([id, name, ...parts].filter(Boolean));
}

function driverCoversRegion(driver, regionId, regionName) {
  const map = assignedRegionMap(driver);
  const aliases = regionAliases(regionId, regionName);
  return Object.entries(map).some(([key, on]) => {
    if (on !== true || !key) return false;
    if (aliases.has(key)) return true;
    return [...aliases].some((alias) => alias.includes(key) || key.includes(alias));
  });
}

function normalizeDriver(raw = {}, restaurantId = '') {
  const loc = geoPoint(
    raw.current_location || raw.currentLocation || raw.last_location || raw.lastLocation,
  );
  const now = new Date().toISOString();
  const rest = String(raw.restaurant_id || raw.restaurantId || restaurantId || '').trim();
  const assigned = assignedRegionMap(raw);
  const pin = String(raw.pin || raw.pinCode || raw.pin_code || '').trim();
  let pinHash = String(raw.pin_hash || raw.pinHash || '').trim();
  if (/^\d{4}$/.test(pin)) {
    try {
      pinHash = require('./staffUsers').hashPin(pin, 'fleet');
    } catch (_) {}
  }
  return {
    id: String(raw.id || raw.driver_id || `drv_${randomUUID()}`),
    restaurant_id: rest || null,
    restaurantId: rest || null,
    name: String(raw.name || '').trim().slice(0, 80),
    phone: String(raw.phone || '').trim().slice(0, 40),
    civil_id: String(raw.civil_id || raw.civilId || '').trim().slice(0, 20),
    civil_id_photo_url: String(raw.civil_id_photo_url || raw.civilIdPhotoUrl || '').trim(),
    license_photo_url: String(raw.license_photo_url || raw.licensePhotoUrl || '').trim(),
    is_online: raw.is_online === true || raw.isOnline === true,
    is_busy: raw.is_busy === true || raw.isBusy === true,
    current_location: loc,
    last_location: loc,
    fcm_token: String(raw.fcm_token || raw.fcmToken || '').trim(),
    assigned_regions: assigned,
    allowed_delivery_regions: allowedFromAssigned(assigned),
    staff_id: String(raw.staff_id || raw.staffId || '').trim() || null,
    pin_hash: pinHash,
    last_updated: raw.last_updated || raw.lastUpdated || now,
    available_since: raw.available_since || raw.availableSince || null,
    suspended_until: raw.suspended_until || raw.suspendedUntil || null,
    financial_ledger: Array.isArray(raw.financial_ledger) ? raw.financial_ledger : [],
    createdAt: raw.createdAt || now,
  };
}

function publicDriver(driver) {
  return {
    id: driver.id,
    driver_id: driver.id,
    restaurantId: driver.restaurantId || driver.restaurant_id || null,
    name: driver.name,
    phone: driver.phone,
    civil_id: driver.civil_id || '',
    civil_id_photo_url: driver.civil_id_photo_url || '',
    license_photo_url: driver.license_photo_url || '',
    is_online: Boolean(driver.is_online),
    is_busy: Boolean(driver.is_busy),
    current_location: driver.current_location || driver.last_location || null,
    last_location: driver.last_location || driver.current_location || null,
    assigned_regions: driver.assigned_regions || {},
    allowed_delivery_regions: driver.allowed_delivery_regions || [],
    last_updated: driver.last_updated,
    available_since: driver.available_since || null,
    suspended_until: driver.suspended_until || null,
    staff_id: driver.staff_id || null,
  };
}

function stringIdList(raw) {
  return Array.isArray(raw) ? raw.map(String) : [];
}

function normalizeDeliveryRequest(raw = {}, restaurantId = '') {
  const now = new Date().toISOString();
  const statusRaw = String(raw.status || 'pending').toLowerCase();
  const status = STATUSES.includes(statusRaw) ? statusRaw : 'pending';
  const restLoc = geoPoint(raw.restaurant_location || raw.restaurantLocation);
  const custLoc = geoPoint(raw.customer_location || raw.customerLocation);
  const regionId = String(
    raw.destination_region_id ||
      raw.destinationRegionId ||
      raw.region_id ||
      raw.regionId ||
      raw.deliveryZoneId ||
      '',
  ).trim() || null;
  return {
    id: String(raw.id || raw.request_id || `del_${randomUUID()}`),
    restaurant_id: String(raw.restaurant_id || raw.restaurantId || restaurantId || ''),
    restaurantId: String(raw.restaurant_id || raw.restaurantId || restaurantId || ''),
    restaurantName: String(raw.restaurantName || raw.restaurant_name || '').trim(),
    order_id: raw.order_id || raw.orderId || null,
    is_express: raw.is_express === true || raw.isExpress === true,
    region_id: regionId,
    destination_region_id: regionId,
    region_name: String(raw.region_name || raw.regionName || '').trim(),
    customer_fee: toNum(raw.customer_fee ?? raw.customerFee, 0),
    driver_fee: toNum(raw.driver_fee ?? raw.driverFee, 0),
    platform_margin: toNum(raw.platform_margin ?? raw.platformMargin, 0),
    cash_to_collect: toNum(raw.cash_to_collect ?? raw.cashToCollect, 0),
    status,
    assigned_driver_id: raw.assigned_driver_id || raw.assignedDriverId || null,
    assigned_driver_name: raw.assigned_driver_name || raw.assignedDriverName || null,
    assigned_driver_phone: raw.assigned_driver_phone || raw.assignedDriverPhone || null,
    restaurant_location: restLoc,
    customer_location: custLoc,
    customer_phone: String(raw.customer_phone || raw.customerPhone || '').trim(),
    customer_address: String(raw.customer_address || raw.customerAddress || '').trim(),
    payment_method: String(raw.payment_method || raw.paymentMethod || '').trim(),
    handshake_payment_kind: raw.handshake_payment_kind || raw.handshakePaymentKind || null,
    handshake_order_total: toNum(raw.handshake_order_total ?? raw.handshakeOrderTotal, 0),
    handshake_driver_fee: toNum(raw.handshake_driver_fee ?? raw.handshakeDriverFee, toNum(raw.driver_fee, 0)),
    handshake_net_to_cashier: toNum(raw.handshake_net_to_cashier ?? raw.handshakeNetToCashier, 0),
    handshake_cashier_pays_driver: toNum(
      raw.handshake_cashier_pays_driver ?? raw.handshakeCashierPaysDriver,
      0,
    ),
    handshake_collect_from_customer: toNum(
      raw.handshake_collect_from_customer ?? raw.handshakeCollectFromCustomer,
      toNum(raw.cash_to_collect, 0),
    ),
    cashier_handoff_confirmed_at: raw.cashier_handoff_confirmed_at || raw.cashierHandoffConfirmedAt || null,
    driver_handoff_confirmed_at: raw.driver_handoff_confirmed_at || raw.driverHandoffConfirmedAt || null,
    cashier_handoff_by: raw.cashier_handoff_by || raw.cashierHandoffBy || null,
    driver_handoff_by: raw.driver_handoff_by || raw.driverHandoffBy || null,
    search_radius_km: toNum(raw.search_radius_km ?? raw.searchRadiusKm, 5) || 5,
    notified_driver_ids: stringIdList(raw.notified_driver_ids),
    declined_driver_ids: stringIdList(raw.declined_driver_ids || raw.declinedDriverIds),
    offer_expires_at: raw.offer_expires_at || raw.offerExpiresAt || null,
    accepted_at: raw.accepted_at || raw.acceptedAt || null,
    picked_up_at: raw.picked_up_at || raw.pickedUpAt || null,
    on_the_way_at: raw.on_the_way_at || raw.onTheWayAt || null,
    delivered_at: raw.delivered_at || raw.deliveredAt || null,
    admin_delivered: raw.admin_delivered === true,
    admin_delivered_at: raw.admin_delivered_at || raw.adminDeliveredAt || null,
    admin_delivered_by: raw.admin_delivered_by || raw.adminDeliveredBy || null,
    created_at: raw.created_at || raw.createdAt || now,
    updated_at: raw.updated_at || raw.updatedAt || now,
  };
}

function publicRequest(request, { forDriver = false } = {}) {
  const handshake = require('./driverFinance').handshakePublicFields(request);
  const base = {
    id: request.id,
    request_id: request.id,
    restaurantId: request.restaurantId || request.restaurant_id,
    restaurantName: request.restaurantName || '',
    restaurant_name: request.restaurantName || '',
    order_id: request.order_id || null,
    is_express: Boolean(request.is_express),
    region_id: request.region_id,
    destination_region_id: request.destination_region_id || request.region_id,
    region_name: request.region_name,
    driver_fee: request.driver_fee,
    status: request.status,
    assigned_driver_id: request.assigned_driver_id,
    assigned_driver_name: request.assigned_driver_name,
    assigned_driver_phone: request.assigned_driver_phone || null,
    restaurant_location: request.restaurant_location,
    customer_location: request.customer_location,
    customer_phone: request.customer_phone,
    customer_address: request.customer_address,
    search_radius_km: request.search_radius_km,
    offer_expires_at: request.offer_expires_at,
    accepted_at: request.accepted_at || null,
    picked_up_at: request.picked_up_at || null,
    on_the_way_at: request.on_the_way_at || null,
    delivered_at: request.delivered_at || null,
    admin_delivered: Boolean(request.admin_delivered),
    admin_delivered_at: request.admin_delivered_at || null,
    admin_delivered_by: request.admin_delivered_by || null,
    created_at: request.created_at,
    updated_at: request.updated_at,
    ...handshake,
  };
  if (forDriver) return base;
  return {
    ...base,
    customer_fee: request.customer_fee,
    platform_margin: request.platform_margin,
    cash_to_collect: request.cash_to_collect,
    notified_driver_ids: request.notified_driver_ids || [],
    declined_driver_ids: request.declined_driver_ids || [],
  };
}

function feesFromZone(zone = {}) {
  const customer = toNum(zone.deliveryFee ?? zone.delivery_fee ?? zone.customer_delivery_fee, 0);
  const driver = toNum(zone.driverDeliveryFee ?? zone.driver_delivery_fee ?? zone.driver_fee, customer);
  const margin = toNum(
    zone.platformMargin ?? zone.platform_margin,
    Math.max(0, customer - driver),
  );
  return { customer_fee: customer, driver_fee: driver, platform_margin: margin };
}

function isDriverSuspended(driver) {
  const until = Date.parse(driver?.suspended_until || '');
  return Number.isFinite(until) && until > Date.now();
}

function isDriverReceivingJobs(driver) {
  if (!driver) return false;
  if (isDriverSuspended(driver)) return false;
  if (driver.is_online !== true || driver.is_busy === true) return false;
  return true;
}

function idleDriver(driver, nowIso) {
  return {
    ...driver,
    is_busy: false,
    available_since: nowIso,
    last_updated: nowIso,
  };
}

function availableFleetDrivers(drivers, { regionId, regionName, excludeIds = [] } = {}) {
  const excluded = new Set((excludeIds || []).map(String));
  return (drivers || []).filter((row) => {
    if (excluded.has(String(row.id))) return false;
    if (!isDriverReceivingJobs(row)) return false;
    if (!regionId && !regionName) return false;
    return driverCoversRegion(row, regionId, regionName);
  });
}

function rankDriversByDistance(drivers, origin) {
  return [...drivers]
    .map((driver) => ({
      driver,
      km: haversineKm(origin, driver.current_location),
    }))
    .sort((a, b) => {
      if (a.km == null && b.km == null) return 0;
      if (a.km == null) return 1;
      if (b.km == null) return -1;
      return a.km - b.km;
    })
    .map((row) => row.driver);
}

function selectTopFleetDrivers(drivers, request, { limit = FLEET_NOTIFY_LIMIT } = {}) {
  const pool = availableFleetDrivers(drivers, {
    regionId: request.destination_region_id || request.region_id,
    regionName: request.region_name,
    excludeIds: request.declined_driver_ids || [],
  });
  return rankDriversByDistance(pool, request.restaurant_location).slice(0, limit);
}

function availableDrivers(drivers) {
  return availableFleetDrivers(drivers, {});
}

function driversInRadius(drivers, origin, km) {
  if (!origin) return drivers;
  return drivers.filter((driver) => {
    const dist = haversineKm(origin, driver.current_location);
    return dist == null || dist <= km;
  });
}

function tickPending(request, drivers, nowMs) {
  if (request.status !== 'pending') return { request, changed: false, newlyNotified: [] };
  const created = new Date(request.created_at).getTime();
  const elapsed = nowMs - created;
  let next = { ...request };
  let changed = false;
  if (elapsed >= SEARCH_TIMEOUT_MS) {
    next.status = 'rejected_by_all';
    next.offer_expires_at = null;
    changed = true;
    return { request: next, changed, newlyNotified: [] };
  }
  const top = selectTopFleetDrivers(drivers, next, { limit: FLEET_NOTIFY_LIMIT });
  const ids = top.map((row) => String(row.id));
  const prev = (next.notified_driver_ids || []).map(String);
  const newlyNotified = ids.filter((id) => !prev.includes(id));
  const sameSet =
    ids.length === prev.length && ids.every((id) => prev.includes(id));
  if (!sameSet) {
    next.notified_driver_ids = ids;
    if (!next.offer_expires_at) {
      next.offer_expires_at = new Date(nowMs + OFFER_MS).toISOString();
    }
    changed = true;
  }
  next.updated_at = new Date(nowMs).toISOString();
  return { request: next, changed, newlyNotified };
}

module.exports = {
  STATUSES,
  FLEET_NOTIFY_LIMIT,
  haversineKm,
  geoPoint,
  restaurantLocation,
  regionKey,
  allowedRegionList,
  assignedRegionMap,
  allowedFromAssigned,
  driverCoversRegion,
  normalizeDriver,
  publicDriver,
  normalizeDeliveryRequest,
  publicRequest,
  feesFromZone,
  isDriverSuspended,
  isDriverReceivingJobs,
  idleDriver,
  availableDrivers,
  availableFleetDrivers,
  rankDriversByDistance,
  selectTopFleetDrivers,
  driversInRadius,
  tickPending,
};
