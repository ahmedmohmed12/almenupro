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
  return prev === 'pending';
}

function shouldAutoBindShift(order, previousStatus, nextStatus) {
  if (orderShiftId(order)) return false;
  if (!isCashOnDeliveryOrder(order)) return false;
  return isAcceptanceTransition(previousStatus, nextStatus);
}

function shouldAdjustShiftOnCancel(order, previousStatus) {
  if (String(previousStatus || '').toLowerCase() === 'cancelled') return false;
  if (!orderShiftId(order)) return false;
  if (!isCashPayment(order.paymentMethod || order.payment_method || '')) return false;
  return true;
}

function resolveBindingShift(shifts, restaurantId, auth = {}, body = {}) {
  const scoped = (shifts || []).filter(
    (shift) =>
      String(shift.restaurantId || shift.restaurant_id) === String(restaurantId) &&
      String(shift.status || '').toLowerCase() === 'open',
  );
  if (scoped.length === 0) return null;

  const cashierId =
    String(body.cashierId || body.cashier_id || auth.staffId || '').trim() || null;
  if (cashierId) {
    const match = scoped.find(
      (shift) => String(shift.cashierId || shift.cashier_id) === cashierId,
    );
    if (match) return match;
  }

  return scoped.sort(
    (a, b) => Date.parse(b.openedAt || b.opened_at || 0) - Date.parse(a.openedAt || a.opened_at || 0),
  )[0];
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

function bindOrderToShift(order, shift, auth = {}) {
  const now = new Date().toISOString();
  return {
    ...order,
    shiftId: shift.id,
    shift_id: shift.id,
    cashierId: shift.cashierId || shift.cashier_id || auth.staffId || null,
    cashier_id: shift.cashierId || shift.cashier_id || auth.staffId || null,
    cashierName: shift.cashierName || shift.cashier_name || auth.staffName || null,
    cashier_name: shift.cashierName || shift.cashier_name || auth.staffName || null,
    shiftBoundAt: order.shiftBoundAt || order.shift_bound_at || now,
    shift_bound_at: order.shiftBoundAt || order.shift_bound_at || now,
    cashConfirmedAt: now,
    cash_confirmed_at: now,
  };
}

function applyShiftBindingOnAccept({
  order,
  previousStatus,
  nextStatus,
  shifts,
  restaurantId,
  auth = {},
  body = {},
}) {
  if (!shouldAutoBindShift(order, previousStatus, nextStatus)) {
    return { order, shifts, bound: false };
  }

  const shift = resolveBindingShift(shifts, restaurantId, auth, body);
  if (!shift) {
    return { order, shifts, bound: false, reason: 'NO_OPEN_SHIFT' };
  }

  const amount = orderTotal(order);
  const shiftIndex = shifts.findIndex((entry) => String(entry.id) === String(shift.id));
  const nextShifts = [...shifts];
  if (shiftIndex >= 0) {
    nextShifts[shiftIndex] = adjustShiftCashCollected(nextShifts[shiftIndex], amount);
  }

  return {
    order: bindOrderToShift(order, shift, auth),
    shifts: nextShifts,
    bound: true,
    shiftId: shift.id,
    amount,
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
  orderTotal,
};
