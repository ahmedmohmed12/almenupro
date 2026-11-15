'use strict';

const { kuwaitDateKey } = require('./kuwaitBusinessDay');
const { humanizePlatformKey, resolvePlatformKey } = require('./platformChannelUtils');
const {
  isPlatformOrder,
  merchantSalesOf,
  money,
  settlementLabel,
} = require('./platformOrderFinance');

function orderTime(order) {
  const raw = order?.createdAt || order?.created_at;
  const date = raw ? new Date(raw) : null;
  return date && !Number.isNaN(date.getTime()) ? date.getTime() : 0;
}

function platformKey(order) {
  return resolvePlatformKey(order?.orderSource || order?.order_source || order?.platform);
}

function deliveryCourier(order) {
  const text = String(
    order?.deliveryType || order?.delivery_type || order?.courier || '',
  ).toLowerCase();
  if (/merchant|self\s*delivery|restaurant/.test(text)) return 'merchant';
  if (/talabat|keeta|jahez|platform|courier/.test(text)) return 'platform';
  return 'platform';
}

function lineParts(item) {
  const quantity = Math.max(1, Math.trunc(Number(item?.quantity) || 1));
  const unitPrice = money(item?.unitPrice ?? item?.unit_price);
  const options = Array.isArray(item?.options)
    ? item.options
    : Array.isArray(item?.modifiers)
      ? item.modifiers
      : [];
  const modifiersTotal = money(
    options.reduce((sum, option) => {
      const price = money(option?.price ?? option?.unitPrice ?? option?.unit_price);
      const qty = Math.max(1, Math.trunc(Number(option?.quantity) || 1));
      return sum + price * qty;
    }, 0),
  );
  const itemDiscount = money(
    item?.discountAmount ?? item?.discount_amount ?? item?.discount ?? 0,
  );
  const lineTotal = money(
    item?.lineTotal ?? item?.line_total ?? unitPrice * quantity + modifiersTotal,
  );
  return {
    name: String(item?.name || '').trim(),
    quantity,
    unitPrice,
    modifiersTotal,
    itemDiscount,
    lineTotal,
  };
}

function orderReportRow(order) {
  const items = (Array.isArray(order.items) ? order.items : []).map(lineParts);
  const itemSubtotal = money(items.reduce((sum, item) => sum + item.lineTotal, 0));
  const modifiersTotal = money(items.reduce((sum, item) => sum + item.modifiersTotal, 0));
  const itemDiscounts = money(items.reduce((sum, item) => sum + item.itemDiscount, 0));
  const orderDiscount = money(order.discountAmount ?? order.discount_amount);
  const deliveryFee = money(order.deliveryFee ?? order.delivery_fee);
  const courier = deliveryCourier(order);
  const customerPayableTotal = money(
    order.customerPayableTotal ??
      order.customer_payable_total ??
      order.totalPrice ??
      order.total_price,
  );
  const netMerchantSales = merchantSalesOf(order);
  const platformCommission = money(order.platformCommission ?? order.platform_commission);
  const merchantDeliveryFee = courier === 'merchant' ? deliveryFee : 0;
  const platformDeliveryFee = courier === 'platform' ? deliveryFee : 0;
  return {
    orderId: String(order.id || ''),
    externalOrderId: String(order.externalOrderId || order.external_order_id || ''),
    invoiceNumber: String(order.invoiceNumber || order.invoice_number || order.id || ''),
    platform: platformKey(order),
    platformLabel: humanizePlatformKey(platformKey(order)),
    createdAt: order.createdAt || order.created_at || null,
    paymentMethod: String(order.paymentMethod || order.payment_method || ''),
    paymentStatus: settlementLabel(order.paymentMethod || order.payment_method),
    items,
    itemSubtotal,
    modifiersTotal,
    itemDiscounts,
    orderDiscount,
    deliveryFee,
    deliveryCourier: courier,
    merchantDeliveryFee,
    platformDeliveryFee,
    customerPayableTotal,
    netMerchantSales,
    platformCommission,
    netAfterCommission: money(Math.max(0, netMerchantSales - platformCommission)),
  };
}

function emptyChannel(platform) {
  return {
    platform,
    platformLabel: humanizePlatformKey(platform),
    orders: 0,
    customerPayableTotal: 0,
    netMerchantSales: 0,
    platformCommission: 0,
    netAfterCommission: 0,
    deliveryFee: 0,
    merchantDeliveryFee: 0,
    platformDeliveryFee: 0,
  };
}

function addMoney(target, row) {
  target.orders += 1;
  target.customerPayableTotal = money(target.customerPayableTotal + row.customerPayableTotal);
  target.netMerchantSales = money(target.netMerchantSales + row.netMerchantSales);
  target.platformCommission = money(target.platformCommission + row.platformCommission);
  target.netAfterCommission = money(target.netAfterCommission + row.netAfterCommission);
  target.deliveryFee = money(target.deliveryFee + row.deliveryFee);
  target.merchantDeliveryFee = money(target.merchantDeliveryFee + row.merchantDeliveryFee);
  target.platformDeliveryFee = money(target.platformDeliveryFee + row.platformDeliveryFee);
}

function computePlatformReconciliationReport(orders, restaurantId, options = {}) {
  const days = Math.max(1, Number(options.days) || 1);
  const firstDay = new Date(Date.now() - (days - 1) * 24 * 60 * 60 * 1000);
  const firstDayKey = kuwaitDateKey(firstDay);
  const rows = (orders || [])
    .filter((order) => {
      const owner = String(order.restaurant_id || order.restaurantId || '');
      if (restaurantId && owner !== String(restaurantId)) return false;
      if (!isPlatformOrder(order)) return false;
      const status = String(order.status || '').toLowerCase();
      if (status === 'cancelled' || status === 'canceled') return false;
      const created = orderTime(order);
      return created > 0 && kuwaitDateKey(created) >= firstDayKey;
    })
    .map(orderReportRow)
    .sort((a, b) => orderTime(b) - orderTime(a));

  const channels = new Map();
  const daily = new Map();
  for (const row of rows) {
    const channel = channels.get(row.platform) || emptyChannel(row.platform);
    addMoney(channel, row);
    channels.set(row.platform, channel);
    const dayKey = `${kuwaitDateKey(row.createdAt)}|${row.platform}`;
    const day = daily.get(dayKey) || {
      ...emptyChannel(row.platform),
      day: kuwaitDateKey(row.createdAt),
    };
    addMoney(day, row);
    daily.set(dayKey, day);
  }

  return {
    days,
    orderCount: rows.length,
    channels: [...channels.values()],
    daily: [...daily.values()].sort((a, b) => String(b.day).localeCompare(String(a.day))),
    orders: rows.slice(0, 200),
  };
}

module.exports = {
  computePlatformReconciliationReport,
  deliveryCourier,
  orderReportRow,
};
