'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { computeAvco } = require('../lib/inventory/avco');

test('AVCO when stock is zero uses purchase price', () => {
  const avg = computeAvco({
    currentQty: 0,
    currentAvgCost: 1.2,
    purchasedQty: 10,
    purchaseUnitCost: 2.5,
  });
  assert.equal(avg, 2.5);
});

test('AVCO blends existing and new purchase', () => {
  const avg = computeAvco({
    currentQty: 10,
    currentAvgCost: 1,
    purchasedQty: 10,
    purchaseUnitCost: 3,
  });
  assert.equal(avg, 2);
});