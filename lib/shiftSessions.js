const { orderCountsTowardShiftRevenue } = require('./orderPaymentStatus');

const CASH_PAYMENT_PATTERN = /cash|كاش/i;
const KNET_PAYMENT_PATTERN = /k-?net|knet|كي\s*نت/i;
const ONLINE_SOURCE_PATTERN = /menu|web|whatsapp|direct|online|site|app|qr/i;

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

function resolveOrderType(order) {
  const raw = String(order.orderType || order.order_type || '')
    .trim()
    .toLowerCase()
    .replace(/[_-]/g, '');
  if (raw === 'pickup' || raw === 'takeaway') return 'pickup';
  if (raw === 'dinein') return 'dineIn';
  return 'delivery';
}

function orderSourceValue(order) {
  return String(order.orderSource || order.order_source || '')
    .trim()
    .toLowerCase();
}

function isPosOrderSource(order) {
  const source = orderSourceValue(order);
  if (!source) return false;
  return (
    source === 'pos' ||
    source.startsWith('pos-') ||
    source.startsWith('pos_') ||
    source.includes('cashier')
  );
}

function isHallTableOrder(order) {
  if (resolveOrderType(order) === 'dineIn') return true;
  if (String(order.tableId || order.table_id || '').trim()) return true;
  const source = orderSourceValue(order);
  return (
    source === 'pos-dine-in' ||
    source === 'qr-dine-in' ||
    source.includes('dine-in') ||
    source.includes('dine_in')
  );
}

function isOnlineMenuOrder(order) {
  if (order.createdFromPos || order.created_from_pos) return false;
  if (isPosOrderSource(order)) return false;
  const source = orderSourceValue(order);
  if (!source) return true;
  return ONLINE_SOURCE_PATTERN.test(source) || !isPosOrderSource(order);
}

function classifyOrderChannel(order) {
  if (isHallTableOrder(order)) return 'dineIn';
  if (isOnlineMenuOrder(order)) return 'website';
  if (order.createdFromPos || order.created_from_pos || isPosOrderSource(order)) {
    const type = resolveOrderType(order);
    if (type === 'pickup') return 'takeaway';
    if (type === 'delivery') return 'delivery';
    return 'pos';
  }
  const type = resolveOrderType(order);
  if (type === 'pickup') return 'takeaway';
  if (type === 'dineIn') return 'dineIn';
  return 'delivery';
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
    deliveryExpenses: Number(raw.deliveryExpenses ?? raw.delivery_expenses ?? 0) || 0,
    actualCash: Number(raw.actualCash ?? raw.actual_cash ?? 0) || 0,
    discrepancy: Number(raw.discrepancy ?? 0) || 0,
    discrepancyType: String(raw.discrepancyType || raw.discrepancy_type || 'balanced'),
    dineInSales: Number(raw.dineInSales ?? raw.dine_in_sales ?? 0) || 0,
    dineInCount: Number(raw.dineInCount ?? raw.dine_in_count ?? 0) || 0,
    takeawaySales: Number(raw.takeawaySales ?? raw.takeaway_sales ?? 0) || 0,
    takeawayCount: Number(raw.takeawayCount ?? raw.takeaway_count ?? 0) || 0,
    deliverySales: Number(raw.deliverySales ?? raw.delivery_sales ?? 0) || 0,
    deliveryCount: Number(raw.deliveryCount ?? raw.delivery_count ?? 0) || 0,
    websiteSales: Number(raw.websiteSales ?? raw.website_sales ?? 0) || 0,
    websiteCount: Number(raw.websiteCount ?? raw.website_count ?? 0) || 0,
    posSales: Number(raw.posSales ?? raw.pos_sales ?? 0) || 0,
    posCount: Number(raw.posCount ?? raw.pos_count ?? 0) || 0,
    cashierVoidDebt: Number(raw.cashierVoidDebt ?? raw.cashier_void_debt ?? 0) || 0,
    approvedKitchenVoidAmount:
      Number(raw.approvedKitchenVoidAmount ?? raw.approved_kitchen_void_amount ?? 0) ||
      0,
    kitchenVoidLiabilities:
      raw.kitchenVoidLiabilities && typeof raw.kitchenVoidLiabilities === 'object'
        ? raw.kitchenVoidLiabilities
        : raw.kitchen_void_liabilities && typeof raw.kitchen_void_liabilities === 'object'
          ? raw.kitchen_void_liabilities
          : null,
  };
}

