'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  summarizeShiftPendingOrders,
  enforceShiftClosePendingGuard,
} = require('../lib/shiftPendingOrders');

const shift = { id: 'shift_a', restaurantId: 'r1' };

test('shift close allowed when no pending orders', async () => {
  const orders = [
    {
      id: 'o1',
      shiftId: 'shift_a',
      orderType: 'pickup',
      status: 'delivered',
      paymentStatus: 'paid',
      createdFromPos: true,
      orderSource: 'pos',
    },
  ];
  const summary = summarizeShiftPendingOrders(orders, shift.id);
  assert.equal(summary.total, 0);
  const guard = await enforceShiftClosePendingGuard({
    shift,
    orders,
    body: {},
    auth: { role: 'cashier' },
    staffUsers: [],
    roles: [],
    restaurantRecord: null,
    isCashier: () => true,
    isRestaurantAdmin: () => false,
  });
  assert.equal(guard.ok, true);
  assert.equal(guard.cleared, true);
});

test('cashier blocked without manager pin when pickup pending', async () => {
  const orders = [
    {
      id: 'held',
      shiftId: 'shift_a',
      orderType: 'pickup',
      status: 'preparing',
      paymentStatus: 'pending_payment',
      createdFromPos: true,
      orderSource: 'pos',
    },
  ];
  const summary = summarizeShiftPendingOrders(orders, shift.id);
  assert.equal(summary.total, 1);
  assert.equal(summary.pickup, 1);
  const guard = await enforceShiftClosePendingGuard({
    shift,
    orders,
    body: { roleId: 'cashier' },
    auth: { role: 'cashier' },
    staffUsers: [],
    roles: [],
    restaurantRecord: null,
    isCashier: () => true,
    isRestaurantAdmin: () => false,
  });
  assert.equal(guard.ok, false);
  assert.equal(guard.code, 'PENDING_ORDERS_APPROVAL_REQUIRED');
});

test('supervisor can close pending with reason only', async () => {
  const orders = [
    {
      id: 'table',
      shiftId: 'shift_a',
      orderType: 'dineIn',
      status: 'preparing',
      paymentStatus: 'pending_payment',
      createdFromPos: true,
      orderSource: 'pos-dine-in',
    },
  ];
  const guard = await enforceShiftClosePendingGuard({
    shift,
    orders,
    body: {
      roleId: 'shift_supervisor',
      pendingCloseReason: 'End of day — settle tables tomorrow',
    },
    auth: { role: 'cashier', staffRoleId: 'shift_supervisor' },
    staffUsers: [],
    roles: [],
    restaurantRecord: null,
    isCashier: () => true,
    isRestaurantAdmin: () => false,
  });
  assert.equal(guard.ok, true);
  assert.equal(guard.bypassRole, true);
});