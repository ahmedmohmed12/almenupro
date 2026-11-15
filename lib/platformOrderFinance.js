'use strict';

const PLATFORM_SOURCES = new Set(['talabat', 'jahez', 'keeta', 'keta']);

function money(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return fallback;
  return Number(parsed.toFixed(3));
}

function computePlatformDualTotals({
  itemsTotal = 0,
  deliveryFee = 0,
  discount = 0,
} = {}) {
  const items = money(itemsTotal);
  const fee = money(deliveryFee);
  const off = money(discount);
  const netMerchantSales = Number(Math.max(0, items - off).toFixed(3));
  const customerPayableTotal = Number(
    Math.max(0, items + fee - off).toFixed(3),
  );
  return {
    itemsTotal: items,
    deliveryFee: fee,
    discountAmount: off,
    netMerchantSales,
    customerPayableTotal,
    priceLocked: true,
  };
}

function isPlatformOrder(order) {
  const source = String(
    order?.orderSource || order?.order_source || order?.platform || '',
  )
    .trim()
    .toLowerCase();
  const externalId = String(
    order?.externalOrderId || order?.external_order_id || '',
  ).trim();
  return Boolean(externalId) && PLATFORM_SOURCES.has(source === 'keta' ? 'keeta' : source);
}

function isCashOnDelivery(paymentMethod) {
  const text = String(paymentMethod || '');
  return /\bcash\b|\bcod\b|collect\s+cash|كاش(?!ير)|نقدي|عند\s*الاستلام/i.test(
    text,
  );
}

function settlementLabel(paymentMethod) {
  if (!String(paymentMethod || '').trim()) return '';
  return isCashOnDelivery(paymentMethod)
    ? 'CASH ON DELIVERY'
    : 'PREPAID / ONLINE';
}

function normalizeCashierSettlementMethod(value) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (/k[\s-]?net|كي\s*نت/i.test(text)) return 'KNET';
  if (/\bcash\b|\bcod\b|كاش(?!ير)|نقدي|عند\s*الاستلام/i.test(text)) return 'Cash';
  return '';
}

function merchantSalesOf(order) {
  if (!order || typeof order !== 'object') return 0;
  const explicit = order.netMerchantSales ?? order.net_merchant_sales;
  if (explicit != null && explicit !== '' && Number.isFinite(Number(explicit))) {
    return money(explicit);
  }
  return money(order.totalPrice ?? order.total_price);
}

module.exports = {
  PLATFORM_SOURCES,
  computePlatformDualTotals,
  isCashOnDelivery,
  isPlatformOrder,
  merchantSalesOf,
  money,
  normalizeCashierSettlementMethod,
  settlementLabel,
};
