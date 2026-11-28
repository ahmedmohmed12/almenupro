'use strict';

const {
  DOC_STATUS,
  LOCATION_KIND,
  MOVE_REFERENCE,
  WASTE_REASON_CODES,
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
const { explodeMenuItemToRequirements, mergeRequirements } = require('./recipeExplosion');

function createWasteDocument(body, tenantId, branchId) {
  return attachTenant(
    {
      id: body.id || newId('wst'),
      status: DOC_STATUS.DRAFT,
      branchId: String(branchId),
      lines: (Array.isArray(body.lines) ? body.lines : []).map((line) => ({
        lineType: line.menuItemId ? 'MENU' : 'ITEM',
        itemId: line.itemId ? String(line.itemId) : null,
        menuItemId: line.menuItemId ? String(line.menuItemId) : null,
        qty: roundQty(line.qty || line.qtyInRecipeUom || 1),
        wasteReason: WASTE_REASON_CODES.includes(line.wasteReason)
          ? line.wasteReason
          : line.wasteReason || 'OTHER',
        channel: line.channel || 'TAKEAWAY',
      })),
      createdAt: new Date().toISOString(),
    },
    tenantId,
  );
}

async function closeWasteDocument(dataStore, { tenantId, branchId, wasteId, createdBy }) {
  return mutateInventory(dataStore, tenantId, async (blob) => {
    const docs = scopeTenant(blob.wasteDocuments, tenantId);
    const idx = docs.findIndex((d) => String(d.id) === String(wasteId));
    if (idx < 0) {
      const err = new Error('وثيقة الهالك غير موجودة');
      err.code = 404;
      throw err;
    }
    const doc = docs[idx];
    if (!isDocDraft(doc.status)) {
      const err = new Error('وثيقة الهالك مغلقة');
      err.code = 409;
      throw err;
    }

    const locations = ensureLocationsInBlob(blob, tenantId, branchId);
    const stock = findLocation(locations, {
      kind: LOCATION_KIND.BRANCH_STOCK,
      branchId,
    });
    const waste = findLocation(locations, { kind: LOCATION_KIND.WASTE });
    const requirements = [];

    for (const line of doc.lines) {
      if (line.lineType === 'MENU' && line.menuItemId) {
        requirements.push(
          ...explodeMenuItemToRequirements({
            menuItemId: line.menuItemId,
            qty: line.qty,
            channel: line.channel,
            recipes: blob.recipes,
            items: blob.items,
            tenantId,
          }),
        );
      } else if (line.itemId) {
        requirements.push({
          itemId: line.itemId,
          qtyInRecipeUom: roundQty(line.qty),
          wasteReason: line.wasteReason,
        });
      }
    }

    const merged = mergeRequirements(requirements);
    const moves = [];
    let totalCost = 0;
    for (const need of merged) {
      const items = scopeTenant(blob.items, tenantId);
      const item = items.find((row) => String(row.id) === String(need.itemId));
      if (!item || !stock || !waste) continue;
      const unit = Number(item.avgCost) || 0;
      totalCost += need.qtyInRecipeUom * unit;
      const move = createStockMoveRecord({
        tenantId,
        branchId,
        fromLocation: stock,
        toLocation: waste,
        itemId: need.itemId,
        qtyInRecipeUom: need.qtyInRecipeUom,
        unitCostSnapshot: unit,
        referenceType: MOVE_REFERENCE.WASTE,
        referenceId: doc.id,
        createdBy,
        notes: need.wasteReason || doc.lines[0]?.wasteReason || 'WASTE',
      });
      moves.push(move);
      blob.items = postMoveOnBranchStock({ items: blob.items, move });
    }

    docs[idx] = {
      ...doc,
      status: DOC_STATUS.CLOSED,
      closedAt: new Date().toISOString(),
      closedBy: createdBy,
      totalWasteCost: roundQty(totalCost),
      moveIds: moves.map((m) => m.id),
    };
    blob.moves = [...(blob.moves || []), ...moves];
    blob.wasteDocuments = [
      ...blob.wasteDocuments.filter(
        (d) => String(d.tenantId || d.restaurantId) !== String(tenantId),
      ),
      ...docs,
    ];
    return { blob, result: docs[idx] };
  });
}

module.exports = {
  createWasteDocument,
  closeWasteDocument,
  WASTE_REASON_CODES,
};