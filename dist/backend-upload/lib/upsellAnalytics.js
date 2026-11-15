const { isCancelledStatus } = require('./topItemsAnalytics');

function parseMenuItemId(raw) {
  if (raw == null || raw === '') return null;
  const asNumber = Number(raw);
  if (Number.isFinite(asNumber) && asNumber > 0) return asNumber;
  const digits = String(raw).replace(/\D/g, '');
  if (!digits) return null;
  const parsed = Number(digits);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function getOrderRestaurantId(order) {
  return order.restaurant_id || order.restaurantId || '';
}

function getOrderCreatedAt(order) {
  const raw = order.createdAt || order.created_at;
  const date = raw ? new Date(raw) : null;
  return date && !Number.isNaN(date.getTime()) ? date.getTime() : 0;
}

function normalizeEventType(raw) {
  const value = String(raw || '').trim().toLowerCase();
  if (value === 'conversion' || value === 'add_to_cart' || value === 'order') {
    return 'conversion';
  }
  return 'impression';
}

function normalizeSurface(raw) {
  const value = String(raw || 'unknown').trim().toLowerCase();
  if (
    value === 'smart_recommendations' ||
    value === 'impulse_bumps' ||
    value === 'linked_sides' ||
    value === 'free_delivery'
  ) {
    return value;
  }
  return 'unknown';
}

function normalizeIncomingEvent(raw, restaurantId) {
  const menuItemId = parseMenuItemId(
    raw.menuItemId ?? raw.menu_item_id ?? raw.itemId,
  );
  if (!menuItemId) return null;

  const eventType = normalizeEventType(raw.eventType ?? raw.event_type ?? raw.type);
  const revenue = Math.max(0, Number(raw.revenue ?? raw.lineTotal ?? raw.line_total) || 0);

  return {
    id: String(raw.id || `evt_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`),
    restaurantId: String(raw.restaurantId || raw.restaurant_id || restaurantId),
    eventType,
    surface: normalizeSurface(raw.surface),
    menuItemId,
    itemName: String(raw.itemName || raw.item_name || raw.name || '').trim(),
    reason: String(raw.reason || 'unknown').trim() || 'unknown',
    score: Number(raw.score) || 0,
    revenue: eventType === 'conversion' ? revenue : 0,
    orderId: raw.orderId?.toString() || raw.order_id?.toString() || null,
    sessionId: String(raw.sessionId || raw.session_id || '').trim() || null,
    createdAt: raw.createdAt || raw.created_at || new Date().toISOString(),
  };
}

function isUpsellOrderLine(line) {
  return (
    line.addedViaUpsell === true ||
    line.added_via_upsell === true ||
    line.upsellSurface ||
    line.upsell_surface
  );
}

function lineRevenue(line) {
  const explicit = Number(line.lineTotal ?? line.line_total);
  if (Number.isFinite(explicit) && explicit > 0) return explicit;
  const unit = Number(line.unitPrice ?? line.unit_price ?? line.price) || 0;
  const qty = Math.max(1, Number(line.quantity) || 1);
  return unit * qty;
}

/**
 * Aggregate upsell performance for admin dashboard.
 */
function computeUpsellAnalytics(events, orders, restaurantId, options = {}) {
  const days = Math.max(1, Number(options.days) || 30);
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;

  const scopedEvents = (events || []).filter((event) => {
    if (String(event.restaurantId || event.restaurant_id) !== String(restaurantId)) {
      return false;
    }
    const created = new Date(event.createdAt || event.created_at).getTime();
    return Number.isFinite(created) && created >= cutoff;
  });

  const scopedOrders = (orders || []).filter((order) => {
    if (getOrderRestaurantId(order) !== restaurantId) return false;
    if (isCancelledStatus(order.status)) return false;
    return getOrderCreatedAt(order) >= cutoff;
  });

  const itemStats = new Map();
  const surfaceStats = new Map();

  const bumpItem = (map, key, field, amount = 1) => {
    const current = map.get(key) || {
      key,
      impressions: 0,
      conversions: 0,
      revenue: 0,
    };
    current[field] += amount;
    map.set(key, current);
  };

  for (const event of scopedEvents) {
    const itemKey = String(event.menuItemId);
    const surfaceKey = normalizeSurface(event.surface);
    if (event.eventType === 'impression') {
      bumpItem(itemStats, itemKey, 'impressions');
      bumpItem(surfaceStats, surfaceKey, 'impressions');
    } else if (event.eventType === 'conversion') {
      bumpItem(itemStats, itemKey, 'conversions');
      bumpItem(itemStats, itemKey, 'revenue', event.revenue || 0);
      bumpItem(surfaceStats, surfaceKey, 'conversions');
      bumpItem(surfaceStats, surfaceKey, 'revenue', event.revenue || 0);
    }
  }

  let ordersWithUpsell = 0;
  let ordersWithoutUpsell = 0;
  let upsellOrderRevenue = 0;
  let baselineOrderRevenue = 0;

  for (const order of scopedOrders) {
    const total = Number(order.totalPrice ?? order.total_price) || 0;
    const upsellLines = (order.items || []).filter(isUpsellOrderLine);
    if (upsellLines.length > 0) {
      ordersWithUpsell += 1;
      upsellOrderRevenue += total;
      for (const line of upsellLines) {
        const id = parseMenuItemId(line.menuItemId ?? line.menu_item_id ?? line.id);
        if (!id) continue;
        const rev = lineRevenue(line);
        bumpItem(itemStats, String(id), 'conversions');
        bumpItem(itemStats, String(id), 'revenue', rev);
        const surface = normalizeSurface(line.upsellSurface ?? line.upsell_surface);
        bumpItem(surfaceStats, surface, 'conversions');
        bumpItem(surfaceStats, surface, 'revenue', rev);
      }
    } else {
      ordersWithoutUpsell += 1;
      baselineOrderRevenue += total;
    }
  }

  const totalImpressions = scopedEvents.filter((e) => e.eventType === 'impression').length;
  const totalConversions = scopedEvents.filter((e) => e.eventType === 'conversion').length;
  const totalRevenue = [...itemStats.values()].reduce((sum, row) => sum + row.revenue, 0);

  const avgAovWithUpsell =
    ordersWithUpsell > 0 ? upsellOrderRevenue / ordersWithUpsell : 0;
  const avgAovWithoutUpsell =
    ordersWithoutUpsell > 0 ? baselineOrderRevenue / ordersWithoutUpsell : 0;
  const aovLift =
    avgAovWithoutUpsell > 0
      ? ((avgAovWithUpsell - avgAovWithoutUpsell) / avgAovWithoutUpsell) * 100
      : 0;

  const topItems = [...itemStats.entries()]
    .map(([menuItemId, stats]) => ({
      menuItemId: Number(menuItemId),
      impressions: stats.impressions,
      conversions: stats.conversions,
      revenue: Number(stats.revenue.toFixed(3)),
      conversionRate:
        stats.impressions > 0
          ? Number(((stats.conversions / stats.impressions) * 100).toFixed(1))
          : stats.conversions > 0
            ? 100
            : 0,
    }))
    .sort((a, b) => b.revenue - a.revenue || b.conversions - a.conversions)
    .slice(0, 12);

  const surfaces = [...surfaceStats.entries()]
    .map(([surface, stats]) => ({
      surface,
      impressions: stats.impressions,
      conversions: stats.conversions,
      revenue: Number(stats.revenue.toFixed(3)),
      conversionRate:
        stats.impressions > 0
          ? Number(((stats.conversions / stats.impressions) * 100).toFixed(1))
          : stats.conversions > 0
            ? 100
            : 0,
    }))
    .sort((a, b) => b.revenue - a.revenue);

  return {
    days,
    summary: {
      impressions: totalImpressions,
      conversions: totalConversions,
      revenue: Number(totalRevenue.toFixed(3)),
      conversionRate:
        totalImpressions > 0
          ? Number(((totalConversions / totalImpressions) * 100).toFixed(1))
          : totalConversions > 0
            ? 100
            : 0,
      ordersWithUpsell,
      ordersWithoutUpsell,
      avgAovWithUpsell: Number(avgAovWithUpsell.toFixed(3)),
      avgAovWithoutUpsell: Number(avgAovWithoutUpsell.toFixed(3)),
      aovLiftPercent: Number(aovLift.toFixed(1)),
    },
    topItems,
    surfaces,
    source: scopedEvents.length > 0 || scopedOrders.length > 0 ? 'live' : 'empty',
  };
}

function trimEvents(events, max = 15000) {
  if (!Array.isArray(events) || events.length <= max) return events || [];
  return events.slice(events.length - max);
}

module.exports = {
  computeUpsellAnalytics,
  normalizeIncomingEvent,
  trimEvents,
};
