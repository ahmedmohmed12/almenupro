'use strict';

const {
  DOC_STATUS,
  TRANSFER_STAGE,
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

function createTransferRecord(body, tenantId) {
  return attachTenant(
    {
      id: body.id || newId('trf'),
      status: DOC_STATUS.DRAFT,
      stage: TRANSFER_STAGE.REQUEST,
      fromBranchId: String(body.fromBranchId || body.from_branch_id || tenantId),
      toBranchId: String(body.toBranchId || body.to_branch_id || tenantId),
      notes: String(body.notes || '').trim(),
      lines: (Array.isArray(body.lines) ? body.lines : []).map((line) => ({
        itemId: String(line.itemId),
        qtyInRecipeUom: roundQty(line.qtyInRecipeUom || line.qty || 0),
      })),
      createdAt: new Date().toISOString(),
    },
    tenantId,
  );
}

function findTransfer(blob, tenantId, transferId) {
  const transfers = scopeTenant(blob.transfers, tenantId);
  const idx = transfers.findIndex((t) => String(t.id) === String(transferId));
  return { transfers, idx, record: idx >= 0 ? transfers[idx] : null };
}

async function sendTransfer(dataStore, { tenantId, transferId, createdBy }) {
  return mutateInventory(dataStore, tenantId, async (blob) => {
    const { transfers, idx, record } = findTransfer(blob, tenantId, transferId);
    if (!record) {
      const err = new Error('التحويل غير موجود');
      err.code = 404;
      throw err;
    }
    if (!isDocDraft(record.status)) {
      const err = new Error('التحويل مغلق ولا يمكن إرساله');
      err.code = 409;
      throw err;
    }
    const fromBranch = record.fromBranchId;
    const locations = ensureLocationsInBlob(blob, tenantId, fromBranch);
    const stock = findLocation(locations, {
      kind: LOCATION_KIND.BRANCH_STOCK,
      branchId: fromBranch,
    });
    const inTransit = findLocation(locations, { kind: LOCATION_KIND.IN_TRANSIT });
    if (!stock || !inTransit) {
      const err = new Error('مواقع المخزون غير مهيأة');
      err.code = 500;
      throw err;
    }
    const moves = [];
    for (const line of record.lines) {
      const items = scopeTenant(blob.items, tenantId);
      const item = items.find((row) => String(row.id) === String(line.itemId));
      const move = createStockMoveRecord({
        tenantId,
        branchId: fromBranch,
        fromLocation: stock,
        toLocation: inTransit,
        itemId: line.itemId,
        qtyInRecipeUom: line.qtyInRecipeUom,
        unitCostSnapshot: item?.avgCost || 0,
        referenceType: MOVE_REFERENCE.TRANSFER,
        referenceId: record.id,
        createdBy,
        notes: `transfer_send:${record.toBranchId}`,
      });
      moves.push(move);
      blob.items = postMoveOnBranchStock({ items: blob.items, move });
    }
    transfers[idx] = {
      ...record,
      stage: TRANSFER_STAGE.SENT,
      sentAt: new Date().toISOString(),
      sentBy: createdBy,
    };
    blob.moves = [...(blob.moves || []), ...moves];
    blob.transfers = [
      ...blob.transfers.filter(
        (t) => String(t.tenantId || t.restaurantId) !== String(tenantId),
      ),
      ...transfers,
    ];
    return { blob, result: transfers[idx] };
  });
}

async function receiveTransfer(dataStore, { tenantId, transferId, createdBy }) {
  return mutateInventory(dataStore, tenantId, async (blob) => {
    const { transfers, idx, record } = findTransfer(blob, tenantId, transferId);
    if (!record) {
      const err = new Error('التحويل غير موجود');
      err.code = 404;
      throw err;
    }
    if (record.stage !== TRANSFER_STAGE.SENT) {
      const err = new Error('يجب إرسال التحويل قبل الاستلام');
      err.code = 409;
      throw err;
    }
    const toBranch = record.toBranchId;
    const locations = ensureLocationsInBlob(blob, tenantId, toBranch);
    const stock = findLocation(locations, {
      kind: LOCATION_KIND.BRANCH_STOCK,
      branchId: toBranch,
    });
    const inTransit = findLocation(locations, { kind: LOCATION_KIND.IN_TRANSIT });
    const moves = [];
    for (const line of record.lines) {
      const items = scopeTenant(blob.items, tenantId);
      const item = items.find((row) => String(row.id) === String(line.itemId));
      const move = createStockMoveRecord({
        tenantId,
        branchId: toBranch,
        fromLocation: inTransit,
        toLocation: stock,
        itemId: line.itemId,
        qtyInRecipeUom: line.qtyInRecipeUom,
        unitCostSnapshot: item?.avgCost || 0,
        referenceType: MOVE_REFERENCE.TRANSFER,
        referenceId: record.id,
        createdBy,
        notes: `transfer_receive:from=${record.fromBranchId}`,
      });
      moves.push(move);
      blob.items = postMoveOnBranchStock({ items: blob.items, move });
    }
    transfers[idx] = {
      ...record,
      stage: TRANSFER_STAGE.RECEIVED,
      status: DOC_STATUS.CLOSED,
      receivedAt: new Date().toISOString(),
      receivedBy: createdBy,
      closedAt: new Date().toISOString(),
    };
    blob.moves = [...(blob.moves || []), ...moves];
    blob.transfers = [
      ...blob.transfers.filter(
        (t) => String(t.tenantId || t.restaurantId) !== String(tenantId),
      ),
      ...transfers,
    ];
    return { blob, result: transfers[idx] };
  });
}

module.exports = {
  createTransferRecord,
  sendTransfer,
  receiveTransfer,
};