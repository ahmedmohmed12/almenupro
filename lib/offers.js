'use strict';

const OFFER_TYPES = new Set(['percentage', 'fixed', 'combo']);

function parseItemIds(value) {
  if (Array.isArray(value)) {
    return value
      .map((id) => Number(id))
      .filter((id) => Number.isFinite(id) && id > 0);
  }
  if (typeof value === 'string' && value.trim()) {
    return value
      .split(/[,\s]+/)
      .map((id) => Number(id))
      .filter((id) => Number.isFinite(id) && id > 0);
  }
  return [];
}

function parseDate(value) {
  if (!value) return '';
  const text = String(value).trim();
  if (!text) return '';
  const ms = Date.parse(text);
  if (!Number.isFinite(ms)) return text;
  return new Date(ms).toISOString();
}

function normalizeOffer(raw = {}, restaurantId) {
  const type = String(raw.type || raw.offerType || 'percentage').toLowerCase();
  const offerType = OFFER_TYPES.has(type) ? type : 'percentage';
  const itemIds = parseItemIds(raw.itemIds || raw.item_ids || raw.items);
  const discountValue = Number(raw.discountValue ?? raw.discount_value ?? raw.value ?? 0) || 0;
  const originalPrice = Number(raw.originalPrice ?? raw.original_price ?? 0) || 0;
  const offerPrice = Number(raw.offerPrice ?? raw.offer_price ?? raw.comboPrice ?? 0) || 0;

  return {
    id: String(raw.id || '').trim() || `offer_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
    restaurant_id: restaurantId || raw.restaurant_id || raw.restaurantId || '',
    restaurantId: restaurantId || raw.restaurantId || raw.restaurant_id || '',
    title: String(raw.title || raw.name || '').trim(),
    description: String(raw.description || '').trim(),
    type: offerType,
    discountValue,
    originalPrice,
    offerPrice,
    itemIds,
    imageUrl: String(raw.imageUrl || raw.image_url || '').trim(),
    badgeText: String(raw.badgeText || raw.badge_text || '').trim(),
    startsAt: parseDate(raw.startsAt || raw.starts_at || raw.startDate),
    endsAt: parseDate(raw.endsAt || raw.ends_at || raw.endDate),
    isActive: raw.isActive !== false && raw.is_active !== false,
    minSubtotal: Number(raw.minSubtotal ?? raw.min_subtotal ?? 0) || 0,
    createdAt: raw.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
}

function isOfferLive(offer, now = Date.now()) {
  if (!offer || offer.isActive === false) return false;
  if (offer.startsAt) {
    const start = Date.parse(offer.startsAt);
    if (Number.isFinite(start) && start > now) return false;
  }
  if (offer.endsAt) {
    const end = Date.parse(offer.endsAt);
    if (Number.isFinite(end) && end < now) return false;
  }
  return true;
}

module.exports = {
  OFFER_TYPES,
  normalizeOffer,
  isOfferLive,
  parseItemIds,
};
