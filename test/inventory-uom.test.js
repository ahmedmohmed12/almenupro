'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  convertPurchaseQtyToRecipe,
  unitCostPurchaseToRecipe,
  normalizePurchaseLine,
} = require('../lib/inventory/uomConversion');

const sampleItem = {
  id: 'inv_1',
  purchaseUom: 'crate',
  storageUom: 'kg',
  recipeUom: 'g',
  purchaseToStorageFactor: 2,
  storageToRecipeFactor: 1000,
};

test('purchase -> storage -> recipe conversion chain', () => {
  const converted = convertPurchaseQtyToRecipe(3, sampleItem);
  assert.equal(converted.qtyInStorageUom, 6);
  assert.equal(converted.qtyInRecipeUom, 6000);
});

test('purchase unit cost normalizes to recipe UoM cost', () => {
  const factors = {
    purchaseToStorage: 2,
    storageToRecipe: 1000,
  };
  const perRecipe = unitCostPurchaseToRecipe(10, factors);
  assert.equal(perRecipe, 0.005);
});

test('normalizePurchaseLine stores traceability fields', () => {
  const line = normalizePurchaseLine(
    { itemId: 'inv_1', qtyInPurchaseUom: 1, unitCostInPurchaseUom: 12 },
    sampleItem,
  );
  assert.equal(line.qtyInRecipeUom, 2000);
  assert.equal(line.purchaseUom, 'crate');
  assert.ok(line.unitCostInRecipeUom > 0);
});