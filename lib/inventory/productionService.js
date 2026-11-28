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

function normalizeProductionLines(body) {
  if (Array.isArray(body.lines) && body.lines.length > 0) {
    return body.lines.map((line) => ({
      prepItemId: String(line.prepItemId || line.prep_item_id),
      outputQtyInRecipeUom: roundQty(
        line.outputQtyInRecipeUom ?? line.outputQty ?? line.qty ?? 0,
      ),
    }));
  }
  const prepId = body.prepItemId || body.prep_item_id;
  if (prepId) {
    return [
      {
        prepItemId: String(prepId),
        outputQtyInRecipeUom: roundQty(
          body.outputQtyInRecipeUom ?? body.outputQty ?? body.qty ?? 0,
        ),
      },
    ];
  }
  const err = new Error('أضف سطر إنتاج واحد على الأقل');
  err.code = 400;
  throw err;
}

function productionLinesFromDoc(doc) {
  if (Array.isArray(doc.lines) && doc.lines.length > 0) return doc.lines;
  if (doc.prepItemId) {
    return [
      {
        prepItemId: String(doc.prepItemId),
        outputQtyInRecipeUom: roundQty(doc.outputQtyInRecipeUom || 0),
      },
    ];
  }
  return [];
}

function createProductionRecord(body, tenantId, branchId) {
  const lines = normalizeProductionLines(body);
  const record = {
    id: body.id || newId('prd'),
    status: DOC_STATUS.DRAFT,
    branchId: String(branchId),
    lines,
    notes: String(body.notes || '').trim(),
    createdAt: new Date().toISOString(),
  };
  if (lines.length === 1) {
    record.prepItemId = lines[0].prepItemId;
    record.outputQtyInRecipeUom = lines[0].outputQtyInRecipeUom;
  }
  return attachTenant(record, tenantId);
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
    const lines = productionLinesFromDoc(doc);
    if (!lines.length) {
      const err = new Error('لا توجد بنود إنتاج');
      err.code = 400;
      throw err;
    }

    const recipes = scopeTenant(blob.recipes, tenantId);
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

    const moves = [];
    let inputCost = 0;
    const lineSummaries = [];

    for (const line of lines) {
      let items = scopeTenant(blob.items, tenantId);
      const itemsById = new Map(items.map((row) => [String(row.id), row]));
      const prepItem = itemsById.get(String(line.prepItemId));
      if (!prepItem || prepItem.itemType !== ITEM_TYPE.PREP) {
        const err = new Error('صنف التحضير غير صالح');
        err.code = 400;
        throw err;
      }

      const requirements = mergeRequirements(
        explodePrepRecipe(
          itemsById,
          recipes,
          line.prepItemId,
          line.outputQtyInRecipeUom,
        ),
      );
      let lineInputCost = 0;
      for (const need of requirements) {
        const item = itemsById.get(String(need.itemId));
        if (!item) continue;
        const unit = Number(item.avgCost) || 0;
        lineInputCost += need.qtyInRecipeUom * unit;
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
        items = scopeTenant(blob.items, tenantId);
        itemsById.set(String(need.itemId), items.find((r) => String(r.id) === String(need.itemId)));
      }

      const outputQty = line.outputQtyInRecipeUom;
      const outputUnitCost = roundMoneyKwd(outputQty > 0 ? lineInputCost / outputQty : 0);
      const prepIdx = items.findIndex((row) => String(row.id) === String(line.prepItemId));
      if (prepIdx >= 0) {
        const prep = { ...items[prepIdx] };
        prep.avgCost = computeAvco({
          currentQty: prep.currentQty,
          currentAvgCost: prep.avgCost,
          purchasedQty: outputQty,
          purchaseUnitCost: outputUnitCost,
        });
        prep.currentQty = roundQty((Number(prep.currentQty) || 0) + outputQty);
        prep.updatedAt = new Date().toISOString();
        items[prepIdx] = prep;
      }

      blob.items = [
        ...blob.items.filter(
          (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
        ),
        ...items,
      ];

      inputCost += lineInputCost;
      lineSummaries.push({
        prepItemId: line.prepItemId,
        outputQtyInRecipeUom: outputQty,
        inputCost: roundMoneyKwd(lineInputCost),
        outputUnitCost,
      });
    }

    const closedPatch = {
      status: DOC_STATUS.CLOSED,
      closedAt: new Date().toISOString(),
      closedBy: createdBy,
      lines,
      inputCost: roundMoneyKwd(inputCost),
      lineSummaries,
    };
    if (lines.length === 1) {
      closedPatch.prepItemId = lines[0].prepItemId;
      closedPatch.outputQtyInRecipeUom = lines[0].outputQtyInRecipeUom;
      closedPatch.outputUnitCost = lineSummaries[0]?.outputUnitCost;
    }

    productions[idx] = {
      ...doc,
      ...closedPatch,
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
  normalizeProductionLines,
  productionLinesFromDoc,
  createProductionRecord,
  closeProduction,
};