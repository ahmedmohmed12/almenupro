'use strict';

const { roundMoneyKwd } = require('./constants');
const { scopeTenant } = require('./inventoryRepository');

function estimateRecipeCost(recipe, itemsById) {
  let total = 0;
  for (const line of recipe.ingredients || []) {
    const item = itemsById.get(String(line.itemId));
    if (!item) continue;
    const qty = Number(line.qtyInRecipeUom) || 0;
    const cost = Number(item.avgCost) || 0;
    total += qty * cost;
  }
  return roundMoneyKwd(total);
}

function evaluateMarginAlerts({ recipes, items, menuItems, tenantId, thresholdPct = 0.25 }) {
  const recipeRows = scopeTenant(recipes, tenantId);
  const itemRows = scopeTenant(items, tenantId);
  const itemsById = new Map(itemRows.map((row) => [String(row.id), row]));
  const menuById = new Map(
    (Array.isArray(menuItems) ? menuItems : []).map((row) => [String(row.id), row]),
  );
  const alerts = [];
  for (const recipe of recipeRows) {
    if (!recipe.menuItemId) continue;
    const menu = menuById.get(String(recipe.menuItemId));
    if (!menu) continue;
    const price = Number(menu.price) || 0;
    if (price <= 0) continue;
    const foodCost = estimateRecipeCost(recipe, itemsById);
    const margin = price > 0 ? (price - foodCost) / price : 0;
    const minMargin =
      Number(recipe.minMarginPct ?? recipe.marginThreshold ?? thresholdPct) || thresholdPct;
    if (margin < minMargin) {
      alerts.push({
        menuItemId: recipe.menuItemId,
        menuItemName: menu.name || menu.name_ar,
        price,
        foodCost,
        marginPct: roundMoneyKwd(margin),
        thresholdPct: minMargin,
      });
    }
  }
  return alerts;
}

module.exports = {
  estimateRecipeCost,
  evaluateMarginAlerts,
};