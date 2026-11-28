'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { isInventoryEnabled, normalizeFeatures } = require('../lib/diningTables');

test('inventory disabled by default', () => {
  assert.equal(isInventoryEnabled({ features: {} }), false);
  assert.equal(normalizeFeatures({}).inventoryEnabled, false);
});

test('inventory enabled when feature flag is true and subscription active', () => {
  assert.equal(
    isInventoryEnabled({
      subscriptionStatus: 'active',
      features: { inventoryEnabled: true },
    }),
    true,
  );
});

test('inventory blocked on inactive subscription', () => {
  assert.equal(
    isInventoryEnabled({
      subscriptionStatus: 'suspended',
      features: { inventoryEnabled: true },
    }),
    false,
  );
});

test('normalizeFeatures persists inventoryEnabled from create payload shape', () => {
  const features = normalizeFeatures({
    tableManagement: true,
    kitchenManagement: false,
    deliveryManagement: true,
    inventoryEnabled: true,
  });
  assert.equal(features.inventoryEnabled, true);
  assert.equal(
    isInventoryEnabled({
      subscriptionStatus: 'active',
      features,
    }),
    true,
  );
});