'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  filterByCategory,
  reportInventoryVariance,
  reportCogs,
} = require('../lib/inventory/inventoryReports');
const { attachTenant } = require('../lib/inventory/inventoryRepository');

test('filterByCategory is case-insensitive', () => {
  const rows = [
    { id: '1', category: 'Vegetables' },
    { id: '2', category: 'meat' },
  ];
  assert.equal(filterByCategory(rows, 'meat').length, 1);
  assert.equal(filterByCategory(rows, 'VEGETABLES')[0].id, '1');
});

test('variance and cogs aliases return arrays', () => {
  const tenantId = 't1';
  const blob = {
    items: [attachTenant({ id: 'a', name: 'item', category: 'dry', currentQty: 10, avgCost: 1 }, tenantId)],
    moves: [],
    recipes: [],
    purchases: [],
    wasteDocuments: [],
  };
  const variance = reportInventoryVariance(blob, tenantId, [], {
    branchId: tenantId,
    from: null,
    to: null,
  });
  assert.ok(Array.isArray(variance));
  assert.ok(variance.length >= 1);
  const cogs = reportCogs(blob, tenantId, [], [], { from: null, to: null, category: 'dry' });
  assert.ok(Array.isArray(cogs));
});