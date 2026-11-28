'use strict';

const { ITEM_TYPE, roundQty, roundMoneyKwd, newId } = require('./constants');
const { attachTenant } = require('./inventoryRepository');

function createInventoryItem(body, tenantId, branchId) {
  return attachTenant(
    {
      id: body.id || newId('inv'),
      branchId: String(branchId),
      sku: String(body.sku || '').trim(),
      name: String(body.name || '').trim(),
      category: String(body.category || '').trim(),
      itemType: body.itemType === ITEM_TYPE.PREP ? ITEM_TYPE.PREP : ITEM_TYPE.RAW,
      storageUom: String(body.storageUom || body.storage_uom || 'unit').trim(),
      recipeUom: String(body.recipeUom || body.recipe_uom || 'unit').trim(),
      purchaseUom: String(body.purchaseUom || body.purchase_uom || 'unit').trim(),
      conversionFactor: roundQty(body.conversionFactor || body.conversion_factor || 1),
      currentQty: roundQty(body.currentQty ?? 0),
      avgCost: roundMoneyKwd(body.avgCost ?? 0),
      lastPurchasePrice: roundMoneyKwd(body.lastPurchasePrice ?? 0),
      minStockAlert: roundQty(body.minStockAlert ?? 0),
      negativeStockFlag: false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    tenantId,
  );
}

function normalizeRecipe(body, tenantId, branchId) {
  return attachTenant(
    {
      id: body.id || newId('rcp'),
      branchId: String(branchId || tenantId),
      menuItemId: body.menuItemId != null ? String(body.menuItemId) : null,
      modifierId: body.modifierId != null ? String(body.modifierId) : null,
      prepItemId: body.prepItemId != null ? String(body.prepItemId) : null,
      expectedYieldQty: roundQty(body.expectedYieldQty || body.yieldQty || 1),
      minMarginPct: Number(body.minMarginPct) || 0.25,
      ingredients: (Array.isArray(body.ingredients) ? body.ingredients : []).map((line) => ({
        itemId: String(line.itemId),
        qtyInRecipeUom: roundQty(line.qtyInRecipeUom || line.qty || 0),
      })),
      updatedAt: new Date().toISOString(),
    },
    tenantId,
  );
}

function normalizePackagingProfile(body, tenantId) {
  return attachTenant(
    {
      id: body.id || newId('pkg'),
      channel: String(body.channel || 'TAKEAWAY').toUpperCase(),
      lines: (Array.isArray(body.lines) ? body.lines : []).map((line) => ({
        itemId: String(line.itemId),
        qtyInRecipeUom: roundQty(line.qtyInRecipeUom || line.qty || 0),
      })),
      updatedAt: new Date().toISOString(),
    },
    tenantId,
  );
}

module.exports = {
  createInventoryItem,
  normalizeRecipe,
  normalizePackagingProfile,
};