function requestByOrderId(requests = []) {
  const map = new Map();
  for (const row of requests || []) {
    const orderId = String(row.order_id || row.orderId || '').trim();
    if (!orderId) continue;
    map.set(orderId, row);
  }
  return map;
}

function isAlmenuProFleetDelivery(order, request) {
  const assigned = String(
    order.assigned_driver_id ||
      order.assignedDriverId ||
      request?.assigned_driver_id ||
      request?.assignedDriverId ||
      '',
  ).trim();
  if (!assigned) return false;
  const status = String(order.status || '').toLowerCase();
  if (status === 'cancelled' || status === 'canceled') return false;
  const deliveryStatus = String(
    order.delivery_status || order.deliveryStatus || request?.status || '',
  ).toLowerCase();
  return status === 'delivered' || deliveryStatus === 'delivered';
}

function driverFeeForOrder(order, request) {
  const fee = Number(
    order.driver_fee ??
      order.driverFee ??
      order.assigned_driver_fee ??
      order.assignedDriverFee ??
      request?.driver_fee ??
      request?.driverFee ??
      0,
  );
  return Number.isFinite(fee) && fee > 0 ? fee : 0;
}

function computeShiftSummary(orders, shift, closingCashCounted = null, deliveryRequests = []) {
  const shiftId = String(shift.id);
  const requestsMap = requestByOrderId(deliveryRequests);
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
  let deliveryExpenses = 0;
  let dineInSales = 0;
  let dineInCount = 0;
  let takeawaySales = 0;
  let takeawayCount = 0;
  let deliverySales = 0;
  let deliveryCount = 0;
  let websiteSales = 0;
  let websiteCount = 0;
  let posSales = 0;
  let posCount = 0;

  for (const order of scoped) {
    const status = String(order.status || '').toLowerCase();
    const paymentMethod = order.paymentMethod || order.payment_method || '';
    const total = Number(order.totalPrice ?? order.total_price ?? 0) || 0;
    const discount = Number(order.discountAmount ?? order.discount_amount ?? 0) || 0;
    const refund = Number(order.refundAmount ?? order.refund_amount ?? 0) || 0;

    discountTotal += discount;
    refundTotal += refund;

    if (status === 'cancelled' || status === 'canceled') {
      voidCount += 1;
      continue;
    }

    if (!orderCountsTowardShiftRevenue(order)) {
      continue;
    }

    const request = requestsMap.get(String(order.id || ''));
    if (isAlmenuProFleetDelivery(order, request)) {
      deliveryExpenses += driverFeeForOrder(order, request);
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

    switch (classifyOrderChannel(order)) {
      case 'dineIn':
        dineInSales += total;
        dineInCount += 1;
        break;
      case 'takeaway':
        takeawaySales += total;
        takeawayCount += 1;
        break;
      case 'website':
        websiteSales += total;
        websiteCount += 1;
        break;
      case 'pos':
        posSales += total;
        posCount += 1;
        break;
      default:
        deliverySales += total;
        deliveryCount += 1;
        break;
    }
  }

  const openingFloat = Number(shift.openingFloat ?? shift.opening_float ?? 0) || 0;
  const expectedCash = openingFloat + cashSales - refundTotal - deliveryExpenses;
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
    deliveryExpenses: Number(deliveryExpenses.toFixed(3)),
    expectedCash,
    actualCash: actualCash ?? 0,
    discrepancy,
    discrepancyType,
    dineInSales,
    dineInCount,
    takeawaySales,
    takeawayCount,
    deliverySales,
    deliveryCount,
    websiteSales,
    websiteCount,
    posSales,
    posCount,
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

function closeShift(shift, body = {}, orders = [], deliveryRequests = []) {
  const closingCashCounted = Number(
    body.closingCashCounted ?? body.closing_cash_counted ?? 0,
  );
  const summary = computeShiftSummary(orders, shift, closingCashCounted, deliveryRequests);
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
  classifyOrderChannel,
};
