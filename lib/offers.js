'use strict';

const { phonesMatch } = require('./customersStore');

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
    usageLimitPerCustomer: parseUsageLimitPerCustomer(raw),
    createdAt: raw.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
}

const OFFER_USAGE_LIMIT_MESSAGE = 'لقد وصلت للحد الأقصى لاستخدام هذا العرض';

function parseUsageLimitPerCustomer(raw = {}) {
  const value = Number(
    raw.usageLimitPerCustomer ?? raw.usage_limit_per_customer ?? 0,
  );
  if (!Number.isFinite(value) || value <= 0) return 0;
  return Math.floor(value);
}

function collectOfferIdsFromOrder(order = {}) {
  const ids = new Set();
  const top = order.offerId || order.offer_id;
  if (top) ids.add(String(top).trim());
  const items = Array.isArray(order.items) ? order.items : [];
  for (const item of items) {
    const id = item?.offerId || item?.offer_id;
    if (id) ids.add(String(id).trim());
  }
  return [...ids].filter(Boolean);
}

function isCancelledOrder(order) {
  const status = String(order?.status || '').toLowerCase();
  return status === 'cancelled' || status === 'canceled' || status === 'rejected';
}

function countOfferUsageForCustomer(orders, { offerId, phone, restaurantId }) {
  if (!offerId || !phone) return 0;
  const wanted = String(offerId);
  return (Array.isArray(orders) ? orders : []).filter((order) => {
    if (isCancelledOrder(order)) return false;
    const orderRestaurant = order.restaurant_id || order.restaurantId || '';
    if (restaurantId && String(orderRestaurant) && String(orderRestaurant) !== String(restaurantId)) {
      return false;
    }
    if (!phonesMatch(order.phone, phone)) return false;
    return collectOfferIdsFromOrder(order).includes(wanted);
  }).length;
}

function evaluateOfferUsage({ offer, orders, phone, restaurantId }) {
  const limit = parseUsageLimitPerCustomer(offer || {});
  if (limit <= 0) {
    return { allowed: true, used: 0, limit: 0 };
  }
  const used = countOfferUsageForCustomer(orders, {
    offerId: offer.id,
    phone,
    restaurantId,
  });
  return {
    allowed: used < limit,
    used,
    limit,
    error: used < limit ? undefined : OFFER_USAGE_LIMIT_MESSAGE,
    code: used < limit ? undefined : 'OFFER_USAGE_LIMIT',
  };
}

function assertOffersUsageAllowed({ offers, orders, offerIds, phone, restaurantId }) {
  const uniqueIds = [...new Set((offerIds || []).map((id) => String(id || '').trim()).filter(Boolean))];
  if (uniqueIds.length === 0) return { allowed: true };

  const byId = new Map((offers || []).map((offer) => [String(offer.id), offer]));
  for (const offerId of uniqueIds) {
    const offer = byId.get(offerId);
    if (!offer) continue;
    const limit = parseUsageLimitPerCustomer(offer);
    if (limit <= 0) continue;
    if (!phone) {
      const error = new Error('يرجى إدخال رقم الهاتف لاستخدام العرض');
      error.statusCode = 400;
      error.code = 'OFFER_PHONE_REQUIRED';
      throw error;
    }
    const result = evaluateOfferUsage({ offer, orders, phone, restaurantId });
    if (!result.allowed) {
      const error = new Error(OFFER_USAGE_LIMIT_MESSAGE);
      error.statusCode = 409;
      error.code = 'OFFER_USAGE_LIMIT';
      error.offerId = offerId;
      error.used = result.used;
      error.limit = result.limit;
      throw error;
    }
  }
  return { allowed: true };
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
  OFFER_USAGE_LIMIT_MESSAGE,
  normalizeOffer,
  isOfferLive,
  parseItemIds,
  parseUsageLimitPerCustomer,
  collectOfferIdsFromOrder,
  countOfferUsageForCustomer,
  evaluateOfferUsage,
  assertOffersUsageAllowed,
};
