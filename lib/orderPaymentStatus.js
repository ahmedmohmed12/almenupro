function normalizePaymentStatus(raw) {
  const value = String(raw || '')
    .trim()
    .toLowerCase()
    .replace(/-/g, '_');
  if (!value) return '';
  if (value === 'pending_payment' || value === 'pendingpayment' || value === 'unpaid') {
    return 'pending_payment';
  }
  if (value === 'paid') return 'paid';
  return value;
}

function isPendingPaymentOrder(order) {
  const status = normalizePaymentStatus(
    order.paymentStatus || order.payment_status,
  );
  if (status !== 'pending_payment') return false;
  const orderType = String(order.orderType || order.order_type || '')
    .trim()
    .toLowerCase();
  const pickup = orderType === 'pickup' || orderType === 'takeaway';
  const dineIn = orderType.includes('dine');
  const fromPos =
    order.createdFromPos === true ||
    order.created_from_pos === true ||
    String(order.orderSource || order.order_source || '')
      .trim()
      .toLowerCase()
      .startsWith('pos') ||
    String(order.orderSource || order.order_source || '')
      .toLowerCase()
      .includes('dine');
  return (pickup || dineIn) && fromPos;
}

function orderCountsTowardShiftRevenue(order) {
  const lifecycle = String(order.status || '').toLowerCase();
  if (lifecycle === 'cancelled' || lifecycle === 'canceled') return false;
  return !isPendingPaymentOrder(order);
}

module.exports = {
  normalizePaymentStatus,
  isPendingPaymentOrder,
  orderCountsTowardShiftRevenue,
};