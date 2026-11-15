'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildDailySalesCsv,
  buildDailySalesPrintHtml,
  computeDailySalesAnalytics,
} = require('../lib/platformSalesAnalytics');
const { kuwaitDateKey } = require('../lib/kuwaitBusinessDay');

test('daily sales uses the Kuwait calendar day and excludes cancelled orders', () => {
  const today = kuwaitDateKey();
  const todayNoon = new Date(`${today}T12:00:00+03:00`);
  const yesterday = new Date(todayNoon.getTime() - 24 * 60 * 60 * 1000);
  const orders = [
    {
      restaurantId: 'rest_test',
      orderSource: 'talabat',
      status: 'confirmed',
      totalPrice: 10,
      createdAt: todayNoon.toISOString(),
    },
    {
      restaurantId: 'rest_test',
      orderSource: 'keeta',
      status: 'cancelled',
      totalPrice: 50,
      createdAt: todayNoon.toISOString(),
    },
    {
      restaurantId: 'rest_test',
      orderSource: 'talabat',
      status: 'confirmed',
      totalPrice: 20,
      createdAt: yesterday.toISOString(),
    },
  ];

  const result = computeDailySalesAnalytics(orders, 'rest_test', { days: 1 });
  assert.equal(result.summary.orders, 1);
  assert.equal(result.summary.grossRevenue, 10);
  assert.equal(result.platforms[0].platform, 'talabat');
});

test('daily sales groups Talabat accounts by store instead of platform', () => {
  const today = kuwaitDateKey();
  const noon = new Date(`${today}T12:00:00+03:00`).toISOString();
  const orders = [
    {
      restaurantId: 'rest_test',
      orderSource: 'talabat',
      store_id: 'store_talabat_4',
      store_name: 'دار السعد',
      status: 'confirmed',
      totalPrice: 9,
      externalOrderId: '3949000001',
      createdAt: noon,
    },
    {
      restaurantId: 'rest_test',
      orderSource: 'talabat',
      store_id: 'store_talabat_4',
      store_name: 'دار السعد',
      status: 'confirmed',
      totalPrice: 6,
      externalOrderId: '3949000002',
      createdAt: noon,
    },
    {
      restaurantId: 'rest_test',
      orderSource: 'talabat',
      store_id: 'store_talabat_main',
      store_name: 'بيت وضحى',
      status: 'confirmed',
      totalPrice: 12,
      externalOrderId: '3949000003',
      createdAt: noon,
    },
  ];

  const result = computeDailySalesAnalytics(orders, 'rest_test', { days: 1 });
  assert.equal(result.platforms.length, 1);
  assert.equal(result.stores.length, 2);
  const darAlSaad = result.stores.find((row) => row.storeId === 'store_talabat_4');
  assert.equal(darAlSaad.storeName, 'طلبات - دار السعد');
  assert.equal(darAlSaad.orders, 2);
  assert.equal(darAlSaad.grossRevenue, 15);
  assert.equal(darAlSaad.averageOrderValue, 7.5);

  const filtered = computeDailySalesAnalytics(orders, 'rest_test', {
    days: 1,
    storeId: 'store_talabat_4',
  });
  assert.equal(filtered.summary.orders, 2);
  assert.equal(filtered.summary.grossRevenue, 15);
  assert.equal(filtered.stores.length, 2);
  assert.equal(filtered.transactions.length, 2);
  assert.equal(filtered.transactions.every((row) => row.storeName === 'طلبات - دار السعد'), true);

  const csv = buildDailySalesCsv(filtered);
  assert.match(csv, /طلبات - دار السعد/);
  assert.match(csv, /3949000001/);
  assert.match(csv, /store_talabat_main/);
  const html = buildDailySalesPrintHtml(filtered);
  assert.match(html, /طلبات - دار السعد/);
  assert.match(html, /3949000002/);
});
