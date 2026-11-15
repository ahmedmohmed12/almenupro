'use strict';

const { randomUUID } = require('crypto');
const { isCashPayment } = require('./shiftSessions');

function round3(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 1000) / 1000;
}

function orderTotal(order = {}, request = {}) {
  const fromOrder = Number(order.totalPrice ?? order.total_price ?? 0);
  if (Number.isFinite(fromOrder) && fromOrder > 0) return round3(fromOrder);
  const collect = Number(request.cash_to_collect ?? request.cashToCollect ?? 0);
  if (Number.isFinite(collect) && collect > 0) return round3(collect);
  const customerFee = Number(request.customer_fee ?? order.deliveryFee ?? order.delivery_fee ?? 0);
  const sub = Number(order.subtotal ?? 0);
  return round3(sub + customerFee);
}

function driverRegionFee(order = {}, request = {}) {
  const fee = Number(
    request.driver_fee ??
      request.driverFee ??
      order.driver_fee ??
      order.driverFee ??
      order.assigned_driver_fee ??
      order.assignedDriverFee ??
      0,
  );
  return Number.isFinite(fee) && fee > 0 ? round3(fee) : 0;
}

function paymentKind(order = {}, request = {}) {
  const method = order.paymentMethod || order.payment_method || request.payment_method || request.paymentMethod || '';
  return isCashPayment(method) ? 'cash' : 'knet';
}

function buildHandshake(order = {}, request = {}) {
  const kind = paymentKind(order, request);
  const total = orderTotal(order, request);
  const fee = driverRegionFee(order, request);
  const cash = kind === 'cash';
  return {
    payment_method: String(order.paymentMethod || order.payment_method || request.payment_method || '').trim(),
    handshake_payment_kind: kind,
    handshake_order_total: total,
    handshake_driver_fee: fee,
    handshake_net_to_cashier: cash ? round3(Math.max(0, total - fee)) : 0,
    handshake_cashier_pays_driver: cash ? 0 : fee,
    handshake_collect_from_customer: cash ? total : 0,
  };
}

function applyHandshake(request, order) {
  return { ...request, ...buildHandshake(order || {}, request) };
}

function dualConfirmed(request) {
  return Boolean(request?.cashier_handoff_confirmed_at && request?.driver_handoff_confirmed_at);
}

function ledgerEntry(request, order, nowIso) {
  const money = buildHandshake(order || {}, request || {});
  return {
    id: `led_${randomUUID()}`,
    order_id: String(request?.order_id || order?.id || ''),
    invoice_number: String(order?.invoiceNumber || order?.invoice_number || request?.order_id || ''),
    created_at: nowIso,
    restaurant_id: String(request?.restaurant_id || request?.restaurantId || order?.restaurant_id || ''),
    restaurant_name: String(request?.restaurantName || order?.restaurantName || ''),
    cashier_id: String(order?.cashierId || order?.cashier_id || ''),
    cashier_name: String(order?.cashierName || order?.cashier_name || ''),
    payment_kind: money.handshake_payment_kind,
    payment_method: money.payment_method,
    net_to_cashier: money.handshake_net_to_cashier,
    driver_fee: money.handshake_driver_fee,
    collect_from_customer: money.handshake_collect_from_customer,
    cashier_confirmed_at: request?.cashier_handoff_confirmed_at || null,
    driver_confirmed_at: request?.driver_handoff_confirmed_at || null,
    dual_status: dualConfirmed(request) ? 'confirmed' : 'pending',
  };
}

function appendDriverLedger(driver, entry) {
  const ledger = Array.isArray(driver?.financial_ledger) ? driver.financial_ledger : [];
  const orderId = String(entry.order_id || '');
  const withoutDup = ledger.filter((row) => String(row.order_id || '') !== orderId);
  withoutDup.unshift(entry);
  return { ...driver, financial_ledger: withoutDup.slice(0, 800) };
}

function filterLedger(entries, { from, to, restaurant, orderId } = {}) {
  const fromMs = Date.parse(from || '');
  const toMs = Date.parse(to || '');
  const restaurantNeedle = String(restaurant || '').trim().toLowerCase();
  const orderNeedle = String(orderId || '').trim().toLowerCase();
  return (entries || []).filter((row) => {
    const at = Date.parse(row.created_at || 0);
    if (Number.isFinite(fromMs) && at < fromMs) return false;
    if (Number.isFinite(toMs) && at > toMs + 24 * 60 * 60 * 1000 - 1) return false;
    if (restaurantNeedle) {
      const name = String(row.restaurant_name || '').toLowerCase();
      if (!name.includes(restaurantNeedle)) return false;
    }
    if (orderNeedle) {
      const id = `${row.order_id || ''} ${row.invoice_number || ''}`.toLowerCase();
      if (!id.includes(orderNeedle)) return false;
    }
    return true;
  });
}

function handshakePublicFields(request = {}) {
  return {
    payment_method: request.payment_method || null,
    handshake_payment_kind: request.handshake_payment_kind || null,
    handshake_order_total: request.handshake_order_total ?? null,
    handshake_driver_fee: request.handshake_driver_fee ?? request.driver_fee ?? null,
    handshake_net_to_cashier: request.handshake_net_to_cashier ?? null,
    handshake_cashier_pays_driver: request.handshake_cashier_pays_driver ?? null,
    handshake_collect_from_customer: request.handshake_collect_from_customer ?? null,
    cashier_handoff_confirmed_at: request.cashier_handoff_confirmed_at || null,
    driver_handoff_confirmed_at: request.driver_handoff_confirmed_at || null,
    cashier_handoff_by: request.cashier_handoff_by || null,
    driver_handoff_by: request.driver_handoff_by || null,
  };
}

module.exports = {
  round3,
  buildHandshake,
  applyHandshake,
  dualConfirmed,
  ledgerEntry,
  appendDriverLedger,
  filterLedger,
  handshakePublicFields,
};
