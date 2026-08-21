const {
  findOpenShift,
  isCashPayment,
  normalizeShiftSession,
} = require('./shiftSessions');

const ONLINE_SOURCE_PATTERN = /menu|web|whatsapp|direct|online|site|app/i;
const ACCEPTANCE_STATUSES = new Set(['confirmed', 'preparing', 'ready', 'delivered']);

function orderTotal(order) {
  return Number(order.totalPrice ?? order.total_price ?? 0) || 0;
}

function orderShiftId(order) {
  return String(order.shiftId || order.shift_id || '').trim();
}

function orderSource(order) {
  return String(order.orderSource || order.order_source || '').trim().toLowerCase();
}

function isPosOrder(order) {
  return orderSource(order) === 'pos';
}

function isOnlineOrder(order) {
  if (isPosOrder(order)) return false;
  const source = orderSource(order);
  if (!source) return true;
  return ONLINE_SOURCE_PATTERN.test(source) || source !== 'pos';
}

function isCashOnDeliveryOrder(order) {
  const paymentMethod = order.paymentMethod || order.payment_method || '';
  if (!isCashPayment(paymentMethod)) return false;
  if (isPosOrder(order)) return false;
  return isOnlineOrder(order);
}

function isAcceptanceTransition(previousStatus, nextStatus) {
  const prev = String(previousStatus || 'pending').toLowerCase();
  const next = String(nextStatus || '').toLowerCase();
  if (!ACCEPTANCE_STATUSES.has(next)) return false;
  if (prev === 'cancelled' || prev === 'delivered') return false;
  return prev === 'pending' || prev === 'confirmed' || prev === 'preparing' || prev === 'ready';
}

function shouldAutoBindShift(order, previousStatus, nextStatus, previousOrder = null) {
  if (orderShiftId(previousOrder || {})) return false;
  if (!isOnlineOrder(order)) return false;
  return isAcceptanceTransition(previousStatus, nextStatus);
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const text = String(value == null ? '' : value).trim();
    if (text) return text;
  }
  return '';
}

function attachReceivingCashier(order, previous = {}, body = {}) {
  const nextStatus = String(body.status || order.status || '').toLowerCase();
  const cancellingUnbound =
    nextStatus === 'cancelled' && !orderShiftId(previous || {});
  if (cancellingUnbound) {
    return order;
  }

  const cashierId = firstNonEmpty(
    body.cashierId,
    body.cashier_id,
    order.cashierId,
    order.cashier_id,
    previous.cashierId,
    previous.cashier_id,
  );
  const cashierName = firstNonEmpty(
    body.cashierName,
    body.cashier_name,
    order.cashierName,
    order.cashier_name,
    previous.cashierName,
    previous.cashier_name,
  );
  const shiftId = firstNonEmpty(
    body.shiftId,
    body.shift_id,
    order.shiftId,
    order.shift_id,
    previous.shiftId,
    previous.shift_id,
  );

  return {
    ...order,
    ...(shiftId ? { shiftId, shift_id: shiftId } : {}),
    ...(cashierId ? { cashierId, cashier_id: cashierId } : {}),
    ...(cashierName ? { cashierName, cashier_name: cashierName } : {}),
  };
}

function shouldAdjustShiftOnCancel(order, previousStatus) {
  if (String(previousStatus || '').toLowerCase() === 'cancelled') return false;
  if (!orderShiftId(order)) return false;
  if (!isCashPayment(order.paymentMethod || order.payment_method || '')) return false;
  return true;
}

function resolveBindingShift(shifts, restaurantId, auth = {}, body = {}) {
  const cashierId = firstNonEmpty(
    body.cashierId,
    body.cashier_id,
    auth.staffId,
  );
  const requestedShiftId = firstNonEmpty(body.shiftId, body.shift_id);
  const restaurantIds = new Set(
    [restaurantId, auth.restaurantId, auth.restaurant_id]
      .map((id) => String(id || '').trim())
      .filter(Boolean),
  );

  const open = (shifts || []).filter(
    (shift) => String(shift.status || '').toLowerCase() === 'open',
  );
  const scoped = restaurantIds.size
    ? open.filter((shift) =>
        restaurantIds.has(String(shift.restaurantId || shift.restaurant_id || '')),
      )
    : open;
  const search = scoped.length ? scoped : open;

  if (cashierId) {
    const byCashier = search.find(
      (shift) => String(shift.cashierId || shift.cashier_id) === cashierId,
    );
    if (byCashier) return byCashier;
  }

  if (requestedShiftId) {
    return (
      search.find((shift) => String(shift.id) === requestedShiftId) ||
      open.find((shift) => String(shift.id) === requestedShiftId) ||
      null
    );
  }

  return null;
}

