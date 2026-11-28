'use strict';

const {
  DOC_STATUS,
  LOCATION_KIND,
  MOVE_REFERENCE,
  ITEM_TYPE,
  roundQty,
  roundMoneyKwd,
  newId,
  isDocDraft,
} = require('./constants');
const { computeAvco } = require('./avco');
const {
  mutateInventory,
  ensureLocationsInBlob,
  findLocation,
  scopeTenant,
  attachTenant,
} = require('./inventoryRepository');
const { createStockMoveRecord, postMoveOnBranchStock } = require('./stockLedger');
const { explodePrepRecipe, mergeRequirements } = require('./recipeExplosion');

function createProductionRecord(body, tenantId, branchId) {
  return attachTenant(
    {
      id: body.id || newId('prd'),
      status: DOC_STATUS.DRAFT,
      branchId: String(branchId),
      prepItemId: String(body.prepItemId || body.prep_item_id),
      outputQtyInRecipeUom: roundQty(
        body.outputQtyInRecipeUom || body.outputQty || body.qty || 0,
      ),
      notes: String(body.notes || '').trim(),
      createdAt: new Date().toISOString(),
    },
    tenantId,
  );
}

async function closeProduction(dataStore, { tenantId, branchId, productionId, createdBy }) {
  return mutateInventory(dataStore, tenantId, async (blob) => {
    const productions = scopeTenant(blob.productions, tenantId);
    const idx = productions.findIndex((p) => String(p.id) === String(productionId));
    if (idx < 0) {
      const err = new Error('وثيقة الإنتاج غير موجودة');
      err.code = 404;
      throw err;
    }
    const doc = productions[idx];
    if (!isDocDraft(doc.status)) {
      const err = new Error('الإنتاج مغلق مسبقاً');
      err.code = 409;
      throw err;
    }
    const items = scopeTenant(blob.items, tenantId);
    const recipes = scopeTenant(blob.recipes, tenantId);
    const itemsById = new Map(items.map((row) => [String(row.id), row]));
    const prepItem = itemsById.get(String(doc.prepItemId));
    if (!prepItem || prepItem.itemType !== ITEM_TYPE.PREP) {
      const err = new Error('صنف التحضير غير صالح');
      err.code = 400;
      throw err;
    }

    const locations = ensureLocationsInBlob(blob, tenantId, branchId);
    const stock = findLocation(locations, {
      kind: LOCATION_KIND.BRANCH_STOCK,
      branchId,
    });
    const prepLoc = findLocation(locations, {
      kind: LOCATION_KIND.KITCHEN_PREP,
      branchId,
    });
    const customer = findLocation(locations, { kind: LOCATION_KIND.CUSTOMER });
    const consumeFrom = stock || prepLoc;
    if (!consumeFrom || !prepLoc) {
      const err = new Error('مواقع المخزون غير مهيأة');
      err.code = 500;
      throw err;
    }

    const requirements = mergeRequirements(
      explodePrepRecipe(itemsById, recipes, doc.prepItemId, doc.outputQtyInRecipeUom),
    );
    const moves = [];
    let inputCost = 0;
    for (const need of requirements) {
      const item = itemsById.get(String(need.itemId));
      if (!item) continue;
      const unit = Number(item.avgCost) || 0;
      inputCost += need.qtyInRecipeUom * unit;
      const move = createStockMoveRecord({
        tenantId,
        branchId,
        fromLocation: consumeFrom,
        toLocation: customer,
        itemId: need.itemId,
        qtyInRecipeUom: need.qtyInRecipeUom,
        unitCostSnapshot: unit,
        referenceType: MOVE_REFERENCE.PREP_PRODUCTION,
        referenceId: doc.id,
        negativeStockFlag: true,
        createdBy,
      });
      moves.push(move);
      blob.items = postMoveOnBranchStock({ items: blob.items, move });
    }

    const outputUnitCost = roundMoneyKwd(
      doc.outputQtyInRecipeUom > 0 ? inputCost / doc.outputQtyInRecipeUom : 0,
    );
    const prepIdx = items.findIndex((row) => String(row.id) === String(doc.prepItemId));
    if (prepIdx >= 0) {
      const prep = { ...items[prepIdx] };
      prep.avgCost = computeAvco({
        currentQty: prep.currentQty,
        currentAvgCost: prep.avgCost,
        purchasedQty: doc.outputQtyInRecipeUom,
        purchaseUnitCost: outputUnitCost,
      });
      prep.currentQty = roundQty((Number(prep.currentQty) || 0) + doc.outputQtyInRecipeUom);
      prep.updatedAt = new Date().toISOString();
      items[prepIdx] = prep;
    }

    blob.items = [
      ...blob.items.filter(
        (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
      ),
      ...items,
    ];
    productions[idx] = {
      ...doc,
      status: DOC_STATUS.CLOSED,
      closedAt: new Date().toISOString(),
      closedBy: createdBy,
      outputUnitCost,
      inputCost: roundMoneyKwd(inputCost),
    };
    blob.moves = [...(blob.moves || []), ...moves];
    blob.productions = [
      ...blob.productions.filter(
        (p) => String(p.tenantId || p.restaurantId) !== String(tenantId),
      ),
      ...productions,
    ];
    return { blob, result: productions[idx] };
  });
}

module.exports = {
  createProductionRecord,
  closeProduction,
};