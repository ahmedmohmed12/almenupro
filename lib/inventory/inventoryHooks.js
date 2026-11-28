'use strict';

const { isDeliveredStatus } = require('../loyaltyCashback');
const { scheduleOrderDeduction } = require('./orderDeductionWorker');
const { inventoryEnabledForTenant } = require('./inventoryAccess');

async function maybeQueueInventoryDeduction(
  dataStore,
  { previous, next, auth, readRestaurants },
) {
  if (!next || !dataStore) return;
  const wasDelivered = previous ? isDeliveredStatus(previous.status) : false;
  const nowDelivered = isDeliveredStatus(next.status);
  if (!nowDelivered || (previous && wasDelivered)) return;

  const tenantId = String(next.restaurant_id || next.restaurantId || '');
  if (!tenantId) return;

  const read =
    readRestaurants || (() => (dataStore.readRestaurants ? dataStore.readRestaurants() : []));
  const enabled = await inventoryEnabledForTenant(read, tenantId);
  if (!enabled) return;

  const branchId = String(next.branchId || next.branch_id || tenantId);
  const orderId = String(next.id);
  const createdBy = auth?.staffId || auth?.role || 'system';

  scheduleOrderDeduction(dataStore, {
    tenantId,
    branchId,
    orderId,
    order: next,
    createdBy,
    readRestaurants: read,
  });
}

module.exports = {
  maybeQueueInventoryDeduction,
};