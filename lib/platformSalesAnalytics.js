const { isCancelledStatus } = require('./topItemsAnalytics');
const { resolvePlatformKey } = require('./platformChannelUtils');

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
  const total = orderTotal(order);
  const commission = Number(order.platformCommission ?? order.platform_commission) || 0;
  if (commission > 0) return Math.max(0, total - commission);
  const gross = Number(order.platformGrossTotal ?? order.platform_gross_total);
  if (Number.isFinite(gross) && gross > 0) return gross;
  return total;
}

function computeDailySalesAnalytics(orders, restaurantId, options = {}) {
  const days = Math.max(1, Number(options.days) || 1);
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;

  const scoped = (orders || []).filter((order) => {
    if (getOrderRestaurantId(order) !== restaurantId) return false;
    if (isCancelledStatus(order.status)) return false;
    return getOrderCreatedAt(order) >= cutoff;
  });

  const byPlatform = new Map();
  let grossTotal = 0;
  let netTotal = 0;
  let commissionTotal = 0;
  let orderCount = 0;

  for (const order of scoped) {
    const key = resolvePlatformKey(order.orderSource || order.order_source);
    const total = orderTotal(order);
    const commission = Number(order.platformCommission ?? order.platform_commission) || 0;
    const net = orderNet(order);

    grossTotal += total;
    netTotal += net;
    commissionTotal += commission;
    orderCount += 1;

    const current = byPlatform.get(key) || {
      platform: key,
      orders: 0,
      grossRevenue: 0,
      netRevenue: 0,
      commission: 0,
    };
    current.orders += 1;
    current.grossRevenue += total;
    current.netRevenue += net;
    current.commission += commission;
    byPlatform.set(key, current);
  }

  const platforms = [...byPlatform.values()]
    .map((row) => ({
      platform: row.platform,
      orders: row.orders,
      grossRevenue: Number(row.grossRevenue.toFixed(3)),
      netRevenue: Number(row.netRevenue.toFixed(3)),
      commission: Number(row.commission.toFixed(3)),
      sharePercent:
        grossTotal > 0
          ? Number(((row.grossRevenue / grossTotal) * 100).toFixed(1))
          : 0,
    }))
    .sort((a, b) => b.grossRevenue - a.grossRevenue);

  return {
    days,
    summary: {
      orders: orderCount,
      grossRevenue: Number(grossTotal.toFixed(3)),
      netRevenue: Number(netTotal.toFixed(3)),
      commission: Number(commissionTotal.toFixed(3)),
    },
    platforms,
    source: scoped.length > 0 ? 'live' : 'empty',
  };
}

module.exports = {
  computeDailySalesAnalytics,
  resolvePlatformKey,
};
