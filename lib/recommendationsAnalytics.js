const { computeTopMenuItems, isCancelledStatus } = require('./topItemsAnalytics');

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

function isItemAvailable(item) {
  return !(
    item.is_available === 0 ||
    item.is_available === false ||
    item.isAvailable === false
  );
}

function parseLinkedItemIds(item) {
  const raw = item.linked_item_ids || item.linkedItemIds || [];
  if (!Array.isArray(raw)) return [];
  return raw
    .map((id) => Number(id))
    .filter((id) => Number.isFinite(id) && id > 0);
}

const COMPLEMENT_RULES = [
  {
    cartKeywords: ['كوك', 'cookie', 'حلو', 'dessert', 'كيك', 'cake', 'براون', 'brownie'],
    suggestKeywords: ['مشرو', 'drink', 'coffee', 'tea', 'قهو', 'شاي', 'عصير', 'juice'],
    reason: 'complement',
  },
  {
    cartKeywords: ['ساند', 'sandwich', 'برger', 'burger', 'وجب', 'meal', 'main'],
    suggestKeywords: ['مشرو', 'drink', 'صوص', 'sauce', 'بطاط', 'fries', 'side'],
    reason: 'complement',
  },
];

function haystackForItem(item) {
  return `${item.category_name || item.categoryName || ''} ${item.name || ''} ${item.name_ar || item.nameAr || ''} ${item.name_en || item.nameEn || ''}`.toLowerCase();
}

function matchesKeywords(item, keywords) {
  const haystack = haystackForItem(item);
  return keywords.some((keyword) => haystack.includes(keyword.toLowerCase()));
}

/**
 * Rank checkout recommendations based on cart contents, linked items, and order history.
 */
function computeCartRecommendations(
  orders,
  menuItems,
  restaurantId,
  cartItemIds,
  options = {},
) {
  const limit = Math.max(1, Math.min(12, Number(options.limit) || 8));
  const subtotal = Number(options.subtotal) || 0;
  const freeDeliveryThreshold = Number(options.freeDeliveryThreshold) || 0;
  const cartSet = new Set(
    (cartItemIds || [])
      .map((id) => Number(id))
      .filter((id) => Number.isFinite(id) && id > 0),
  );

  const scopedItems = (menuItems || []).filter(
    (item) =>
      String(item.restaurant_id || item.restaurantId || restaurantId) ===
      String(restaurantId),
  );
  const itemById = new Map(
    scopedItems.map((item) => [Number(item.id), item]),
  );
  const scores = new Map();
  const reasons = new Map();

  const bump = (id, amount, reason) => {
    if (!itemById.has(id) || cartSet.has(id)) return;
    scores.set(id, (scores.get(id) || 0) + amount);
    if (!reasons.has(id) || amount >= 50) {
      reasons.set(id, reason);
    }
  };

  for (const cartId of cartSet) {
    const item = itemById.get(cartId);
    if (!item) continue;
    for (const linkedId of parseLinkedItemIds(item)) {
      bump(linkedId, 100, 'linked');
    }
    for (const option of item.options || []) {
      const linkedOptionId = parseMenuItemId(
        option.linked_menu_item_id ?? option.linkedMenuItemId,
      );
      if (linkedOptionId) {
        bump(linkedOptionId, 90, 'linked');
      }
    }
  }

  const cartItems = [...cartSet]
    .map((id) => itemById.get(id))
    .filter(Boolean);
  for (const candidate of scopedItems) {
    if (!isItemAvailable(candidate)) continue;
    const candidateId = Number(candidate.id);
    for (const rule of COMPLEMENT_RULES) {
      const cartMatches = cartItems.some((item) =>
        matchesKeywords(item, rule.cartKeywords),
      );
      if (cartMatches && matchesKeywords(candidate, rule.suggestKeywords)) {
        bump(candidateId, 35, rule.reason);
      }
    }
  }

  for (const order of orders || []) {
    if (getOrderRestaurantId(order) !== restaurantId) continue;
    if (isCancelledStatus(order.status)) continue;

    const orderIds = new Set();
    for (const line of order.items || []) {
      const id = parseMenuItemId(
        line.menuItemId ?? line.menu_item_id ?? line.id,
      );
      if (id) orderIds.add(id);
    }

    const sharesCartItem = [...cartSet].some((id) => orderIds.has(id));
    if (!sharesCartItem) continue;

    for (const id of orderIds) {
      bump(id, 12, 'popular_pair');
    }
  }

  const topResult = computeTopMenuItems(orders, menuItems, restaurantId, {
    limit: 20,
  });
  for (const entry of topResult.items) {
    bump(entry.menuItemId, 8, 'popular');
  }

  if (freeDeliveryThreshold > 0 && subtotal > 0 && subtotal < freeDeliveryThreshold) {
    const remaining = freeDeliveryThreshold - subtotal;
    for (const candidate of scopedItems) {
      if (!isItemAvailable(candidate)) continue;
      const candidateId = Number(candidate.id);
      const price = Number(candidate.price) || 0;
      if (price <= 0) continue;
      if (price >= remaining * 0.5 && price <= remaining * 1.5) {
        bump(candidateId, 45, 'free_delivery');
      }
    }
  }

  const recommendations = [...scores.entries()]
    .filter(([id]) => isItemAvailable(itemById.get(id)))
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([menuItemId, score]) => ({
      menuItemId,
      score,
      reason: reasons.get(menuItemId) || 'popular',
    }));

  return {
    source: recommendations.length > 0 ? 'engine' : 'none',
    recommendations,
  };
}

module.exports = {
  computeCartRecommendations,
};
