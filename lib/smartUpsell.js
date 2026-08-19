'use strict';

const DESSERT_TOTAL_THRESHOLD_KD = 5;

const DRINK_KEYWORDS = [
  'مشرو',
  'عصير',
  'قهو',
  'شاي',
  'مويه',
  'موية',
  'ماء',
  'كولا',
  'لاتيه',
  'drink',
  'beverage',
  'soda',
  'cola',
  'water',
  'juice',
  'coffee',
  'tea',
  'milkshake',
  'smoothie',
  'latte',
];

const SIDE_KEYWORDS = [
  'شورب',
  'سلط',
  'مقبل',
  'جانب',
  'بطاطس',
  'بطاطا',
  'أرز',
  'ارز',
  'soup',
  'salad',
  'side',
  'fries',
  'rice',
  'starter',
  'appetizer',
];

const DESSERT_KEYWORDS = [
  'حلوي',
  'حلوا',
  'حلى',
  'كيك',
  'براون',
  'آيس',
  'ايس كريم',
  'تيراميسو',
  'cake',
  'brownie',
  'dessert',
  'ice cream',
  'tiramisu',
  'pudding',
];

const MAIN_KEYWORDS = [
  'وجب',
  'طبق',
  'رئيسي',
  'ساند',
  'برجر',
  'بيتزا',
  'باستا',
  'كوكيز',
  'cookie',
  'burger',
  'sandwich',
  'pizza',
  'pasta',
  'meal',
  'main',
  'entree',
];

function haystack(item = {}) {
  return [
    item.category_name,
    item.categoryName,
    item.category,
    item.category_name_en,
    item.categoryNameEn,
    item.name,
    item.name_ar,
    item.nameAr,
    item.name_en,
    item.nameEn,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
}

function matchesAny(text, keywords) {
  const tokens = String(text || '')
    .toLowerCase()
    .split(/[^a-z0-9\u0600-\u06ff]+/i)
    .filter(Boolean);
  return keywords.some((keyword) => {
    const needle = String(keyword || '').toLowerCase();
    if (!needle) return false;
    if (/^[a-z]+$/.test(needle)) {
      return tokens.includes(needle);
    }
    return tokens.some((token) => {
      if (token === needle) return true;
      return needle.length >= 3 && token.startsWith(needle);
    });
  });
}

function classifyItem(item) {
  const text = haystack(item);
  if (matchesAny(text, DRINK_KEYWORDS)) return 'drink';
  if (matchesAny(text, SIDE_KEYWORDS)) return 'side';
  if (matchesAny(text, DESSERT_KEYWORDS)) return 'dessert';
  if (matchesAny(text, MAIN_KEYWORDS)) return 'main';
  return 'main';
}

function itemId(item) {
  const raw = item?.id ?? item?.menuItemId ?? item?.menu_item_id;
  if (raw == null || raw === '') return '';
  return String(raw);
}

function itemPrice(item) {
  const value = Number(item?.price ?? item?.unitPrice ?? 0);
  return Number.isFinite(value) ? value : 0;
}

function itemQuantity(item) {
  const value = Number(item?.quantity ?? 1);
  return Number.isFinite(value) && value > 0 ? value : 1;
}

function isAvailable(item) {
  if (item?.is_available === 0 || item?.isAvailable === false) return false;
  if (item?.is_available === false) return false;
  return true;
}

function toSuggestedItem(item, reason, message) {
  return {
    id: item.id,
    menuItemId: item.id,
    name: item.name_ar || item.nameAr || item.name || '',
    name_ar: item.name_ar || item.nameAr || item.name || '',
    name_en: item.name_en || item.nameEn || '',
    category_name: item.category_name || item.categoryName || '',
    categoryName: item.category_name || item.categoryName || '',
    price: itemPrice(item),
    image_url: item.image_url || item.imageUrl || '',
    imageUrl: item.image_url || item.imageUrl || '',
    is_available: 1,
    isAvailable: true,
    reason,
    message,
  };
}

function pickSuggestions(catalog, cartIds, type, limit = 3) {
  return catalog
    .filter((item) => classifyItem(item) === type)
    .filter((item) => isAvailable(item))
    .filter((item) => !cartIds.has(itemId(item)))
    .sort((a, b) => itemPrice(a) - itemPrice(b))
    .slice(0, limit);
}

function computeSmartUpsell({
  cartItems = [],
  menuItems = [],
  cartTotal,
  dessertThreshold = DESSERT_TOTAL_THRESHOLD_KD,
} = {}) {
  const cart = Array.isArray(cartItems) ? cartItems : [];
  const catalog = Array.isArray(menuItems) ? menuItems : [];
  const cartIds = new Set(cart.map(itemId).filter(Boolean));

  const computedTotal = cart.reduce(
    (sum, item) => sum + itemPrice(item) * itemQuantity(item),
    0,
  );
  const total =
    Number.isFinite(Number(cartTotal)) && Number(cartTotal) > 0
      ? Number(cartTotal)
      : computedTotal;

  const cartTypes = new Set(cart.map(classifyItem));
  const hasMain = cartTypes.has('main');
  const hasDrink = cartTypes.has('drink');
  const hasSide = cartTypes.has('side');
  const hasDessert = cartTypes.has('dessert');

  const gaps = {
    needsDrink: hasMain && !hasDrink,
    needsSide: hasMain && !hasSide,
    needsDessert: total >= dessertThreshold && !hasDessert,
  };

  const recommendations = [];
  const suggestedItems = [];

  const pushGroup = (reason, messageAr, messageEn, items) => {
    if (!items.length) return;
    const mapped = items.map((item) => toSuggestedItem(item, reason, messageAr));
    recommendations.push({
      reason,
      message: messageAr,
      messageAr,
      messageEn,
      items: mapped,
    });
    suggestedItems.push(...mapped);
  };

  if (gaps.needsDrink) {
    pushGroup(
      'drink',
      'أضف مشروباً يكمل الطلب',
      'Add a drink to complete the order',
      pickSuggestions(catalog, cartIds, 'drink'),
    );
  }

  if (gaps.needsSide) {
    pushGroup(
      'side',
      'أضف شوربة أو سلطة أو مقبلات',
      'Add soup, salad, or a side',
      pickSuggestions(catalog, cartIds, 'side'),
    );
  }

  if (gaps.needsDessert) {
    pushGroup(
      'dessert',
      'السلة فوق 5 د.ك — اقترح حلويات',
      'Cart is over 5.000 KD — suggest a dessert',
      pickSuggestions(catalog, cartIds, 'dessert'),
    );
  }

  return {
    ok: true,
    cartTotal: Number(total.toFixed(3)),
    dessertThreshold,
    gaps,
    recommendations,
    suggestedItems,
  };
}

module.exports = {
  DESSERT_TOTAL_THRESHOLD_KD,
  classifyItem,
  computeSmartUpsell,
};
