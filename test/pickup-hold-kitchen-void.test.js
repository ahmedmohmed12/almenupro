'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { recordKitchenVoidLiabilities } = require('../lib/posKitchenVoidRecord');
const { enforceKitchenItemMutation } = require('../lib/kitchenDispatchLock');

const previousItems = [
  {
    id: 'line_pickup_1',
    name: 'Shawarma',
    menuItemId: '22',
    quantity: 2,
    unitPrice: 1.5,
    isSentToKitchen: true,
    sentToKitchenAt: new Date().toISOString(),
  },
];

const nextItems = [
  {
    id: 'line_pickup_1',
    name: 'Shawarma',
    menuItemId: '22',
    quantity: 1,
    unitPrice: 1.5,
    isSentToKitchen: true,
    sentToKitchenAt: previousItems[0].sentToKitchenAt,
  },
];

test('pickup-hold style mutation records pending kitchen void liability', async () => {
  const saved = [];
  const lock = await enforceKitchenItemMutation({
    previousItems,
    nextItems,
    body: {
      kitchenVoidReason: 'customer_request',
      cashierId: 'cashier_pickup',
      cashierName: 'Pickup Cashier',
      shiftId: 'shift_pickup',
    },
    auth: { role: 'cashier', staffId: 'cashier_pickup' },
    restaurantId: 'rest_pickup',
    deps: {
      readSettings: async () => ({}),
      readStaffUsers: async () => [],
      filterByRestaurant: (rows) => rows,
      readRestaurants: async () => [],
    },
    context: { entityType: 'order', entityId: 'ord_pickup_1', orderType: 'pickup' },
  });
  assert.equal(lock.ok, true);

  const records = await recordKitchenVoidLiabilities(
    {
      readKitchenVoidLiabilities: async () => saved,
      writeKitchenVoidLiabilities: async (rows) => {
        saved.splice(0, saved.length, ...rows);
      },
    },
    {
      lock,
      previousItems,
      restaurantId: 'rest_pickup',
      body: {
        kitchenVoidReason: 'customer_request',
        shiftId: 'shift_pickup',
        cashierId: 'cashier_pickup',
        cashierName: 'Pickup Cashier',
      },
      auth: { role: 'cashier', staffId: 'cashier_pickup' },
      context: {
        entityType: 'order',
        entityId: 'ord_pickup_1',
        orderId: 'ord_pickup_1',
        shiftId: 'shift_pickup',
      },
    },
  );

  assert.equal(records.length, 1);
  assert.equal(records[0].shiftId, 'shift_pickup');
  assert.equal(records[0].cashierId, 'cashier_pickup');
  assert.equal(records[0].approvalStatus, 'PENDING');
  assert.equal(saved.length, 1);
});