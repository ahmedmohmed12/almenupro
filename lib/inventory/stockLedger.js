'use strict';

const {
  MOVE_REFERENCE,
  PHYSICAL_KINDS,
  roundQty,
  roundMoneyKwd,
  newId,
} = require('./constants');
const { attachTenant } = require('./inventoryRepository');

function canMutateQtyWithoutMove() {
  return false;
}

/**
 * Creates an immutable stock move. Never change qty without this.
 */
function createStockMoveRecord({
  tenantId,
  branchId,
  fromLocation,
  toLocation,
  itemId,
  qtyInRecipeUom,
  unitCostSnapshot,
  referenceType,
  referenceId,
  negativeStockFlag = false,
  createdBy,
  notes = '',
  reversalOfMoveId = null,
}) {
  const qty = roundQty(qtyInRecipeUom);
  const unitCost = roundMoneyKwd(unitCostSnapshot);
  return attachTenant(
    {
      id: newId('smv'),
      branchId: String(branchId),
      fromLocationId: fromLocation.id,
      fromLocationKind: fromLocation.kind,
      toLocationId: toLocation.id,
      toLocationKind: toLocation.kind,
      itemId: String(itemId),
      qtyInRecipeUom: qty,
      unitCostSnapshot: unitCost,
      totalCost: roundMoneyKwd(qty * unitCost),
      referenceType,
      referenceId: String(referenceId || ''),
      negativeStockFlag: negativeStockFlag === true,
      reversalOfMoveId,
      notes: String(notes || '').trim(),
      createdBy: createdBy ? String(createdBy) : null,
      createdAt: new Date().toISOString(),
    },
    tenantId,
  );
}

function qtyDeltaForMove(move) {
  const qty = roundQty(move.qtyInRecipeUom);
  const fromPhysical = PHYSICAL_KINDS.has(move.fromLocationKind);
  const toPhysical = PHYSICAL_KINDS.has(move.toLocationKind);

  if (fromPhysical && !toPhysical) return -qty;
  if (!fromPhysical && toPhysical) return qty;
  if (fromPhysical && toPhysical) {
    if (move.referenceType === MOVE_REFERENCE.STOCKTAKE_ADJ) {
      return move.adjustmentSign === 'PLUS' ? qty : -qty;
    }
    return -qty;
  }
  return 0;
}

function postMoveOnBranchStock({ items, move }) {
  const allIdx = items.findIndex((row) => String(row.id) === String(move.itemId));
  if (allIdx < 0) return items;

  const item = { ...items[allIdx] };
  const delta = qtyDeltaForMove(move);
  const nextQty = roundQty((Number(item.currentQty) || 0) + delta);
  item.currentQty = nextQty;
  if (nextQty < 0 && move.negativeStockFlag) {
    item.negativeStockFlag = true;
  }
  item.updatedAt = new Date().toISOString();
  items[allIdx] = item;
  return items;
}

function reverseMoveRecord(move, { createdBy, reason }) {
  return createStockMoveRecord({
    tenantId: move.tenantId || move.restaurantId,
    branchId: move.branchId,
    fromLocation: {
      id: move.toLocationId,
      kind: move.toLocationKind,
    },
    toLocation: {
      id: move.fromLocationId,
      kind: move.fromLocationKind,
    },
    itemId: move.itemId,
    qtyInRecipeUom: move.qtyInRecipeUom,
    unitCostSnapshot: move.unitCostSnapshot,
    referenceType: MOVE_REFERENCE.REVERSAL,
    referenceId: move.id,
    createdBy,
    notes: reason || `Reversal of ${move.id}`,
    reversalOfMoveId: move.id,
  });
}

module.exports = {
  canMutateQtyWithoutMove,
  createStockMoveRecord,
  postMoveOnBranchStock,
  reverseMoveRecord,
};