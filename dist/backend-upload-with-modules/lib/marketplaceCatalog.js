'use strict';

const { aggregateReviews } = require('./reviewsStore');

const MARKETPLACE_CATEGORIES = [
  { id: 'all', labelAr: 'الكل', labelEn: 'All', icon: 'apps' },
  { id: 'burgers', labelAr: 'برجر', labelEn: 'Burgers', icon: 'lunch_dining' },
  { id: 'yemeni', labelAr: 'يمني / مندي', labelEn: 'Yemeni / Mandi', icon: 'ramen_dining' },
  { id: 'kuwaiti', labelAr: 'كويتي', labelEn: 'Kuwaiti', icon: 'restaurant' },
  { id: 'sweets', labelAr: 'حلويات', labelEn: 'Sweets', icon: 'cake' },
  { id: 'drinks', labelAr: 'مشروبات', labelEn: 'Drinks', icon: 'local_cafe' },
  { id: 'grills', labelAr: 'مشاوي', labelEn: 'Grills', icon: 'outdoor_grill' },
];

const DEFAULT_KUWAIT_AREAS = [
  'القرين، قطعة 1',
  'حولي',
  'السالمية',
  'الفروانية',
  'الجهراء',
  'مبارك الكبير',
  'الأحمدي',
];

function parseTimeToMinutes(value) {
  const raw = String(value || '').trim();
  const match = raw.match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return null;
  return hour * 60 + minute;
}

function isOpenNowFromHours(workingHours, now = new Date()) {
  const days = Array.isArray(workingHours)
    ? workingHours
    : Array.isArray(workingHours?.days)
      ? workingHours.days
      : [];
  if (!days.length) return true;

  // JS: Sunday=0 … Saturday=6. Flutter Weekday: Mon=1 … Sun=7, Sat=6, Fri=5.
  // Stored weekday uses Flutter DateTime constants (Sat=6 … Fri=5).
  const jsDay = now.getDay(); // 0 Sun … 6 Sat
  const flutterWeekday = jsDay === 0 ? 7 : jsDay;
  const day =
    days.find((entry) => Number(entry.weekday) === flutterWeekday) ||
    days.find((entry) => Number(entry.weekday) === jsDay);

  if (!day) return true;
  if (day.isOpen === false || day.is_open === false) return false;

  const openMin = parseTimeToMinutes(day.open || day.openTime || '10:00');
  const closeMin = parseTimeToMinutes(day.close || day.closeTime || '22:00');
  if (openMin == null || closeMin == null) return true;

  const nowMin = now.getHours() * 60 + now.getMinutes();
  if (closeMin > openMin) {
    return nowMin >= openMin && nowMin < closeMin;
  }
  // Overnight window (e.g. 18:00 → 02:00)
  return nowMin >= openMin || nowMin < closeMin;
}

