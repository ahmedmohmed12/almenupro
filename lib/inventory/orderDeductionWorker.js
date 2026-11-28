'use strict';

const { LOCATION_KIND, MOVE_REFERENCE, JOB_STATUS, newId } = require('./constants');
const {
  mutateInventory,
  ensureLocationsInBlob,
  findLocation,
  scopeTenant,
  attachTenant,
} = require('./inventoryRepository');
const { createStockMoveRecord, postMoveOnBranchStock } = require('./stockLedger');
const { flattenOrderRequirements } = require('./recipeEngine');
const { inventoryEnabledForTenant } = require('./inventoryAccess');

const pendingTimers = new Map();

function scheduleOrderDeduction(
  dataStore,
  { tenantId, branchId, orderId, order, createdBy, readRestaurants },
) {
  const jobId = newId('job');
  const key = `${tenantId}:${orderId}`;
  if (pendingTimers.has(key)) {
    clearTimeout(pendingTimers.get(key));
  }
  const timer = setTimeout(() => {
    pendingTimers.delete(key);
    deductOrder(dataStore, {
      tenantId,
      branchId,
      orderId,
      order,
      createdBy,
      jobId,
      readRestaurants,
    }).catch(
      (error) => {
        console.error('[inventory] order deduction failed:', orderId, error?.message || error);
      },
    );
  }, 0);
  pendingTimers.set(key, timer);
  return jobId;
}

async function deductOrder(
  dataStore,
  { tenantId, branchId, orderId, order, createdBy, jobId, readRestaurants },
) {
  const read =
    readRestaurants || (() => (dataStore.readRestaurants ? dataStore.readRestaurants() : []));
  if (!(await inventoryEnabledForTenant(read, tenantId))) {
    return { skipped: true, reason: 'INVENTORY_DISABLED' };
  }
  const dedupeKey = `pos:${orderId}`;
  return mutateInventory(dataStore, tenantId, async (blob) => {
    const already = (blob.moves || []).some(
      (m) =>
        m.referenceType === MOVE_REFERENCE.POS_ORDER &&
        String(m.referenceId) === String(orderId) &&
        !m.reversalOfMoveId,
    );
    if (already) {
      return { blob, result: { skipped: true, reason: 'ALREADY_DEDUCTED' } };
    }

    const items = scopeTenant(blob.items, tenantId);
    const itemsById = new Map(items.map((row) => [String(row.id), row]));
    const { channel, requirements } = flattenOrderRequirements({
      order,
      recipes: blob.recipes,
      packagingProfiles: blob.packagingProfiles,
      itemsById,
      tenantId,
    });
    if (!requirements.length) {
      return { blob, result: { skipped: true, reason: 'NO_RECIPE_LINES' } };
    }

    const locations = ensureLocationsInBlob(blob, tenantId, branchId);
    const stock = findLocation(locations, {
      kind: LOCATION_KIND.BRANCH_STOCK,
      branchId,
    });
    const customer = findLocation(locations, { kind: LOCATION_KIND.CUSTOMER });
    if (!stock || !customer) {
      const err = new Error('مواقع المخزون غير مهيأة');
      err.code = 500;
      throw err;
    }

    const moves = [];
    let workingItems = [...blob.items];

    for (const need of requirements) {
      const item = itemsById.get(String(need.itemId));
      if (!item) continue;
      const move = createStockMoveRecord({
        tenantId,
        branchId,
        fromLocation: stock,
        toLocation: customer,
        itemId: need.itemId,
        qtyInRecipeUom: need.qtyInRecipeUom,
        unitCostSnapshot: item.avgCost || 0,
        referenceType: MOVE_REFERENCE.POS_ORDER,
        referenceId: orderId,
        negativeStockFlag: true,
        createdBy,
        notes: `channel=${channel};dedupe=${dedupeKey}`,
      });
      moves.push(move);
      workingItems = postMoveOnBranchStock({ items: workingItems, move });
    }

    blob.moves = [...(blob.moves || []), ...moves];
    blob.items = workingItems;
    blob.jobs = [
      ...(blob.jobs || []),
      attachTenant(
        {
          id: jobId || newId('job'),
          type: 'ORDER_DEDUCTION',
          status: JOB_STATUS.DONE,
          orderId,
          channel,
          moveIds: moves.map((m) => m.id),
          createdAt: new Date().toISOString(),
        },
        tenantId,
      ),
    ];

    return {
      blob,
      result: { moves, channel, requirements },
    };
  }).then((out) => out.result || out);
}

module.exports = {
  scheduleOrderDeduction,
  deductOrder,
};