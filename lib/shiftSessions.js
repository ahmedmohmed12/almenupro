const CASH_PAYMENT_PATTERN = /cash|كاش/i;
const KNET_PAYMENT_PATTERN = /k-?net|knet|كي\s*نت/i;

function isCashPayment(method) {
  return CASH_PAYMENT_PATTERN.test(String(method || ''));
}

function isKnetPayment(method) {
  return KNET_PAYMENT_PATTERN.test(String(method || ''));
}

function isElectronicPayment(method) {
  const value = String(method || '').trim();
  if (!value) return false;
  return !isCashPayment(value);
}

function normalizeShiftSession(raw, restaurantId) {
  const id =
    String(raw.id || '').trim() ||
    `shift_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
  const now = new Date().toISOString();
  return {
    id,
    restaurantId: raw.restaurantId || raw.restaurant_id || restaurantId,
    cashierId: String(raw.cashierId || raw.cashier_id || '').trim(),
    cashierName: String(raw.cashierName || raw.cashier_name || '').trim(),
    roleId: String(raw.roleId || raw.role_id || '').trim(),
    status: String(raw.status || 'open').trim().toLowerCase() === 'closed'
      ? 'closed'
      : 'open',
    openedAt: raw.openedAt || raw.opened_at || now,
    closedAt: raw.closedAt || raw.closed_at || null,
    openingFloat: Number(raw.openingFloat ?? raw.opening_float ?? 0) || 0,
    closingCashCounted:
      raw.closingCashCounted == null && raw.closing_cash_counted == null
        ? null
        : Number(raw.closingCashCounted ?? raw.closing_cash_counted ?? 0) || 0,
    notes: String(raw.notes || '').trim(),
    summary: normalizeShiftSummary(raw.summary),
    closedById: String(raw.closedById || raw.closed_by_id || '').trim() || null,
    closedByName: String(raw.closedByName || raw.closed_by_name || '').trim() || null,
    createdAt: raw.createdAt || now,
    updatedAt: raw.updatedAt || now,
  };
}

function normalizeShiftSummary(raw = {}) {
  return {
    orderCount: Number(raw.orderCount ?? raw.order_count ?? 0) || 0,
    voidCount: Number(raw.voidCount ?? raw.void_count ?? 0) || 0,
    refundCount: Number(raw.refundCount ?? raw.refund_count ?? 0) || 0,
    cashSales: Number(raw.cashSales ?? raw.cash_sales ?? 0) || 0,
    knetSales: Number(raw.knetSales ?? raw.knet_sales ?? 0) || 0,
    electronicSales:
      Number(raw.electronicSales ?? raw.electronic_sales ?? 0) || 0,
    grossSales: Number(raw.grossSales ?? raw.gross_sales ?? 0) || 0,
    discountTotal: Number(raw.discountTotal ?? raw.discount_total ?? 0) || 0,
    refundTotal: Number(raw.refundTotal ?? raw.refund_total ?? 0) || 0,
    expectedCash: Number(raw.expectedCash ?? raw.expected_cash ?? 0) || 0,
    actualCash: Number(raw.actualCash ?? raw.actual_cash ?? 0) || 0,
    discrepancy: Number(raw.discrepancy ?? 0) || 0,
    discrepancyType: String(raw.discrepancyType || raw.discrepancy_type || 'balanced'),
  };
}

function computeShiftSummary(orders, shift, closingCashCounted = null) {
  const shiftId = String(shift.id);
  const scoped = (orders || []).filter(
    (order) => String(order.shiftId || order.shift_id || '') === shiftId,
  );

  let orderCount = 0;
  let voidCount = 0;
  let refundCount = 0;
  let cashSales = 0;
  let knetSales = 0;
  let electronicSales = 0;
  let grossSales = 0;
  let discountTotal = 0;
  let refundTotal = 0;

  for (const order of scoped) {
    const status = String(order.status || '').toLowerCase();
    const paymentMethod = order.paymentMethod || order.payment_method || '';
    const total = Number(order.totalPrice ?? order.total_price ?? 0) || 0;
    const discount = Number(order.discountAmount ?? order.discount_amount ?? 0) || 0;
    const refund = Number(order.refundAmount ?? order.refund_amount ?? 0) || 0;

    discountTotal += discount;
    refundTotal += refund;

    if (status === 'cancelled') {
      voidCount += 1;
      continue;
    }

    if (refund > 0) {
      refundCount += 1;
    }

    orderCount += 1;
    grossSales += total;

    if (isCashPayment(paymentMethod)) {
      cashSales += total;
    } else if (isKnetPayment(paymentMethod)) {
      knetSales += total;
    } else if (isElectronicPayment(paymentMethod)) {
      electronicSales += total;
    }
  }

  const openingFloat = Number(shift.openingFloat ?? shift.opening_float ?? 0) || 0;
  const expectedCash = openingFloat + cashSales - refundTotal;
  const actualCash =
    closingCashCounted == null
      ? null
      : Number(closingCashCounted) || 0;
  const discrepancy =
    actualCash == null ? 0 : Number((actualCash - expectedCash).toFixed(3));
  let discrepancyType = 'balanced';
  if (discrepancy < -0.001) discrepancyType = 'shortage';
  if (discrepancy > 0.001) discrepancyType = 'surplus';

  return normalizeShiftSummary({
    orderCount,
    voidCount,
    refundCount,
    cashSales,
    knetSales,
    electronicSales,
    grossSales,
    discountTotal,
    refundTotal,
    expectedCash,
    actualCash: actualCash ?? 0,
    discrepancy,
    discrepancyType,
  });
}

function findOpenShift(shifts, restaurantId, cashierId = null) {
  return (shifts || []).find((shift) => {
    if (String(shift.restaurantId || shift.restaurant_id) !== String(restaurantId)) {
      return false;
    }
    if (String(shift.status || '').toLowerCase() !== 'open') {
      return false;
    }
    if (cashierId && String(shift.cashierId || shift.cashier_id) !== String(cashierId)) {
      return false;
    }
    return true;
  });
}

function createOpenShift(body = {}, restaurantId) {
  const shift = normalizeShiftSession(
    {
      ...body,
      status: 'open',
      closedAt: null,
      closingCashCounted: null,
    },
    restaurantId,
  );
  if (!shift.cashierId || !shift.cashierName) {
    throw new Error('cashierId and cashierName are required');
  }
  return shift;
}

function closeShift(shift, body = {}, orders = []) {
  const closingCashCounted = Number(
    body.closingCashCounted ?? body.closing_cash_counted ?? 0,
  );
  const summary = computeShiftSummary(orders, shift, closingCashCounted);
  const now = new Date().toISOString();
  return {
    ...shift,
    status: 'closed',
    closedAt: now,
    closingCashCounted,
    notes: String(body.notes || shift.notes || '').trim(),
    summary,
    closedById: String(body.closedById || body.closed_by_id || shift.cashierId || '').trim(),
    closedByName: String(
      body.closedByName || body.closed_by_name || shift.cashierName || '',
    ).trim(),
    updatedAt: now,
  };
}

module.exports = {
  normalizeShiftSession,
  normalizeShiftSummary,
  computeShiftSummary,
  findOpenShift,
  createOpenShift,
  closeShift,
  isCashPayment,
  isKnetPayment,
  isElectronicPayment,
};
