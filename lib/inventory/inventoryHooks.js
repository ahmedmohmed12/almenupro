'use strict';

const { isDeliveredStatus } = require('../loyaltyCashback');
const { scheduleOrderDeduction } = require('./orderDeductionWorker');

function maybeQueueInventoryDeduction(dataStore, { previous, next, auth }) {
  if (!next || !dataStore) return;
  const wasDelivered = previous ? isDeliveredStatus(previous.status) : false;
  const nowDelivered = isDeliveredStatus(next.status);
  if (!nowDelivered || (previous && wasDelivered)) return;

  const tenantId = String(next.restaurant_id || next.restaurantId || '');
  if (!tenantId) return;
  const branchId = String(next.branchId || next.branch_id || tenantId);
  const orderId = String(next.id);
  const createdBy = auth?.staffId || auth?.role || 'system';

  scheduleOrderDeduction(dataStore, {
    tenantId,
    branchId,
    orderId,
    order: next,
    createdBy,
  });
}

module.exports = {
  maybeQueueInventoryDeduction,
};