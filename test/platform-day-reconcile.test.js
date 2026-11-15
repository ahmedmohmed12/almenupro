'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  applyPlatformDayPurge,
  diffPlatformOrderIds,
} = require('../lib/platformDayReconcile');
const {
  reconcileTodayOrderIds,
} = require('../desktop/src/services/talabat-ingestion-service');

const now = new Date('2026-10-09T12:00:00+03:00');
const today = '2026-10-09T10:00:00+03:00';
const yesterday = '2026-10-08T10:00:00+03:00';

test('live and local order ids split into missing and extra', () => {
  const result = reconcileTodayOrderIds(['A', 'B'], ['B', 'C']);
  assert.deepEqual(diffPlatformOrderIds(['A', 'B'], ['B', 'C']), result);
  assert.deepEqual(result.missing, ['A']);
  assert.deepEqual(result.extra, ['C']);
});

test('today purge drops extras and duplicate copies and keeps other days', () => {
  const orders = [
    {
      id: '1',
      restaurantId: 'r1',
      orderSource: 'keeta',
      externalOrderId: 'LIVE',
      createdAt: today,
    },
    {
      id: '2',
      restaurantId: 'r1',
      orderSource: 'keta',
      externalOrderId: 'LIVE',
      createdAt: today,
    },
    {
      id: '3',
      restaurantId: 'r1',
      orderSource: 'keeta',
      externalOrderId: 'GHOST',
      createdAt: today,
    },
    {
      id: '4',
      restaurantId: 'r1',
      orderSource: 'keeta',
      externalOrderId: 'OLD',
      createdAt: yesterday,
    },
    {
      id: '5',
      restaurantId: 'r1',
      orderSource: 'talabat',
      externalOrderId: 'T1',
      createdAt: today,
    },
    {
      id: '6',
      restaurantId: 'r2',
      orderSource: 'keeta',
      externalOrderId: 'GHOST',
      createdAt: today,
    },
  ];
  const result = applyPlatformDayPurge(orders, {
    restaurantId: 'r1',
    platform: 'keeta',
    liveOrderIds: ['LIVE'],
    now,
  });
  assert.equal(result.purged, 2);
  assert.deepEqual(
    result.orders.map((order) => order.id),
    ['1', '4', '5', '6'],
  );
});