function adjustShiftCashCollected(shift, delta) {
  const normalized = normalizeShiftSession(shift, shift.restaurantId || shift.restaurant_id);
  const current = Number(normalized.cashCollected ?? 0) || 0;
  const next = Number(Math.max(0, current + delta).toFixed(3));
  return {
    ...normalized,
    cashCollected: next,
    updatedAt: new Date().toISOString(),
  };
}

function bindOrderToShift(order, shift, auth = {}, body = {}) {
  const now = new Date().toISOString();
  const cashierName = firstNonEmpty(
    shift.cashierName,
    shift.cashier_name,
    body.cashierName,
    body.cashier_name,
    auth.staffName,
  );
  const cashierId = firstNonEmpty(
    shift.cashierId,
    shift.cashier_id,
    body.cashierId,
    body.cashier_id,
    auth.staffId,
  );
  const cash = isCashPayment(order.paymentMethod || order.payment_method);
  return {
    ...order,
    shiftId: shift.id,
    shift_id: shift.id,
    cashierId: cashierId || null,
    cashier_id: cashierId || null,
    cashierName: cashierName || null,
    cashier_name: cashierName || null,
    shiftBoundAt: order.shiftBoundAt || order.shift_bound_at || now,
    shift_bound_at: order.shiftBoundAt || order.shift_bound_at || now,
    ...(cash
      ? { cashConfirmedAt: now, cash_confirmed_at: now }
      : {}),
  };
}

function applyShiftBindingOnAccept({
  order,
  previousOrder = null,
  previousStatus,
  nextStatus,
  shifts,
  restaurantId,
  auth = {},
  body = {},
}) {
  if (!shouldAutoBindShift(order, previousStatus, nextStatus, previousOrder)) {
    return { order, shifts, bound: false };
  }

  const shift = resolveBindingShift(shifts, restaurantId, auth, body);
  if (!shift) {
    return { order, shifts, bound: false, reason: 'NO_OPEN_SHIFT' };
  }

  const nextShifts = [...shifts];
  if (isCashPayment(order.paymentMethod || order.payment_method)) {
    const amount = orderTotal(order);
    const shiftIndex = shifts.findIndex((entry) => String(entry.id) === String(shift.id));
    if (shiftIndex >= 0) {
      nextShifts[shiftIndex] = adjustShiftCashCollected(nextShifts[shiftIndex], amount);
    }
  }

  return {
    order: bindOrderToShift(order, shift, auth, body),
    shifts: nextShifts,
    bound: true,
    shiftId: shift.id,
  };
}

function applyShiftAdjustmentOnCancel({ order, previousStatus, shifts }) {
  if (!shouldAdjustShiftOnCancel(order, previousStatus)) {
    return { order, shifts, adjusted: false };
  }

  const shiftId = orderShiftId(order);
  const amount = orderTotal(order);
  const shiftIndex = shifts.findIndex((entry) => String(entry.id) === shiftId);
  if (shiftIndex === -1) {
    return { order, shifts, adjusted: false, reason: 'SHIFT_NOT_FOUND' };
  }

  const nextShifts = [...shifts];
  nextShifts[shiftIndex] = adjustShiftCashCollected(nextShifts[shiftIndex], -amount);

  return {
    order,
    shifts: nextShifts,
    adjusted: true,
    shiftId,
    amount: -amount,
  };
}

module.exports = {
  isCashOnDeliveryOrder,
  isAcceptanceTransition,
  shouldAutoBindShift,
  shouldAdjustShiftOnCancel,
  resolveBindingShift,
  bindOrderToShift,
  adjustShiftCashCollected,
  applyShiftBindingOnAccept,
  applyShiftAdjustmentOnCancel,
  attachReceivingCashier,
  orderTotal,
};
