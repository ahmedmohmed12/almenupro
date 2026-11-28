'use strict';

const { roundQty } = require('./constants');
const { scopeTenant } = require('./inventoryRepository');

function mapSalesChannel(order) {
  const orderType = String(
    order.orderType || order.order_type || order.orderSource || '',
  )
    .trim()
    .toLowerCase();
  const source = String(order.orderSource || order.order_source || '')
    .trim()
    .toLowerCase();

  if (orderType.includes('dine')) return 'DINE_IN';
  if (source.includes('talabat') || source.includes('keeta') || source.includes('aggregator')) {
    return 'AGGREGATOR';
  }
  if (orderType.includes('delivery')) return 'DELIVERY';
  if (orderType.includes('pickup') || orderType.includes('takeaway')) return 'TAKEAWAY';
  return 'TAKEAWAY';
}

/**
 * Flatten menu lines + modifiers + nested PREP into net ingredient requirements.
 */
function flattenOrderRequirements({
  order,
  recipes,
  packagingProfiles,
  itemsById,
  tenantId,
}) {
  const recipeRows = scopeTenant(recipes, tenantId);
  const packagingRows = scopeTenant(packagingProfiles, tenantId);
  const channel = mapSalesChannel(order);
  const requirements = new Map();

  const addNeed = (itemId, qty) => {
    const id = String(itemId);
    const q = roundQty(qty);
    if (!id || q <= 0) return;
    requirements.set(id, roundQty((requirements.get(id) || 0) + q));
  };

  const expandPrep = (itemId, qty, depth = 0) => {
    if (depth > 8) return;
    const prep = itemsById.get(String(itemId));
    const prepRecipe = recipeRows.find(
      (r) =>
        r.prepItemId === itemId ||
        (r.menuItemId == null && r.itemId === itemId && prep?.itemType === 'PREP'),
    );
    if (!prepRecipe || !Array.isArray(prepRecipe.ingredients)) {
      addNeed(itemId, qty);
      return;
    }
    const yieldQty = roundQty(prepRecipe.expectedYieldQty || prepRecipe.yieldQty || 1);
    const factor = yieldQty > 0 ? qty / yieldQty : qty;
    for (const line of prepRecipe.ingredients) {
      expandPrep(line.itemId, roundQty(line.qtyInRecipeUom) * factor, depth + 1);
    }
  };

  const lines = Array.isArray(order.items) ? order.items : [];
  for (const line of lines) {
    const menuItemId =
      line.menuItemId ||
      line.menu_item_id ||
      line.id ||
      line.itemId ||
      line.item_id;
    const lineQty = roundQty(line.quantity ?? line.qty ?? 1);
    const recipe = recipeRows.find(
      (r) => String(r.menuItemId) === String(menuItemId),
    );
    if (!recipe) continue;
    for (const ing of recipe.ingredients || []) {
      const baseQty = roundQty(ing.qtyInRecipeUom) * lineQty;
      const item = itemsById.get(String(ing.itemId));
      if (item?.itemType === 'PREP') {
        expandPrep(ing.itemId, baseQty);
      } else {
        addNeed(ing.itemId, baseQty);
      }
    }
    for (const mod of line.modifiers || line.selectedModifiers || []) {
      const modRecipe = recipeRows.find(
        (r) => String(r.modifierId) === String(mod.id || mod.modifierId),
      );
      if (!modRecipe) continue;
      const modQty = roundQty(mod.quantity ?? 1) * lineQty;
      for (const ing of modRecipe.ingredients || []) {
        expandPrep(ing.itemId, roundQty(ing.qtyInRecipeUom) * modQty);
      }
    }
  }

  const packProfile =
    packagingRows.find((p) => p.channel === channel) ||
    packagingRows.find((p) => p.channel === 'TAKEAWAY');
  if (packProfile && channel !== 'DINE_IN') {
    for (const pack of packProfile.lines || packProfile.ingredients || []) {
      addNeed(pack.itemId, pack.qtyInRecipeUom || pack.qty || 0);
    }
  }

  return {
    channel,
    requirements: [...requirements.entries()].map(([itemId, qtyInRecipeUom]) => ({
      itemId,
      qtyInRecipeUom,
    })),
  };
}

module.exports = {
  flattenOrderRequirements,
  mapSalesChannel,
};