'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  createApprovalRequestRecord,
  validateApprovedForUse,
  resolveRemoteApproval,
  APPROVAL_TYPES,
  APPROVAL_STATUSES,
} = require('../lib/posApprovalRequests');
const { enforceShiftClosePendingGuard } = require('../lib/shiftPendingOrders');
const { enforceKitchenItemMutation } = require('../lib/kitchenDispatchLock');

const shift = { id: 'shift_1', restaurantId: 'rest_1' };

test('approved shift close request bypasses manager pin', async () => {
  const memory = [];
  const request = createApprovalRequestRecord({
    id: 'apr_1',
    restaurantId: 'rest_1',
    restaurantSlug: 'demo',
    shiftId: 'shift_1',
    type: APPROVAL_TYPES.CLOSE_SHIFT_PENDING_ORDERS,
    requestedById: 'cashier_1',
    requestedByName: 'Cashier',
    reason: 'Emergency close',
    payload: { shiftId: 'shift_1', total: 1 },
  });
  memory.push({
    ...request,
    status: APPROVAL_STATUSES.APPROVED,
    reviewedById: 'mgr_1',
    reviewedByName: 'Manager',
    reviewedAt: new Date().toISOString(),
  });

  const orders = [
    {
      id: 'held',
      shiftId: 'shift_1',
      orderType: 'pickup',
      status: 'preparing',
      paymentStatus: 'pending_payment',
      createdFromPos: true,
      orderSource: 'pos',
    },
  ];

  const guard = await enforceShiftClosePendingGuard({
    shift,
    orders,
    body: {
      roleId: 'cashier',
      pendingCloseReason: 'Emergency close',
      approvalRequestId: 'apr_1',
    },
    auth: { role: 'cashier' },
    staffUsers: [],
    roles: [],
    restaurantRecord: null,
    isCashier: () => true,
    isRestaurantAdmin: () => false,
    deps: {
      resolveRemoteApproval: (opts) =>
        resolveRemoteApproval({
          ...opts,
          readApprovalRequests: async () => memory,
          writeApprovalRequests: async (rows) => {
            const snapshot = [...rows];
            memory.length = 0;
            memory.push(...snapshot);
          },
        }),
    },
  });

  assert.equal(guard.ok, true);
  assert.equal(guard.remoteApprovalId, 'apr_1');
  assert.equal(memory[0].consumedAt != null, true);
});

test('kitchen mutation accepts approved void request', async () => {
  const memory = [];
  const request = createApprovalRequestRecord({
    id: 'apr_void',
    restaurantId: 'rest_1',
    restaurantSlug: 'demo',
    shiftId: 'shift_1',
    type: APPROVAL_TYPES.VOID_SENT_ITEM,
    requestedById: 'cashier_1',
    requestedByName: 'Cashier',
    reason: 'Wrong item',
    payload: {
      orderId: 'order_1',
      cartItemId: 'line_1',
      itemName: 'Burger',
    },
  });
  memory.push({
    ...request,
    status: APPROVAL_STATUSES.APPROVED,
    reviewedById: 'sup_1',
    reviewedByName: 'Supervisor',
    reviewedAt: new Date().toISOString(),
  });

  const previousItems = [
    {
      id: 'line_1',
      name: 'Burger',
      quantity: 2,
      isSentToKitchen: true,
      sentToKitchenAt: '2025-01-01T00:00:00.000Z',
    },
  ];
  const nextItems = [
    {
      id: 'line_1',
      name: 'Burger',
      quantity: 1,
      isSentToKitchen: true,
      sentToKitchenAt: '2025-01-01T00:00:00.000Z',
    },
  ];

  const lock = await enforceKitchenItemMutation({
    previousItems,
    nextItems,
    body: {
      approvalRequestId: 'apr_void',
      cartItemId: 'line_1',
      kitchenVoidReason: 'Wrong item',
    },
    auth: { role: 'cashier' },
    restaurantId: 'rest_1',
    deps: {
      readSettings: async () => ({}),
      readStaffUsers: async () => [],
      filterByRestaurant: (rows) => rows,
      readRestaurants: async () => [],
      resolveRemoteApproval: (opts) =>
        resolveRemoteApproval({
          ...opts,
          readApprovalRequests: async () => memory,
          writeApprovalRequests: async (rows) => {
            const snapshot = [...rows];
            memory.length = 0;
            memory.push(...snapshot);
          },
        }),
    },
    context: { entityType: 'order', entityId: 'order_1' },
  });

  assert.equal(lock.ok, true);
  assert.equal(lock.remoteApprovalId, 'apr_void');
});

test('cannot reuse consumed approval', () => {
  const row = {
    id: 'apr_x',
    restaurantId: 'rest_1',
    type: APPROVAL_TYPES.VOID_SENT_ITEM,
    status: APPROVAL_STATUSES.APPROVED,
    consumedAt: new Date().toISOString(),
    payload: { orderId: 'order_1', cartItemId: 'line_1' },
  };
  const validation = validateApprovedForUse(row, {
    restaurantId: 'rest_1',
    type: APPROVAL_TYPES.VOID_SENT_ITEM,
    context: { entityId: 'order_1', cartItemId: 'line_1' },
  });
  assert.equal(validation.ok, false);
  assert.equal(validation.code, 'APPROVAL_ALREADY_USED');
});