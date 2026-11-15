'use strict';

const { haversineKm, isDriverSuspended, publicDriver, publicRequest } = require('./deliveryDispatch');

const ACTIVE = new Set(['accepted', 'picked_up', 'on_the_way']);

function etaMinutes(from, to, fallback = 20) {
  const km = haversineKm(from, to);
  if (km == null) return fallback;
  return Math.max(8, Math.round((km / 25) * 60));
}

function isTripDelayed(request, driver, nowMs = Date.now()) {
  const status = String(request?.status || '');
  if (!ACTIVE.has(status)) return false;
  if (status === 'accepted') {
    const start = Date.parse(request.accepted_at || request.updated_at || 0);
    if (!Number.isFinite(start)) return false;
    const eta = etaMinutes(driver?.current_location || driver?.last_location, request.restaurant_location, 18);
    return nowMs - start > eta * 60 * 1000 * 1.4;
  }
  const start = Date.parse(
    request.picked_up_at || request.on_the_way_at || request.updated_at || 0,
  );
  if (!Number.isFinite(start)) return false;
  const eta = etaMinutes(
    request.restaurant_location || driver?.current_location,
    request.customer_location,
    22,
  );
  return nowMs - start > eta * 60 * 1000 * 1.4;
}

function idleMinutes(driver, nowMs = Date.now()) {
  const start = Date.parse(driver?.available_since || driver?.last_updated || 0);
  if (!Number.isFinite(start) || start > nowMs) return 0;
  return Math.max(0, Math.floor((nowMs - start) / 60000));
}

function opsStatusFor(driver, activeOrders, nowMs = Date.now()) {
  if (isDriverSuspended(driver)) {
    return { key: 'suspended', delayed: false, idle_minutes: 0 };
  }
  const delayed = activeOrders.some((row) => isTripDelayed(row, driver, nowMs));
  const accepted = activeOrders.filter((row) => row.status === 'accepted');
  const delivering = activeOrders.filter((row) => row.status === 'picked_up' || row.status === 'on_the_way');
  if (delivering.length) {
    return { key: delayed ? 'delayed' : 'en_route_customer', delayed, idle_minutes: 0 };
  }
  if (accepted.length) {
    return { key: delayed ? 'delayed' : 'en_route_restaurant', delayed, idle_minutes: 0 };
  }
  if (!driver.is_online) {
    return { key: 'offline', delayed: false, idle_minutes: 0 };
  }
  if (driver.is_busy) {
    return { key: 'busy', delayed: false, idle_minutes: 0 };
  }
  return { key: 'available', delayed: false, idle_minutes: idleMinutes(driver, nowMs) };
}

function buildFleetSnapshot(drivers, requests) {
  const nowMs = Date.now();
  const live = (requests || []).filter((row) => ACTIVE.has(String(row.status || '')));
  const rows = (drivers || []).map((driver) => {
    const activeOrders = live.filter((row) => String(row.assigned_driver_id) === String(driver.id));
    const ops = opsStatusFor(driver, activeOrders, nowMs);
    return {
      ...publicDriver(driver),
      ops_status: ops.key,
      delayed: ops.delayed,
      idle_minutes: ops.idle_minutes,
      active_orders: activeOrders.map((row) => ({
        ...publicRequest(row),
        delayed: isTripDelayed(row, driver, nowMs),
        eta_minutes:
          row.status === 'accepted'
            ? etaMinutes(driver.current_location, row.restaurant_location, 18)
            : etaMinutes(row.restaurant_location || driver.current_location, row.customer_location, 22),
      })),
    };
  });
  const summary = {
    available: rows.filter((row) => row.ops_status === 'available').length,
    picking_up: live.filter((row) => row.status === 'accepted').length,
    delivering: live.filter((row) => row.status === 'picked_up' || row.status === 'on_the_way').length,
    delayed: live.filter((row) => {
      const driver = (drivers || []).find((entry) => String(entry.id) === String(row.assigned_driver_id));
      return isTripDelayed(row, driver, nowMs);
    }).length,
  };
  const needsDriver = (requests || []).filter((row) => {
    const status = String(row.status || '');
    return status === 'pending' || status === 'rejected_by_all';
  });
  summary.needs_driver = needsDriver.length;
  return {
    summary,
    drivers: rows,
    needs_driver: needsDriver.map((row) => publicRequest(row)),
  };
}

function driverHasActiveTrip(requests, driverId) {
  return (requests || []).some(
    (row) =>
      String(row.assigned_driver_id) === String(driverId) && ACTIVE.has(String(row.status || '')),
  );
}

module.exports = {
  ACTIVE,
  buildFleetSnapshot,
  driverHasActiveTrip,
  isTripDelayed,
};
