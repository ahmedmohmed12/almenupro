'use strict';

const { performerFromBody } = require('./kitchenDispatchLock');
const {
  buildLiabilitiesFromLock,
  appendKitchenVoidLiabilities,
  resolveLiabilityApprovalStatus,
  liabilityAuthorizer,
} = require('./kitchenVoidLiabilities');

async function recordKitchenVoidLiabilities(
  deps,
  {
    lock,
    previousItems,
    restaurantId,
    body,
    context,
    auth,
  },
) {
  if (!lock?.ok || !Array.isArray(lock.violations) || lock.violations.length === 0) {
    return [];
  }

  const staffUsers =
    typeof deps.readStaffUsers === 'function' && typeof deps.filterByRestaurant === 'function'
      ? deps.filterByRestaurant(await deps.readStaffUsers(), restaurantId)
      : [];
  const performer = performerFromBody(body, staffUsers);

  const shiftId = String(
    body.shiftId ||
      body.shift_id ||
      context.shiftId ||
      context.shift_id ||
      '',
  ).trim();
  const cashierId = String(
    body.cashierId ||
      body.cashier_id ||
      performer?.id ||
      body.performedById ||
      body.performed_by_id ||
      auth?.staffId ||
      auth?.staff_id ||
      '',
  ).trim();
  const cashierName = String(
    body.cashierName ||
      body.cashier_name ||
      performer?.name ||
      body.performedByName ||
      body.performed_by_name ||
      'Cashier',
  );

  const approvalStatus = resolveLiabilityApprovalStatus(lock);
  const reviewer = approvalStatus === 'APPROVED' ? liabilityAuthorizer(lock) : null;

  const scopedRestaurantId = String(
    restaurantId ||
      context?.restaurantId ||
      context?.restaurant_id ||
      auth?.restaurantId ||
      auth?.restaurant_id ||
      '',
  ).trim();
  if (!scopedRestaurantId) {
    return [];
  }

  const records = buildLiabilitiesFromLock({
    violations: lock.violations,
    previousItems,
    restaurantId: scopedRestaurantId,
    shiftId,
    orderId: context.orderId || context.entityId,
    entityType: context.entityType || 'order',
    entityId: context.entityId || context.orderId,
    cashierId,
    cashierName,
    reason: lock.reason || body.kitchenVoidReason || body.reason,
    approvalStatus,
    reviewedBy: reviewer,
  });

  await appendKitchenVoidLiabilities(deps, records);
  return records;
}

module.exports = {
  recordKitchenVoidLiabilities,
};