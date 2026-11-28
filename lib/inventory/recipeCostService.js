'use strict';

const { roundMoneyKwd, roundQty, SALES_CHANNEL } = require('./constants');
const { scopeTenant } = require('./inventoryRepository');
const { estimateRecipeCost } = require('./marginGuard');

function packagingCost(profile, itemsById) {
  let total = 0;
  for (const line of profile?.lines || profile?.ingredients || []) {
    const item = itemsById.get(String(line.itemId));
    if (!item) continue;
    const qty = roundQty(line.qtyInRecipeUom || line.qty || 0);
    total += qty * (Number(item.avgCost) || 0);
  }
  return roundMoneyKwd(total);
}

function estimateMenuItemCost({
  menuItemId,
  channel,
  recipes,
  packagingProfiles,
  items,
  tenantId,
  menuItem,
}) {
  const recipeRows = scopeTenant(recipes, tenantId);
  const itemRows = scopeTenant(items, tenantId);
  const itemsById = new Map(itemRows.map((row) => [String(row.id), row]));
  const recipe = recipeRows.find((row) => String(row.menuItemId) === String(menuItemId));
  const foodCost = recipe ? estimateRecipeCost(recipe, itemsById) : 0;

  const profiles = scopeTenant(packagingProfiles, tenantId);
  const normalizedChannel = String(channel || SALES_CHANNEL.TAKEAWAY).toUpperCase();
  const pack =
    profiles.find((p) => p.channel === normalizedChannel) ||
    (normalizedChannel !== SALES_CHANNEL.DINE_IN
      ? profiles.find((p) => p.channel === SALES_CHANNEL.TAKEAWAY)
      : null);
  const packaging = normalizedChannel === SALES_CHANNEL.DINE_IN ? 0 : packagingCost(pack, itemsById);
  const totalCost = roundMoneyKwd(foodCost + packaging);
  const price = Number(menuItem?.price) || 0;
  const marginPct = price > 0 ? roundMoneyKwd((price - totalCost) / price) : 0;

  return {
    menuItemId: String(menuItemId),
    channel: normalizedChannel,
    foodCost,
    packagingCost: packaging,
    totalCost,
    menuPrice: price,
    marginPct,
    marginAmount: roundMoneyKwd(price - totalCost),
    recipeId: recipe?.id || null,
  };
}

module.exports = {
  estimateMenuItemCost,
};