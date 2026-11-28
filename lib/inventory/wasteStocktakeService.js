'use strict';

const {
  LOCATION_KIND,
  MOVE_REFERENCE,
  roundQty,
  newId,
} = require('./constants');
const {
  mutateInventory,
  ensureLocationsInBlob,
  findLocation,
  scopeTenant,
  attachTenant,
} = require('./inventoryRepository');
const { createStockMoveRecord, postMoveOnBranchStock } = require('./stockLedger');

async function recordWaste(dataStore, {
  tenantId,
  branchId,
  itemId,
  qtyInRecipeUom,
  reasonCode,
  createdBy,
}) {
  return mutateInventory(dataStore, tenantId, async (blob) => {
    const locations = ensureLocationsInBlob(blob, tenantId, branchId);
    const stock = findLocation(locations, {
      kind: LOCATION_KIND.BRANCH_STOCK,
      branchId,
    });
    const waste = findLocation(locations, { kind: LOCATION_KIND.WASTE });
    const items = scopeTenant(blob.items, tenantId);
    const item = items.find((row) => String(row.id) === String(itemId));
    if (!item || !stock || !waste) {
      const err = new Error('صنف أو موقع غير موجود');
      err.code = 404;
      throw err;
    }

    const move = createStockMoveRecord({
      tenantId,
      branchId,
      fromLocation: stock,
      toLocation: waste,
      itemId,
      qtyInRecipeUom,
      unitCostSnapshot: item.avgCost || 0,
      referenceType: MOVE_REFERENCE.WASTE,
      referenceId: reasonCode || 'WASTE',
      createdBy,
      notes: reasonCode || '',
    });

    blob.moves = [...(blob.moves || []), move];
    blob.items = postMoveOnBranchStock({ items: blob.items, move });
    return { blob, result: move };
  }).then((out) => out.result || out);
}

async function submitStocktake(dataStore, {
  tenantId,
  branchId,
  lines,
  createdBy,
  stocktakeId,
}) {
  return mutateInventory(dataStore, tenantId, async (blob) => {
    const sid = stocktakeId || newId('stk');
    const locations = ensureLocationsInBlob(blob, tenantId, branchId);
    const stock = findLocation(locations, {
      kind: LOCATION_KIND.BRANCH_STOCK,
      branchId,
    });
    const adjustment = findLocation(locations, { kind: LOCATION_KIND.ADJUSTMENT });
    if (!stock || !adjustment) {
      const err = new Error('مواقع المخزون غير مهيأة');
      err.code = 500;
      throw err;
    }

    const items = scopeTenant(blob.items, tenantId);
    const moves = [];
    const variances = [];

    for (const line of lines || []) {
      const itemIdx = items.findIndex((row) => String(row.id) === String(line.itemId));
      if (itemIdx < 0) continue;
      const item = items[itemIdx];
      const theoretical = roundQty(item.currentQty);
      const actual = roundQty(line.countedQty);
      const variance = roundQty(actual - theoretical);
      if (Math.abs(variance) < 0.00001) continue;

      const isShort = variance < 0;
      const move = createStockMoveRecord({
        tenantId,
        branchId,
        fromLocation: isShort ? stock : adjustment,
        toLocation: isShort ? adjustment : stock,
        itemId: item.id,
        qtyInRecipeUom: Math.abs(variance),
        unitCostSnapshot: item.avgCost || 0,
        referenceType: MOVE_REFERENCE.STOCKTAKE_ADJ,
        referenceId: sid,
        createdBy,
        notes: `theoretical=${theoretical};actual=${actual}`,
      });
      move.adjustmentSign = isShort ? 'MINUS' : 'PLUS';

      moves.push(move);
      item.currentQty = actual;
      item.updatedAt = new Date().toISOString();
      items[itemIdx] = item;

      variances.push({
        itemId: item.id,
        theoreticalQty: theoretical,
        actualQty: actual,
        varianceQty: variance,
        financialLoss: Math.abs(variance) * (Number(item.avgCost) || 0) * (isShort ? 1 : 0),
      });
    }

    const other = blob.items.filter(
      (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
    );
    blob.items = [...other, ...items];
    blob.moves = [...(blob.moves || []), ...moves];

    return {
      blob,
      result: {
        stocktakeId: sid,
        variances,
        moves,
        totalLoss: variances.reduce((sum, row) => sum + row.financialLoss, 0),
      },
    };
  }).then((out) => out.result || out);
}

module.exports = {
  recordWaste,
  submitStocktake,
};