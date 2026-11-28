'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  validateInventoryItem,
  validateStockMove,
  validateRecipe,
  validateTransfer,
  publicTransferStage,
} = require('../lib/inventory/schemas');
const { TRANSFER_STAGE } = require('../lib/inventory/constants');

test('validateInventoryItem normalizes qty and cost precision', () => {
  const row = validateInventoryItem({
    id: 'inv1',
    itemType: 'RAW',
    currentQty: 1.23456789,
    avgCost: 0.123456789,
  });
  assert.equal(row.currentQty, 1.23457);
  assert.equal(row.avgCost, 0.12346);
});

test('validateStockMove computes totalCost', () => {
  const move = validateStockMove({
    id: 'm1',
    itemId: 'inv1',
    qtyInRecipeUom: 10,
    unitCostSnapshot: 0.5,
    referenceType: 'PURCHASE',
  });
  assert.equal(move.totalCost, 5);
});

test('validateRecipe rejects invalid channel on ingredient', () => {
  assert.throws(
    () =>
      validateRecipe({
        menuItemId: 'burger',
        ingredients: [{ itemId: 'x', applicableOrderTypes: ['INVALID'] }],
      }),
    /invalid/i,
  );
});

test('validateTransfer accepts draft transfer', () => {
  const row = validateTransfer({ id: 't1', status: 'DRAFT', stage: TRANSFER_STAGE.REQUEST });
  assert.equal(row.id, 't1');
});

test('publicTransferStage maps Foodics labels', () => {
  assert.equal(publicTransferStage(TRANSFER_STAGE.REQUEST), 'REQUESTED');
  assert.equal(publicTransferStage(TRANSFER_STAGE.SENT), 'IN_TRANSIT');
  assert.equal(publicTransferStage(TRANSFER_STAGE.RECEIVED), 'RECEIVED');
});