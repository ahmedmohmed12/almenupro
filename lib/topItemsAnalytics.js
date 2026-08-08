function isPicksCategoryName(name) {
  const value = String(name || '').trim().toLowerCase();
  return (
    value.includes('ذوقك') ||
    value.includes('picks for you') ||
    value.includes('pick for you')
  );
}

function isCancelledStatus(status) {
  const value = String(status || '').trim().toLowerCase();
  return value === 'cancelled' || value === 'canceled' || value === 'ملغي';
}

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

/**
 * Rank menu items by total quantity sold within a time window.
 * Falls back to static Talabat "picks" category items when no order data exists.
 */
function computeTopMenuItems(orders, menuItems, restaurantId, options = {}) {
  const days = Math.max(1, Number(options.days) || 90);
  const limit = Math.max(1, Math.min(30, Number(options.limit) || 12));
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;
  const counts = new Map();

  for (const order of orders || []) {
    if (getOrderRestaurantId(order) !== restaurantId) continue;
    if (isCancelledStatus(order.status)) continue;
    if (getOrderCreatedAt(order) < cutoff) continue;

    for (const line of order.items || []) {
      const menuItemId = parseMenuItemId(
        line.menuItemId ?? line.menu_item_id ?? line.id,
      );
      if (!menuItemId) continue;
      const quantity = Math.max(1, Number(line.quantity) || 1);
      counts.set(menuItemId, (counts.get(menuItemId) || 0) + quantity);
    }
  }

  if (counts.size > 0) {
    return {
      source: 'orders',
      items: [...counts.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, limit)
        .map(([menuItemId, quantity]) => ({ menuItemId, quantity })),
    };
  }

  const fallbackItems = (menuItems || [])
    .filter((item) => isPicksCategoryName(item.category_name || item.categoryName))
    .slice(0, limit)
    .map((item) => ({
      menuItemId: Number(item.id),
      quantity: 0,
    }))
    .filter((entry) => Number.isFinite(entry.menuItemId) && entry.menuItemId > 0);

  return {
    source: fallbackItems.length > 0 ? 'fallback' : 'none',
    items: fallbackItems,
  };
}

module.exports = {
  computeTopMenuItems,
  isPicksCategoryName,
};
