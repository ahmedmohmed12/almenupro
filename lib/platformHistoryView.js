'use strict';

const { isKuwaitToday, kuwaitDateKey, KUWAIT_TIME_ZONE } = require('./kuwaitBusinessDay');
const { humanizePlatformKey, resolvePlatformKey } = require('./platformChannelUtils');
const { isCashOnDelivery, money } = require('./platformOrderFinance');
const { migrateCustomersFromOrders, normalizePhoneDigits } = require('./customersStore');

const PLATFORM_KEYS = new Set(['talabat', 'keeta', 'jahez']);

function platformOf(order) {
  return resolvePlatformKey(order?.orderSource || order?.order_source || order?.platform);
}

function isSavedPlatformOrder(order) {
  return PLATFORM_KEYS.has(platformOf(order));
}

function storedTotal(order) {
  return money(
    order?.totalPrice ??
      order?.total_price ??
      order?.customerPayableTotal ??
      order?.customer_payable_total ??
      0,
  );
}

function paymentBucket(order) {
  const method = String(order?.paymentMethod || order?.payment_method || '').trim();
  return isCashOnDelivery(method) ? 'Cash' : 'Prepaid';
}

function itemsLabel(order) {
  return (Array.isArray(order?.items) ? order.items : [])
    .map((item) => {
      const name = String(item?.name || '').trim();
      if (!name) return '';
      const quantity = Math.max(1, Math.trunc(Number(item?.quantity) || 1));
      return `${quantity}× ${name}`;
    })
    .filter(Boolean)
    .join('، ');
}

function contactPhone(order) {
  return String(
    order?.phone || order?.customer_phone || order?.customerPhone || '',
  ).trim();
}

function contactName(order) {
  const name = String(order?.customerName || order?.customer_name || '').trim();
  if (!name || /^\*+$/.test(name) || /\*{2,}/.test(name)) return 'عميل منصات';
  if (/^(unknown|customer|n\/a|na|null|undefined|عميل|بدون اسم)$/i.test(name)) {
    return 'عميل منصات';
  }
  return name;
}

function contactAddress(order) {
  return String(
    order?.address || order?.delivery_address || order?.deliveryAddress || '',
  ).trim();
}

function kuwaitDateTimeLabel(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: KUWAIT_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date);
}

function historyRow(order) {
  const platform = platformOf(order);
  const createdAt = order.createdAt || order.created_at || null;
  return {
    orderId: String(order.id || ''),
    orderNumber: String(
      order.invoiceNumber || order.invoice_number || order.externalOrderId || order.external_order_id || order.id || '',
    ),
    platform,
    platformLabel: humanizePlatformKey(platform),
    createdAt,
    createdAtLabel: kuwaitDateTimeLabel(createdAt),
    items: itemsLabel(order),
    total: storedTotal(order),
    phone: contactPhone(order),
    customerName: contactName(order),
    address: contactAddress(order),
    paymentStatus: paymentBucket(order),
    paymentMethod: String(order.paymentMethod || order.payment_method || ''),
    status: String(order.status || ''),
  };
}

function scopedPlatformOrders(orders, restaurantId) {
  return (orders || [])
    .filter((order) => {
      const owner = String(order.restaurant_id || order.restaurantId || '');
      if (restaurantId && owner !== String(restaurantId)) return false;
      return isSavedPlatformOrder(order);
    })
    .sort((a, b) => {
      const aTime = Date.parse(a.createdAt || a.created_at || 0) || 0;
      const bTime = Date.parse(b.createdAt || b.created_at || 0) || 0;
      return bTime - aTime;
    });
}

function listPlatformHistory(orders, restaurantId) {
  return scopedPlatformOrders(orders, restaurantId).map(historyRow);
}

function todayPlatformReport(orders, restaurantId, now = new Date()) {
  const rows = scopedPlatformOrders(orders, restaurantId)
    .filter((order) => isKuwaitToday(order.createdAt || order.created_at, now))
    .map(historyRow);
  const openRows = rows.filter((row) => !/^cancel/i.test(row.status));
  const cash = openRows.filter((row) => row.paymentStatus === 'Cash');
  const prepaid = openRows.filter((row) => row.paymentStatus === 'Prepaid');
  const sum = (list) => money(list.reduce((total, row) => total + row.total, 0));
  return {
    date: kuwaitDateKey(now),
    orderCount: openRows.length,
    cancelledCount: rows.length - openRows.length,
    totalSales: sum(openRows),
    cash: { count: cash.length, total: sum(cash) },
    prepaid: { count: prepaid.length, total: sum(prepaid) },
    orders: rows,
  };
}

function backfillPlatformCustomers(customers, orders) {
  const platformOrders = (orders || []).filter(isSavedPlatformOrder);
  let skippedShortPhone = 0;
  const phones = new Set();
  const contacts = platformOrders.map((order) => {
    const phone = contactPhone(order);
    const digits = normalizePhoneDigits(phone);
    if (digits.length < 8) skippedShortPhone += 1;
    else phones.add(digits.slice(-8));
    return {
      ...order,
      phone,
      customerName: contactName(order),
      address: contactAddress(order),
    };
  });
  const next = migrateCustomersFromOrders(customers || [], contacts);
  return {
    customers: next,
    scanned: platformOrders.length,
    saved: phones.size,
    skippedShortPhone,
    changed: next !== (customers || []),
  };
}

module.exports = {
  backfillPlatformCustomers,
  isSavedPlatformOrder,
  listPlatformHistory,
  todayPlatformReport,
};
