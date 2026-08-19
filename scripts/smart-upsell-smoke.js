'use strict';

const { computeSmartUpsell, classifyItem } = require('../lib/smartUpsell');

const catalog = [
  { id: 1, name: 'برجر لحم', category_name: 'وجبات', price: 4.5, isAvailable: true },
  { id: 2, name: 'Pepsi', category_name: 'مشروبات', price: 0.35, isAvailable: true },
  { id: 3, name: 'سلطة سيزر', category_name: 'سلطات', price: 1.25, isAvailable: true },
  { id: 4, name: 'براوني', category_name: 'حلويات', price: 1.5, isAvailable: true },
  { id: 5, name: 'Extra Chocolate Cookies', category_name: 'اكسترا كوكيز', price: 5.2, isAvailable: true },
];

const mainOnly = computeSmartUpsell({
  cartItems: [{ id: 1, name: 'برجر لحم', categoryName: 'وجبات', price: 4.5, quantity: 2 }],
  menuItems: catalog,
});

const checks = [
  classifyItem(catalog[0]) === 'main',
  classifyItem(catalog[1]) === 'drink',
  classifyItem(catalog[2]) === 'side',
  classifyItem(catalog[3]) === 'dessert',
  classifyItem({ name: 'شوكولاتة شيبس', category_name: 'كوكيز' }) === 'main',
  !mainOnly.suggestedItems.some((item) => String(item.id) === '5'),
  mainOnly.gaps.needsDrink === true,
  mainOnly.gaps.needsSide === true,
  mainOnly.gaps.needsDessert === true,
  mainOnly.suggestedItems.some((item) => item.reason === 'drink'),
  mainOnly.suggestedItems.some((item) => item.reason === 'side'),
  mainOnly.suggestedItems.some((item) => item.reason === 'dessert'),
];

if (checks.some((ok) => !ok)) {
  console.error('smart-upsell smoke failed', mainOnly);
  process.exit(1);
}

console.log('smart-upsell smoke ok', {
  cartTotal: mainOnly.cartTotal,
  reasons: mainOnly.recommendations.map((entry) => entry.reason),
});
