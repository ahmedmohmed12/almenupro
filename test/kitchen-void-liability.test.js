'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  enforceKitchenItemMutation,
  detectKitchenLockViolations,
} = require('../lib/kitchenDispatchLock');
const {
  buildLiabilitiesFromLock,
  summarizeKitchenVoidLiabilities,
  mergeLiabilityIntoShiftSummary,
  APPROVAL_STATUSES,
} = require('../lib/kitchenVoidLiabilities');

const previousItems = [
  {
    id: 'line_1',
    name: 'Kebab',
    quantity: 3,
    unitPrice: 2.5,
    isSentToKitchen: true,
    sentToKitchenAt: new Date(Date.now() - 12 * 60000).toISOString(),
  },
];
const nextItems = [
  {
    id: 'line_1',
    name: 'Kebab',
    quantity: 1,
    unitPrice: 2.5,
    isSentToKitchen: true,
    sentToKitchenAt: previousItems[0].sentToKitchenAt,
  },
];

test('detectKitchenLockViolations matches lines without stable ids', () => {
  const violations = detectKitchenLockViolations(
    [
      {
        name: 'Kebab',
        menuItemId: '10',
        quantity: 2,
        unitPrice: 2.5,
        isSentToKitchen: true,
      },
    ],
    [
      {
        name: 'Kebab',
        menuItemId: '10',
        quantity: 1,
        unitPrice: 2.5,
        isSentToKitchen: true,
      },
    ],
  );
  assert.equal(violations.length, 1);
  assert.equal(violations[0].type, 'reduce');
  assert.equal(violations[0].quantityBefore, 2);
  assert.equal(violations[0].quantityAfter, 1);
});

test('checkout without kitchen line changes needs no authorization', async () => {
  const items = [
    {
      id: 'line_keep',
      name: 'Juice',
      menuItemId: 'm_juice',
      quantity: 2,
      unitPrice: 1.25,
      isSentToKitchen: true,
      sentToKitchenAt: new Date().toISOString(),
    },
  ];
  const lock = await enforceKitchenItemMutation({
    previousItems: items,
    nextItems: items.map((line) => ({ ...line })),
    body: { cashierId: 'cashier_1' },
    auth: { role: 'cashier' },
    restaurantId: 'rest_1',
    deps: {
      readSettings: async () => ({}),
      readStaffUsers: async () => [],
      filterByRestaurant: (rows) => rows,
      readRestaurants: async () => [],
    },
    context: { entityType: 'order', entityId: 'order_settle' },
  });
  assert.equal(lock.ok, true);
  assert.equal(lock.violations.length, 0);
  assert.equal(lock.conditionalVoid, undefined);
});

test('cashier conditional void allows mutation with reason only', async () => {
  const lock = await enforceKitchenItemMutation({
    previousItems,
    nextItems,
    body: {
      kitchenVoidReason: 'customer_request',
      cashierId: 'cashier_1',
      cashierName: 'Ahmed',
    },
    auth: { role: 'cashier' },
    restaurantId: 'rest_1',
    deps: {
      readSettings: async () => ({}),
      readStaffUsers: async () => [],
      filterByRestaurant: (rows) => rows,
      readRestaurants: async () => [],
    },
    context: { entityType: 'order', entityId: 'order_1' },
  });
  assert.equal(lock.ok, true);
  assert.equal(lock.conditionalVoid, true);
});

test('pending liability amount uses removed quantity', () => {
  const records = buildLiabilitiesFromLock({
    violations: [
      {
        type: 'reduce',
        itemId: 'line_1',
        menuItemId: 'm1',
        name: 'Kebab',
        quantityBefore: 3,
        quantityAfter: 1,
        unitPrice: 2.5,
      },
    ],
    previousItems,
    restaurantId: 'rest_1',
    shiftId: 'shift_1',
    orderId: 'order_1',
    entityType: 'order',
    entityId: 'order_1',
    cashierId: 'cashier_1',
    cashierName: 'Ahmed',
    reason: 'customer_request',
    approvalStatus: APPROVAL_STATUSES.PENDING,
  });
  assert.equal(records.length, 1);
  assert.equal(records[0].quantityRemoved, 2);
  assert.equal(records[0].amount, 5);
  assert.equal(records[0].approvalStatus, 'PENDING');
  assert.ok(records[0].elapsedMinutes >= 10);
});

test('shift settlement: approved waived vs rejected debt', () => {
  const rows = [
    { shiftId: 's1', cashierId: 'c1', amount: 4, approvalStatus: 'APPROVED' },
    { shiftId: 's1', cashierId: 'c1', amount: 6, approvalStatus: 'REJECTED' },
    { shiftId: 's1', cashierId: 'c1', amount: 3, approvalStatus: 'PENDING' },
  ];
  const summary = summarizeKitchenVoidLiabilities(rows, { shiftId: 's1' });
  assert.equal(summary.approvedAmount, 4);
  assert.equal(summary.rejectedAmount, 6);
  assert.equal(summary.cashierVoidDebt, 6);
  assert.equal(summary.pendingAmount, 3);
  const merged = mergeLiabilityIntoShiftSummary({ expectedCash: 100 }, summary);
  assert.equal(merged.cashierVoidDebt, 6);
  assert.equal(merged.approvedKitchenVoidAmount, 4);
});