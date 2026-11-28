'use strict';

const {
  ITEM_TYPE,
  APPLICABLE_ORDER_TYPES,
  roundQty,
  roundMoneyKwd,
  newId,
} = require('./constants');
const { attachTenant } = require('./inventoryRepository');

function createInventoryItem(body, tenantId, branchId) {
  const storageToRecipe = roundQty(
    body.storageToRecipeFactor ??
      body.storage_to_recipe_factor ??
      body.conversionFactor ??
      body.conversion_factor ??
      1,
  );
  return attachTenant(
    {
      id: body.id || newId('inv'),
      branchId: String(branchId),
      sku: String(body.sku || '').trim(),
      name: String(body.name || '').trim(),
      category: String(body.category || '').trim(),
      itemType: body.itemType === ITEM_TYPE.PREP ? ITEM_TYPE.PREP : ITEM_TYPE.RAW,
      purchaseUom: String(body.purchaseUom || body.purchase_uom || 'unit').trim(),
      storageUom: String(body.storageUom || body.storage_uom || 'unit').trim(),
      recipeUom: String(body.recipeUom || body.recipe_uom || 'unit').trim(),
      purchaseToStorageFactor: roundQty(
        body.purchaseToStorageFactor ?? body.purchase_to_storage_factor ?? 1,
      ),
      storageToRecipeFactor: storageToRecipe,
      conversionFactor: storageToRecipe,
      currentQty: roundQty(body.currentQty ?? 0),
      avgCost: roundMoneyKwd(body.avgCost ?? 0),
      lastPurchasePrice: roundMoneyKwd(body.lastPurchasePrice ?? 0),
      lastPurchasePriceUom: body.lastPurchasePriceUom || 'recipe',
      minStockAlert: roundQty(body.minStockAlert ?? 0),
      minLevel: roundQty(body.minLevel ?? body.minStockAlert ?? 0),
      parLevel: roundQty(body.parLevel ?? body.par_level ?? 0),
      maxLevel: roundQty(body.maxLevel ?? body.max_level ?? 0),
      yieldQty: roundQty(body.yieldQty ?? body.yield_qty ?? 1),
      shelfLifeDays: roundQty(body.shelfLifeDays ?? body.shelf_life_days ?? 0),
      purchasingUnits: Array.isArray(body.purchasingUnits)
        ? body.purchasingUnits.map((u) => ({
            id: u.id || newId('pu'),
            name: String(u.name || u.purchaseUom || 'unit'),
            factorToStorage: roundQty(u.factorToStorage ?? u.factor_to_storage ?? 1),
          }))
        : [],
      branchLevels: Array.isArray(body.branchLevels)
        ? body.branchLevels.map((row) => ({
            branchId: String(row.branchId || row.branch_id || branchId),
            minLevel: roundQty(row.minLevel ?? 0),
            parLevel: roundQty(row.parLevel ?? 0),
            maxLevel: roundQty(row.maxLevel ?? 0),
          }))
        : [],
      negativeStockFlag: false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    tenantId,
  );
}

const ITEM_PATCH_KEYS = new Set([
  'name',
  'sku',
  'category',
  'itemType',
  'purchaseUom',
  'storageUom',
  'recipeUom',
  'purchaseToStorageFactor',
  'storageToRecipeFactor',
  'conversionFactor',
  'minStockAlert',
  'min_stock_alert',
]);

function patchInventoryItem(existing, body) {
  const next = { ...existing };
  for (const [key, value] of Object.entries(body || {})) {
    const normalized =
      key === 'min_stock_alert'
        ? 'minStockAlert'
        : key === 'purchase_uom'
          ? 'purchaseUom'
          : key === 'storage_uom'
            ? 'storageUom'
            : key === 'recipe_uom'
              ? 'recipeUom'
              : key === 'purchase_to_storage_factor'
                ? 'purchaseToStorageFactor'
                : key === 'storage_to_recipe_factor'
                  ? 'storageToRecipeFactor'
                  : key === 'conversion_factor'
                    ? 'conversionFactor'
                    : key === 'item_type'
                      ? 'itemType'
                      : key;
    if (!ITEM_PATCH_KEYS.has(normalized)) continue;
    if (normalized === 'storageToRecipeFactor' || normalized === 'conversionFactor') {
      next.storageToRecipeFactor = roundQty(value);
      next.conversionFactor = next.storageToRecipeFactor;
    } else if (normalized === 'purchaseToStorageFactor') {
      next.purchaseToStorageFactor = roundQty(value);
    } else if (normalized === 'minStockAlert') {
      next.minStockAlert = roundQty(value);
    } else if (normalized === 'itemType') {
      next.itemType = value === ITEM_TYPE.PREP ? ITEM_TYPE.PREP : ITEM_TYPE.RAW;
    } else {
      next[normalized] = value;
    }
  }
  next.updatedAt = new Date().toISOString();
  return next;
}

function publicInventoryItem(item) {
  return {
    ...item,
    stockValue: roundMoneyKwd((Number(item.currentQty) || 0) * (Number(item.avgCost) || 0)),
  };
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
        applicableOrderTypes: normalizeApplicableOrderTypes(line.applicableOrderTypes),
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

function normalizeApplicableOrderTypes(raw) {
  if (!raw || raw === 'ALL') return ['ALL'];
  const list = Array.isArray(raw) ? raw : [raw];
  const normalized = list.map((v) => String(v).toUpperCase());
  return normalized.every((v) => APPLICABLE_ORDER_TYPES.includes(v))
    ? normalized
    : ['ALL'];
}

module.exports = {
  createInventoryItem,
  patchInventoryItem,
  publicInventoryItem,
  normalizeRecipe,
  normalizePackagingProfile,
  normalizeApplicableOrderTypes,
};