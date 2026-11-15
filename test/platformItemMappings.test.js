'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeMapping,
  normalizeName,
  resolveCanonicalMenuItemId,
  resolveLine,
} = require('../lib/platformItemMappings');
const { computeTopMenuItems } = require('../lib/topItemsAnalytics');

const menuItems = [
  {
    id: 17,
    restaurant_id: 'rest_test',
    name: 'Chicken Majboos',
    name_ar: 'مجبوس دجاج',
  },
];

test('normalizes tenant mapping with item hierarchy fields', () => {
  const mapping = normalizeMapping(
    {
      pos_item_id: '17',
      platform_name: 'Talabat',
      platform_item_id: 'T-17',
      platform_item_name: 'Chicken Majboos',
      entity_type: 'option',
      parent_mapping_id: 'parent-1',
      pos_option_id: 'size-large',
    },
    'rest_test',
  );
  assert.equal(mapping.restaurant_id, 'rest_test');
  assert.equal(mapping.platform_name, 'talabat');
  assert.equal(mapping.entity_type, 'option');
  assert.equal(mapping.parent_mapping_id, 'parent-1');
  assert.equal(mapping.pos_option_id, 'size-large');
});

test('mapping precedence is platform id, SKU, exact name, then normalized name', () => {
  const mappings = [
    {
      id: 'm1',
      pos_item_id: '17',
      platform_name: 'talabat',
      platform_item_id: 'T-17',
      platform_item_name: 'Chicken Majboos',
      sku: 'SKU-17',
      entity_type: 'item',
    },
  ];
  for (const [line, method] of [
    [{ name: 'Other', platformItemId: 'T-17' }, 'platform_item_id'],
    [{ name: 'Other', sku: 'sku-17' }, 'sku'],
    [{ name: 'Chicken Majboos' }, 'exact_name'],
    [{ name: 'Chicken-Majboos!!' }, 'normalized_name'],
  ]) {
    const result = resolveLine({
      line,
      platform: 'talabat',
      mappings,
      menuItems,
    });
    assert.equal(result.posItemId, '17');
    assert.equal(result.method, method);
  }
});

test('ambiguous names remain unmapped and normalization handles Arabic spacing', () => {
  assert.equal(normalizeName('  مجبوس - دجاج '), normalizeName('مجبوس دجاج'));
  const result = resolveLine({
    line: { name: 'Duplicate' },
    platform: 'talabat',
    mappings: [
      {
        pos_item_id: '1',
        platform_name: 'talabat',
        platform_item_name: 'Duplicate',
        entity_type: 'item',
      },
      {
        pos_item_id: '2',
        platform_name: 'talabat',
        platform_item_name: 'Duplicate',
        entity_type: 'item',
      },
    ],
    menuItems: [],
  });
  assert.equal(result.isMapped, false);
});

test('best seller aggregates platform line under canonical POS item id', () => {
  const mappings = [
    {
      id: 'm1',
      pos_item_id: '17',
      platform_name: 'talabat',
      platform_item_id: 'T-17',
      platform_item_name: 'Chicken Majboos',
      entity_type: 'item',
    },
  ];
  const order = {
    restaurantId: 'rest_test',
    orderSource: 'talabat',
    status: 'confirmed',
    createdAt: new Date().toISOString(),
    items: [{ name: 'Chicken Majboos', platformItemId: 'T-17', quantity: 3 }],
  };
  assert.equal(
    resolveCanonicalMenuItemId(order.items[0], order, mappings, menuItems),
    17,
  );
  const result = computeTopMenuItems([order], menuItems, 'rest_test', {
    mappings,
    days: 1,
  });
  assert.deepEqual(result.items[0], { menuItemId: 17, quantity: 3 });
});