function inferCuisines(restaurant, settings = {}) {
  const text = [
    restaurant.name,
    restaurant.slug,
    restaurant.description,
    restaurant.description_ar,
    restaurant.descriptionAr,
    settings.restaurantDescription,
    settings.restaurant_description,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();

  const tags = [];
  const push = (id, labelAr, labelEn) => {
    if (!tags.some((tag) => tag.id === id)) {
      tags.push({ id, labelAr, labelEn });
    }
  };

  if (/burger|برجر|برغر/.test(text)) push('burgers', 'برجر', 'Burgers');
  if (/yemen|يمني|مندي|مظبي|زربيان|alyaman|alyamani|سوهيل/.test(text)) {
    push('yemeni', 'يمني / مندي', 'Yemeni / Mandi');
  }
  if (/kuwait|كويت|مضغوط| حاشي|hashy|amsha|wadha/.test(text)) {
    push('kuwaiti', 'كويتي', 'Kuwaiti');
  }
  if (/cookie|كوكيز|sweet|حلويات|dessert|bakery|بيكري|كعك|molton/.test(text)) {
    push('sweets', 'حلويات', 'Sweets');
  }
  if (/juice|عصير|مشروب|قهوة|coffee|jahrawi|شاي/.test(text)) {
    push('drinks', 'مشروبات', 'Drinks');
  }
  if (/grill|مشاوي|لحم|كباب|شواء|arabi/.test(text)) {
    push('grills', 'مشاوي', 'Grills');
  }

  if (!tags.length) {
    push('restaurants', 'مطعم', 'Restaurant');
  }
  return tags;
}

function primaryCategoryId(cuisines) {
  const first = (cuisines || []).find((tag) => tag.id !== 'restaurants');
  return first?.id || 'restaurants';
}

function minDeliveryFee(zones, restaurantId) {
  const scoped = (zones || []).filter(
    (zone) =>
      String(zone.restaurant_id || zone.restaurantId) === String(restaurantId) &&
      zone.isActive !== false &&
      zone.is_active !== false,
  );
  if (!scoped.length) return null;
  let min = null;
  for (const zone of scoped) {
    const fee = Number(zone.deliveryFee ?? zone.delivery_fee ?? 0);
    if (!Number.isFinite(fee)) continue;
    if (min == null || fee < min) min = fee;
  }
  return min;
}

function areaNamesFromZones(zones, restaurantId) {
  return (zones || [])
    .filter(
      (zone) =>
        String(zone.restaurant_id || zone.restaurantId) === String(restaurantId) &&
        zone.isActive !== false &&
        zone.is_active !== false,
    )
    .map((zone) =>
      String(zone.areaName || zone.area_name || zone.governorate || '').trim(),
    )
    .filter(Boolean);
}

function activePromoLabel(offers, restaurantId, settings = {}) {
  const now = Date.now();
  const deliveryFee = Number(settings.minDeliveryFee);
  if (Number.isFinite(deliveryFee) && deliveryFee <= 0) {
    return 'توصيل مجاني';
  }

  const scoped = (offers || []).filter((offer) => {
    if (String(offer.restaurant_id || offer.restaurantId) !== String(restaurantId)) {
      return false;
    }
    if (offer.isActive === false || offer.is_active === false) return false;
    const starts = Date.parse(offer.startsAt || offer.starts_at || 0);
    const ends = Date.parse(offer.endsAt || offer.ends_at || 0);
    if (Number.isFinite(starts) && starts > now) return false;
    if (Number.isFinite(ends) && ends > 0 && ends < now) return false;
    return true;
  });

  for (const offer of scoped) {
    const badge = String(offer.badgeText || offer.badge_text || '').trim();
    if (badge) return badge;
    if (offer.type === 'percentage' && Number(offer.discountValue) > 0) {
      return `${Math.round(Number(offer.discountValue))}% خصم`;
    }
    if (offer.type === 'fixed' && Number(offer.discountValue) > 0) {
      return `خصم ${Number(offer.discountValue).toFixed(3)} د.ك`;
    }
    const title = String(offer.title || '').trim();
    if (title) return title;
  }

  return null;
}

function estimateDeliveryWindow(fee) {
  if (fee == null) return { min: 25, max: 40 };
  if (fee <= 0) return { min: 20, max: 30 };
  if (fee < 1) return { min: 25, max: 35 };
  return { min: 30, max: 45 };
}

function buildMarketplaceCard({
  restaurant,
  settings = {},
  zones = [],
  reviews = [],
  offers = [],
}) {
  const id = String(restaurant.id || '');
  const logoUrl = String(
    settings.logoUrl ||
      settings.logo_url ||
      restaurant.logoUrl ||
      restaurant.logo_url ||
      '',
  ).trim();
  const coverUrl = String(
    settings.heroImageUrl ||
      settings.hero_image_url ||
      settings.coverUrl ||
      settings.cover_url ||
      restaurant.heroImageUrl ||
      restaurant.hero_image_url ||
      restaurant.coverUrl ||
      restaurant.cover_url ||
      logoUrl,
  ).trim();
  const description = String(
    settings.restaurantDescription ||
      settings.restaurant_description ||
      restaurant.description ||
      restaurant.description_ar ||
      restaurant.descriptionAr ||
      '',
  ).trim();

  const workingHours =
    settings.workingHours ||
    settings.working_hours ||
    restaurant.workingHours ||
    [];
  const isOpen = isOpenNowFromHours(workingHours);
  const deliveryFee = minDeliveryFee(zones, id);
  const eta = estimateDeliveryWindow(deliveryFee);
  const ratingSummary = aggregateReviews(reviews, id);
  const cuisines = inferCuisines(restaurant, settings);
  const promoLabel = activePromoLabel(offers, id, {
    ...settings,
    minDeliveryFee: deliveryFee,
  });

  return {
    id,
    slug: String(restaurant.slug || '').trim().toLowerCase(),
    name: String(restaurant.name || '').trim(),
    logoUrl,
    coverUrl,
    description,
    cuisines,
    categoryIds: [
      'all',
      primaryCategoryId(cuisines),
      ...cuisines.map((tag) => tag.id),
    ].filter((value, index, arr) => arr.indexOf(value) === index),
    isOpen,
    rating: ratingSummary.average || 0,
    reviewCount: ratingSummary.count || 0,
    deliveryFee: deliveryFee == null ? null : Number(deliveryFee.toFixed(3)),
    deliveryTimeMin: eta.min,
    deliveryTimeMax: eta.max,
    promoLabel,
    freeDelivery: deliveryFee === 0 || /توصيل مجاني|free delivery/i.test(String(promoLabel || '')),
    areas: areaNamesFromZones(zones, id),
  };
}

function buildMarketplaceCatalog({
  restaurants = [],
  settingsMap = {},
  zones = [],
  reviews = [],
  offers = [],
}) {
  const byRestaurant = settingsMap.byRestaurant || settingsMap || {};
  const active = (restaurants || []).filter(
    (entry) => String(entry.status || 'active') === 'active',
  );

  const cards = active
    .map((restaurant) =>
      buildMarketplaceCard({
        restaurant,
        settings: byRestaurant[restaurant.id] || {},
        zones,
        reviews,
        offers,
      }),
    )
    .filter((card) => card.slug && card.name)
    .sort((a, b) => {
      if (a.isOpen !== b.isOpen) return a.isOpen ? -1 : 1;
      if ((b.rating || 0) !== (a.rating || 0)) return (b.rating || 0) - (a.rating || 0);
      return a.name.localeCompare(b.name, 'ar');
    });

  const areaSet = new Set(DEFAULT_KUWAIT_AREAS);
  for (const card of cards) {
    for (const area of card.areas || []) areaSet.add(area);
  }

  return {
    categories: MARKETPLACE_CATEGORIES,
    areas: [...areaSet],
    restaurants: cards,
    generatedAt: new Date().toISOString(),
  };
}

module.exports = {
  MARKETPLACE_CATEGORIES,
  DEFAULT_KUWAIT_AREAS,
  isOpenNowFromHours,
  inferCuisines,
  buildMarketplaceCard,
  buildMarketplaceCatalog,
};
