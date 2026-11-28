'use strict';

const {
  DOC_STATUS,
  LOCATION_KIND,
  MOVE_REFERENCE,
  roundQty,
  newId,
  isDocDraft,
} = require('./constants');
const {
  mutateInventory,
  ensureLocationsInBlob,
  findLocation,
  scopeTenant,
  attachTenant,
} = require('./inventoryRepository');
const { createStockMoveRecord, postMoveOnBranchStock } = require('./stockLedger');

function createCountSession(body, tenantId, branchId) {
  return attachTenant(
    {
      id: body.id || newId('cnt'),
      status: DOC_STATUS.DRAFT,
      branchId: String(branchId),
      categoryFilter: String(body.categoryFilter || body.category || '').trim(),
      blindCount: body.blindCount === true || body.blind_count === true,
      lines: (Array.isArray(body.lines) ? body.lines : []).map((line) => ({
        itemId: String(line.itemId),
        countedQty: roundQty(line.countedQty ?? line.counted_qty),
      })),
      createdAt: new Date().toISOString(),
    },
    tenantId,
  );
}

async function closeCountSession(dataStore, { tenantId, branchId, countId, createdBy }) {
  return mutateInventory(dataStore, tenantId, async (blob) => {
    const sessions = scopeTenant(blob.inventoryCounts, tenantId);
    const idx = sessions.findIndex((c) => String(c.id) === String(countId));
    if (idx < 0) {
      const err = new Error('جلسة الجرد غير موجودة');
      err.code = 404;
      throw err;
    }
    const doc = sessions[idx];
    if (!isDocDraft(doc.status)) {
      const err = new Error('الجرد مغلق مسبقاً');
      err.code = 409;
      throw err;
    }

    let items = scopeTenant(blob.items, tenantId);
    if (doc.categoryFilter) {
      const cat = doc.categoryFilter.toLowerCase();
      items = items.filter((row) => String(row.category || '').toLowerCase() === cat);
    }
    const itemIds = new Set(items.map((row) => String(row.id)));

    const locations = ensureLocationsInBlob(blob, tenantId, branchId);
    const stock = findLocation(locations, {
      kind: LOCATION_KIND.BRANCH_STOCK,
      branchId,
    });
    const adjustment = findLocation(locations, { kind: LOCATION_KIND.ADJUSTMENT });
    const moves = [];
    const variances = [];

    const lines = doc.lines.filter((line) => itemIds.has(String(line.itemId)));
    const allItems = scopeTenant(blob.items, tenantId);

    for (const line of lines) {
      const itemIdx = allItems.findIndex((row) => String(row.id) === String(line.itemId));
      if (itemIdx < 0) continue;
      const item = allItems[itemIdx];
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
        referenceId: doc.id,
        createdBy,
        notes: `count theoretical=${theoretical} actual=${actual}`,
      });
      move.adjustmentSign = isShort ? 'MINUS' : 'PLUS';
      moves.push(move);
      item.currentQty = actual;
      item.updatedAt = new Date().toISOString();
      allItems[itemIdx] = item;
      variances.push({
        itemId: item.id,
        theoreticalQty: theoretical,
        actualQty: actual,
        varianceQty: variance,
        varianceCost: Math.abs(variance) * (Number(item.avgCost) || 0) * (isShort ? 1 : 0),
      });
    }

    sessions[idx] = {
      ...doc,
      status: DOC_STATUS.CLOSED,
      closedAt: new Date().toISOString(),
      closedBy: createdBy,
      variances,
      totalVarianceCost: variances.reduce((s, r) => s + r.varianceCost, 0),
    };
    blob.items = [
      ...blob.items.filter(
        (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
      ),
      ...allItems,
    ];
    blob.moves = [...(blob.moves || []), ...moves];
    blob.inventoryCounts = [
      ...blob.inventoryCounts.filter(
        (c) => String(c.tenantId || c.restaurantId) !== String(tenantId),
      ),
      ...sessions,
    ];
    return { blob, result: sessions[idx] };
  });
}

module.exports = {
  createCountSession,
  closeCountSession,
};