'use strict';

const { roundQty } = require('./constants');
const { scopeTenant } = require('./inventoryRepository');

function normalizeApplicableTypes(raw) {
  if (!raw || raw === 'ALL') return ['ALL'];
  if (Array.isArray(raw)) return raw.map((v) => String(v).toUpperCase());
  return [String(raw).toUpperCase()];
}

function ingredientApplies(ingredient, channel) {
  const types = normalizeApplicableTypes(ingredient.applicableOrderTypes);
  if (types.includes('ALL')) return true;
  return types.includes(String(channel || 'TAKEAWAY').toUpperCase());
}

function explodePrepRecipe(itemsById, recipes, prepItemId, qty, depth = 0) {
  if (depth > 10) return [];
  const prep = itemsById.get(String(prepItemId));
  const prepRecipe = recipes.find(
    (r) =>
      String(r.prepItemId) === String(prepItemId) ||
      (r.menuItemId == null && String(r.itemId) === String(prepItemId)),
  );
  if (!prepRecipe?.ingredients?.length) {
    return [{ itemId: String(prepItemId), qtyInRecipeUom: roundQty(qty) }];
  }
  const yieldQty = roundQty(prepRecipe.expectedYieldQty || prep?.yieldQty || 1);
  const factor = yieldQty > 0 ? qty / yieldQty : qty;
  const needs = [];
  for (const ing of prepRecipe.ingredients) {
    const childQty = roundQty((Number(ing.qtyInRecipeUom) || 0) * factor);
    const child = itemsById.get(String(ing.itemId));
    if (child?.itemType === 'PREP') {
      needs.push(...explodePrepRecipe(itemsById, recipes, ing.itemId, childQty, depth + 1));
    } else {
      needs.push({ itemId: String(ing.itemId), qtyInRecipeUom: childQty });
    }
  }
  return needs;
}

function mergeRequirements(rows) {
  const map = new Map();
  for (const row of rows) {
    const id = String(row.itemId);
    const q = roundQty(row.qtyInRecipeUom);
    map.set(id, roundQty((map.get(id) || 0) + q));
  }
  return [...map.entries()].map(([itemId, qtyInRecipeUom]) => ({ itemId, qtyInRecipeUom }));
}

function explodeMenuItemToRequirements({
  menuItemId,
  qty,
  channel,
  recipes,
  items,
  tenantId,
}) {
  const recipeRows = scopeTenant(recipes, tenantId);
  const itemRows = scopeTenant(items, tenantId);
  const itemsById = new Map(itemRows.map((row) => [String(row.id), row]));
  const recipe = recipeRows.find((r) => String(r.menuItemId) === String(menuItemId));
  if (!recipe) return [];
  const lineQty = roundQty(qty);
  const needs = [];
  for (const ing of recipe.ingredients || []) {
    if (!ingredientApplies(ing, channel)) continue;
    const base = roundQty((Number(ing.qtyInRecipeUom) || 0) * lineQty);
    const item = itemsById.get(String(ing.itemId));
    if (item?.itemType === 'PREP') {
      needs.push(...explodePrepRecipe(itemsById, recipeRows, ing.itemId, base));
    } else {
      needs.push({ itemId: String(ing.itemId), qtyInRecipeUom: base });
    }
  }
  return mergeRequirements(needs);
}

module.exports = {
  explodeMenuItemToRequirements,
  explodePrepRecipe,
  mergeRequirements,
  ingredientApplies,
};