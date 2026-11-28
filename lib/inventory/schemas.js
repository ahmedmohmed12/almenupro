'use strict';

/**
 * Document shapes for inventory_ledger (Mongo `named_docs` / AVCO engine).
 * Validation layer — not Mongoose; keeps tenant-scoped blob storage portable.
 */

const {
  DOC_STATUS,
  ITEM_TYPE,
  LOCATION_KIND,
  MOVE_REFERENCE,
  TRANSFER_STAGE,
  WASTE_REASON_CODES,
  APPLICABLE_ORDER_TYPES,
  roundQty,
  roundMoneyKwd,
} = require('./constants');

function assertObject(row, name) {
  if (!row || typeof row !== 'object') {
    const err = new Error(`${name}: expected object`);
    err.code = 400;
    throw err;
  }
}

function validateInventoryItem(row, { partial = false } = {}) {
  assertObject(row, 'InventoryItem');
  if (!partial && !row.id) {
    const err = new Error('InventoryItem.id required');
    err.code = 400;
    throw err;
  }
  if (row.itemType != null && ![ITEM_TYPE.RAW, ITEM_TYPE.PREP].includes(row.itemType)) {
    const err = new Error('InventoryItem.itemType must be RAW or PREP');
    err.code = 400;
    throw err;
  }
  return {
  ...row,
    currentQty: roundQty(row.currentQty),
    avgCost: roundMoneyKwd(row.avgCost),
    lastPurchasePrice: roundMoneyKwd(row.lastPurchasePrice),
    yieldQty: roundQty(row.yieldQty ?? 1),
    shelfLifeDays: roundQty(row.shelfLifeDays ?? 0),
    storageToRecipeFactor: roundQty(row.storageToRecipeFactor ?? row.conversionFactor ?? 1),
  };
}

function validateStockLocation(row) {
  assertObject(row, 'StockLocation');
  if (!Object.values(LOCATION_KIND).includes(row.kind)) {
    const err = new Error('StockLocation.kind invalid');
    err.code = 400;
    throw err;
  }
  return row;
}

function validateStockMove(row) {
  assertObject(row, 'StockMove');
  if (!row.id || !row.itemId) {
    const err = new Error('StockMove requires id and itemId');
    err.code = 400;
    throw err;
  }
  if (row.referenceType && !Object.values(MOVE_REFERENCE).includes(row.referenceType)) {
    const err = new Error('StockMove.referenceType invalid');
    err.code = 400;
    throw err;
  }
  return {
    ...row,
    qtyInRecipeUom: roundQty(row.qtyInRecipeUom),
    unitCostSnapshot: roundMoneyKwd(row.unitCostSnapshot),
    totalCost: roundMoneyKwd(
      row.totalCost ?? roundQty(row.qtyInRecipeUom) * roundMoneyKwd(row.unitCostSnapshot),
    ),
    negativeStockFlag: row.negativeStockFlag === true,
  };
}

function validateRecipe(row) {
  assertObject(row, 'Recipe');
  if (!row.menuItemId && !row.modifierId && !row.prepItemId) {
    const err = new Error('Recipe must link menuItemId, modifierId, or prepItemId');
    err.code = 400;
    throw err;
  }
  const ingredients = Array.isArray(row.ingredients) ? row.ingredients : [];
  for (const ing of ingredients) {
    const types = ing.applicableOrderTypes || ['ALL'];
    const list = Array.isArray(types) ? types : [types];
    for (const t of list) {
      if (!APPLICABLE_ORDER_TYPES.includes(String(t).toUpperCase())) {
        const err = new Error(`Recipe ingredient channel invalid: ${t}`);
        err.code = 400;
        throw err;
      }
    }
  }
  return row;
}

function validatePackagingProfile(row) {
  assertObject(row, 'PackagingProfile');
  return row;
}

function validateTransactionDoc(row, { types = Object.values(DOC_STATUS) } = {}) {
  assertObject(row, 'Transaction');
  if (row.status && !types.includes(row.status) && row.status !== 'APPROVED') {
    const err = new Error('Transaction.status invalid');
    err.code = 400;
    throw err;
  }
  return row;
}

function validateTransfer(row) {
  validateTransactionDoc(row);
  if (row.stage && !Object.values(TRANSFER_STAGE).includes(row.stage)) {
    const err = new Error('Transfer.stage invalid');
    err.code = 400;
    throw err;
  }
  return row;
}

function validateWasteDocument(row) {
  validateTransactionDoc(row);
  const lines = Array.isArray(row.lines) ? row.lines : [];
  for (const line of lines) {
    if (line.wasteReason && !WASTE_REASON_CODES.includes(line.wasteReason)) {
      const err = new Error(`Waste reason invalid: ${line.wasteReason}`);
      err.code = 400;
      throw err;
    }
  }
  return row;
}

function validateInventoryCount(row) {
  validateTransactionDoc(row);
  if (row.blindCount != null && typeof row.blindCount !== 'boolean') {
    const err = new Error('InventoryCount.blindCount must be boolean');
    err.code = 400;
    throw err;
  }
  return row;
}

function publicTransferStage(stage) {
  if (stage === TRANSFER_STAGE.REQUEST) return 'REQUESTED';
  if (stage === TRANSFER_STAGE.SENT) return 'IN_TRANSIT';
  if (stage === TRANSFER_STAGE.RECEIVED) return 'RECEIVED';
  return stage;
}

module.exports = {
  validateInventoryItem,
  validateStockLocation,
  validateStockMove,
  validateRecipe,
  validatePackagingProfile,
  validateTransactionDoc,
  validateTransfer,
  validateWasteDocument,
  validateInventoryCount,
  publicTransferStage,
  SCHEMA_DOCS: {
    InventoryItem: 'RAW|PREP, UoM chain, branchLevels, avgCost (5dp)',
    StockLocation: Object.keys(LOCATION_KIND),
    StockMove: 'immutable ledger row',
    Recipe: 'menu/modifier/prep + applicableOrderTypes',
    Purchase: 'DRAFT|CLOSED',
    Transfer: 'REQUESTED → IN_TRANSIT → RECEIVED',
    Production: 'DRAFT|CLOSED prep output; lines[]: prepItemId + outputQty',
    Waste: 'raw + menu explosion',
    InventoryCount: 'blindCount optional',
  },
};