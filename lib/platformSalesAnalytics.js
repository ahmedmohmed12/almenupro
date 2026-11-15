const { isCancelledStatus } = require('./topItemsAnalytics');
const { resolvePlatformKey, humanizePlatformKey } = require('./platformChannelUtils');
const { kuwaitDateKey } = require('./kuwaitBusinessDay');
const { merchantSalesOf } = require('./platformOrderFinance');

const PLATFORM_AR = {
  talabat: 'طلبات',
  keeta: 'كيتا',
  jahez: 'جاهز',
  pos: 'المحل',
  menu: 'المنيو',
};

function getOrderRestaurantId(order) {
  return order.restaurant_id || order.restaurantId || '';
}

function getOrderCreatedAt(order) {
  const raw = order.createdAt || order.created_at;
  const date = raw ? new Date(raw) : null;
  return date && !Number.isNaN(date.getTime()) ? date.getTime() : 0;
}

function orderTotal(order) {
  return Number(order.totalPrice ?? order.total_price) || 0;
}

function orderNet(order) {
  const merchant = merchantSalesOf(order);
  const commission = Number(order.platformCommission ?? order.platform_commission) || 0;
  if (commission > 0) return Math.max(0, merchant - commission);
  return merchant;
}

function money3(value) {
  return Number((Number(value) || 0).toFixed(3));
}

function storeIdentity(order) {
  const platform = resolvePlatformKey(order.orderSource || order.order_source);
  const storeId = String(order.store_id || order.storeId || '').trim();
  const storeName = String(order.store_name || order.storeName || '').trim();
  if (storeId) {
    return { storeId, storeName, platform };
  }
  if (storeName) {
    return { storeId: `name:${storeName}`, storeName, platform };
  }
  return { storeId: `platform:${platform}`, storeName: '', platform };
}

function storeDisplayName(storeName, platform) {
  const name = String(storeName || '').trim();
  const brand = PLATFORM_AR[platform] || humanizePlatformKey(platform);
  if (!name) return brand;
  if (name.includes(brand) || name.toLowerCase().includes(platform)) return name;
  return `${brand} - ${name}`;
}

function orderRef(order) {
  return String(
    order.invoiceNumber ||
      order.invoice_number ||
      order.externalOrderId ||
      order.external_order_id ||
      order.id ||
      '',
  ).trim();
}

function roundShare(part, total) {
  return total > 0 ? Number(((part / total) * 100).toFixed(1)) : 0;
}

function aggregateSales(orders) {
  const byPlatform = new Map();
  const byStore = new Map();
  let grossTotal = 0;
  let netTotal = 0;
  let commissionTotal = 0;
  const transactions = [];

  for (const order of orders) {
    const identity = storeIdentity(order);
    const total = orderTotal(order);
    const commission = Number(order.platformCommission ?? order.platform_commission) || 0;
    const net = orderNet(order);
    const createdAt = getOrderCreatedAt(order);

    grossTotal += total;
    netTotal += net;
    commissionTotal += commission;

    const platformRow = byPlatform.get(identity.platform) || {
      platform: identity.platform,
      orders: 0,
      grossRevenue: 0,
      netRevenue: 0,
      commission: 0,
    };
    platformRow.orders += 1;
    platformRow.grossRevenue += total;
    platformRow.netRevenue += net;
    platformRow.commission += commission;
    byPlatform.set(identity.platform, platformRow);

    const storeRow = byStore.get(identity.storeId) || {
      storeId: identity.storeId,
      storeName: storeDisplayName(identity.storeName, identity.platform),
      platform: identity.platform,
      orders: 0,
      grossRevenue: 0,
      netRevenue: 0,
      commission: 0,
    };
    if (!storeRow.storeName && identity.storeName) {
      storeRow.storeName = storeDisplayName(identity.storeName, identity.platform);
    }
    storeRow.orders += 1;
    storeRow.grossRevenue += total;
    storeRow.netRevenue += net;
    storeRow.commission += commission;
    byStore.set(identity.storeId, storeRow);

    transactions.push({
      orderId: orderRef(order),
      createdAt: createdAt ? new Date(createdAt).toISOString() : '',
      storeId: identity.storeId,
      storeName: storeDisplayName(identity.storeName, identity.platform),
      platform: identity.platform,
      total: money3(total),
      net: money3(net),
      status: String(order.status || ''),
    });
  }

  transactions.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));

  const platforms = [...byPlatform.values()]
    .map((row) => ({
      platform: row.platform,
      orders: row.orders,
      grossRevenue: money3(row.grossRevenue),
      netRevenue: money3(row.netRevenue),
      commission: money3(row.commission),
      sharePercent: roundShare(row.grossRevenue, grossTotal),
    }))
    .sort((a, b) => b.grossRevenue - a.grossRevenue);

  const stores = [...byStore.values()]
    .map((row) => ({
      storeId: row.storeId,
      storeName: row.storeName,
      platform: row.platform,
      orders: row.orders,
      grossRevenue: money3(row.grossRevenue),
      netRevenue: money3(row.netRevenue),
      commission: money3(row.commission),
      averageOrderValue: row.orders > 0 ? money3(row.grossRevenue / row.orders) : 0,
      sharePercent: roundShare(row.grossRevenue, grossTotal),
    }))
    .sort((a, b) => b.grossRevenue - a.grossRevenue);

  return {
    summary: {
      orders: transactions.length,
      grossRevenue: money3(grossTotal),
      netRevenue: money3(netTotal),
      commission: money3(commissionTotal),
      averageOrderValue:
        transactions.length > 0 ? money3(grossTotal / transactions.length) : 0,
    },
    platforms,
    stores,
    transactions: transactions.slice(0, 2000),
  };
}

