'use strict';

const { roundQty, roundMoneyKwd } = require('./constants');

function resolveUomFactors(item, line = {}) {
  const purchaseToStorage = roundQty(
    line.purchaseToStorageFactor ??
      line.purchase_to_storage_factor ??
      item?.purchaseToStorageFactor ??
      item?.purchase_to_storage_factor ??
      1,
  );
  const storageToRecipe = roundQty(
    line.storageToRecipeFactor ??
      line.storage_to_recipe_factor ??
      item?.storageToRecipeFactor ??
      item?.storage_to_recipe_factor ??
      item?.conversionFactor ??
      item?.conversion_factor ??
      1,
  );
  return { purchaseToStorage, storageToRecipe };
}

function convertPurchaseQtyToStorage(qtyInPurchaseUom, factors) {
  return roundQty(qtyInPurchaseUom * factors.purchaseToStorage);
}

function convertStorageQtyToRecipe(qtyInStorageUom, factors) {
  return roundQty(qtyInStorageUom * factors.storageToRecipe);
}

function convertPurchaseQtyToRecipe(qtyInPurchaseUom, item, line = {}) {
  const factors = resolveUomFactors(item, line);
  const qtyInStorageUom = convertPurchaseQtyToStorage(qtyInPurchaseUom, factors);
  const qtyInRecipeUom = convertStorageQtyToRecipe(qtyInStorageUom, factors);
  return {
    qtyInPurchaseUom: roundQty(qtyInPurchaseUom),
    qtyInStorageUom,
    qtyInRecipeUom,
    purchaseToStorageFactor: factors.purchaseToStorage,
    storageToRecipeFactor: factors.storageToRecipe,
  };
}

/** Cost per 1 purchase UoM -> cost per 1 recipe UoM */
function unitCostPurchaseToRecipe(unitCostInPurchaseUom, factors) {
  const purchase = roundMoneyKwd(unitCostInPurchaseUom);
  if (purchase <= 0) return 0;
  const perStorage = purchase / (factors.purchaseToStorage || 1);
  return roundMoneyKwd(perStorage / (factors.storageToRecipe || 1));
}

function normalizePurchaseLine(line, item) {
  const qtyInPurchaseUom = roundQty(
    line.qtyInPurchaseUom ??
      line.qtyPurchased ??
      line.qty_purchased ??
      line.qty ??
      0,
  );
  const converted = convertPurchaseQtyToRecipe(qtyInPurchaseUom, item, line);
  const factors = {
    purchaseToStorage: converted.purchaseToStorageFactor,
    storageToRecipe: converted.storageToRecipeFactor,
  };
  const unitCostInPurchaseUom = roundMoneyKwd(
    line.unitCostInPurchaseUom ??
      line.unitCost ??
      line.unit_cost ??
      0,
  );
  const unitCostInRecipeUom = unitCostPurchaseToRecipe(unitCostInPurchaseUom, factors);
  return {
    itemId: String(line.itemId || item?.id || ''),
    qtyInPurchaseUom: converted.qtyInPurchaseUom,
    qtyInStorageUom: converted.qtyInStorageUom,
    qtyInRecipeUom: converted.qtyInRecipeUom,
    qtyPurchased: converted.qtyInPurchaseUom,
    purchaseUom:
      line.purchaseUom ||
      line.purchase_uom ||
      item?.purchaseUom ||
      item?.purchase_uom ||
      'unit',
    storageUom: item?.storageUom || item?.storage_uom || 'unit',
    recipeUom: item?.recipeUom || item?.recipe_uom || 'unit',
    purchaseToStorageFactor: converted.purchaseToStorageFactor,
    storageToRecipeFactor: converted.storageToRecipeFactor,
    unitCostInPurchaseUom,
    unitCostInStorageUom: roundMoneyKwd(
      unitCostInPurchaseUom / (converted.purchaseToStorageFactor || 1),
    ),
    unitCostInRecipeUom,
    unitCost: unitCostInPurchaseUom,
    conversionToRecipeUom: roundQty(
      converted.purchaseToStorageFactor * converted.storageToRecipeFactor,
    ),
  };
}

module.exports = {
  resolveUomFactors,
  convertPurchaseQtyToRecipe,
  unitCostPurchaseToRecipe,
  normalizePurchaseLine,
};