function computeDailySalesAnalytics(orders, restaurantId, options = {}) {
  const days = Math.max(1, Number(options.days) || 1);
  const firstDay = new Date(Date.now() - (days - 1) * 24 * 60 * 60 * 1000);
  const firstDayKey = kuwaitDateKey(firstDay);
  const storeFilter = String(options.storeId || options.store_id || '').trim();

  const scoped = (orders || []).filter((order) => {
    if (getOrderRestaurantId(order) !== restaurantId) return false;
    if (isCancelledStatus(order.status)) return false;
    const createdAt = getOrderCreatedAt(order);
    return createdAt > 0 && kuwaitDateKey(createdAt) >= firstDayKey;
  });

  const full = aggregateSales(scoped);
  const selected = storeFilter
    ? scoped.filter((order) => storeIdentity(order).storeId === storeFilter)
    : scoped;
  const view = storeFilter ? aggregateSales(selected) : full;

  return {
    days,
    storeId: storeFilter,
    summary: view.summary,
    platforms: view.platforms,
    stores: full.stores,
    transactions: view.transactions,
    source: scoped.length > 0 ? 'live' : 'empty',
  };
}

function csvCell(value) {
  const text = String(value ?? '');
  if (/[",\n\r]/.test(text) || /^[=+\-@]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

function buildDailySalesCsv(report) {
  const lines = ['\uFEFFstore_name,store_id,platform,orders,gross_sales,net_sales,average_order_value'];
  for (const store of report?.stores || []) {
    lines.push(
      [
        store.storeName,
        store.storeId,
        store.platform,
        store.orders,
        store.grossRevenue,
        store.netRevenue,
        store.averageOrderValue,
      ]
        .map(csvCell)
        .join(','),
    );
  }
  lines.push('');
  lines.push('order_id,created_at,store_name,store_id,platform,total,net,status');
  for (const row of report?.transactions || []) {
    lines.push(
      [
        row.orderId,
        row.createdAt,
        row.storeName,
        row.storeId,
        row.platform,
        row.total,
        row.net,
        row.status,
      ]
        .map(csvCell)
        .join(','),
    );
  }
  return lines.join('\n');
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function buildDailySalesPrintHtml(report) {
  const storeRows = (report?.stores || [])
    .map(
      (store) => `<tr>
        <td>${escapeHtml(store.storeName)}</td>
        <td>${escapeHtml(store.orders)}</td>
        <td>${escapeHtml(store.grossRevenue)}</td>
        <td>${escapeHtml(store.averageOrderValue)}</td>
        <td>${escapeHtml(store.netRevenue)}</td>
      </tr>`,
    )
    .join('');
  const orderRows = (report?.transactions || [])
    .map(
      (row) => `<tr>
        <td>${escapeHtml(row.orderId)}</td>
        <td>${escapeHtml(row.createdAt)}</td>
        <td>${escapeHtml(row.storeName)}</td>
        <td>${escapeHtml(row.total)}</td>
        <td>${escapeHtml(row.status)}</td>
      </tr>`,
    )
    .join('');
  const summary = report?.summary || {};
  return `<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>تقرير المبيعات حسب المتجر</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 24px; color: #1a1a1a; }
    h1, h2 { color: #6B1124; }
    table { width: 100%; border-collapse: collapse; margin: 12px 0 28px; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: right; }
    th { background: #f6f0f2; }
    @media print { button { display: none; } }
  </style>
</head>
<body>
  <button onclick="window.print()">حفظ PDF</button>
  <h1>تقرير المبيعات حسب المتجر</h1>
  <p>الطلبات ${escapeHtml(summary.orders)} — الإجمالي ${escapeHtml(summary.grossRevenue)} — المتوسط ${escapeHtml(summary.averageOrderValue)}</p>
  <h2>إجمالي كل متجر</h2>
  <table>
    <thead><tr><th>المتجر</th><th>الطلبات</th><th>إجمالي المبيعات</th><th>متوسط الطلب</th><th>الصافي</th></tr></thead>
    <tbody>${storeRows}</tbody>
  </table>
  <h2>العمليات</h2>
  <table>
    <thead><tr><th>رقم الطلب</th><th>الوقت</th><th>المتجر</th><th>الإجمالي</th><th>الحالة</th></tr></thead>
    <tbody>${orderRows}</tbody>
  </table>
</body>
</html>`;
}

module.exports = {
  buildDailySalesCsv,
  buildDailySalesPrintHtml,
  computeDailySalesAnalytics,
  resolvePlatformKey,
  storeIdentity,
};
