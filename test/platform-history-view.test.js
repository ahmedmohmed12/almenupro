'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  backfillPlatformCustomers,
  listPlatformHistory,
  todayPlatformReport,
} = require('../lib/platformHistoryView');

const restaurantId = 'rest_beit';
const today = new Date();

test('history lists every saved platform order with stored totals', () => {
  const rows = listPlatformHistory(
    [
      {
        id: 'old',
        restaurantId,
        orderSource: 'talabat',
        externalOrderId: 'TB-OLD',
        invoiceNumber: 'TB-OLD',
        createdAt: '2024-01-02T10:00:00.000Z',
        phone: '96550001111',
        customerName: '***',
        items: [{ name: 'مجبوس', quantity: 2 }],
        totalPrice: 7.5,
        paymentMethod: 'Cash',
      },
      {
        id: 'hall',
        restaurantId,
        orderSource: 'pos',
        createdAt: today.toISOString(),
        totalPrice: 99,
      },
      {
        id: 'new',
        restaurantId,
        orderSource: 'keeta',
        externalOrderId: 'K-1',
        createdAt: today.toISOString(),
        phone: '00****97',
        customerName: '',
        items: [{ name: 'شاورما', quantity: 1 }],
        totalPrice: 3.25,
        paymentMethod: 'Paid',
      },
    ],
    restaurantId,
  );
  assert.equal(rows.length, 2);
  assert.equal(rows[1].orderNumber, 'TB-OLD');
  assert.equal(rows[1].customerName, 'عميل منصات');
  assert.equal(rows[1].items, '2× مجبوس');
  assert.equal(rows[1].total, 7.5);
  assert.equal(rows[1].phone, '96550001111');
  assert.equal(rows[0].paymentStatus, 'Prepaid');
});

test('today report sums stored amounts into cash and prepaid', () => {
  const report = todayPlatformReport(
    [
      {
        id: 'a',
        restaurantId,
        orderSource: 'jahez',
        createdAt: today.toISOString(),
        totalPrice: 4,
        paymentMethod: 'Cash',
        items: [{ name: 'عصير', quantity: 1 }],
        status: 'confirmed',
      },
      {
        id: 'b',
        restaurantId,
        orderSource: 'talabat',
        createdAt: today.toISOString(),
        totalPrice: 6,
        paymentMethod: 'Prepaid',
        status: 'confirmed',
      },
      {
        id: 'old',
        restaurantId,
        orderSource: 'talabat',
        createdAt: '2020-01-01T00:00:00.000Z',
        totalPrice: 100,
        paymentMethod: 'Cash',
      },
      {
        id: 'cancelled',
        restaurantId,
        orderSource: 'keeta',
        createdAt: today.toISOString(),
        totalPrice: 9,
        paymentMethod: 'Cash',
        status: 'cancelled',
      },
    ],
    restaurantId,
    today,
  );
  assert.equal(report.orderCount, 2);
  assert.equal(report.cancelledCount, 1);
  assert.equal(report.totalSales, 10);
  assert.equal(report.cash.count, 1);
  assert.equal(report.cash.total, 4);
  assert.equal(report.prepaid.count, 1);
  assert.equal(report.prepaid.total, 6);
  assert.equal(report.orders[0].items.includes('عصير') || report.orders.some((row) => row.items.includes('عصير')), true);
});

test('backfill saves one customer per full phone and skips masked numbers', () => {
  const result = backfillPlatformCustomers(
    [],
    [
      {
        id: '1',
        restaurantId,
        orderSource: 'talabat',
        phone: '+965 5012 3456',
        customerName: '',
        address: 'السالمية',
        totalPrice: 4,
        createdAt: '2026-01-01T00:00:00.000Z',
      },
      {
        id: '2',
        restaurantId,
        orderSource: 'keeta',
        phone: '50123456',
        customerName: 'Noura',
        address: 'حولي',
        totalPrice: 5,
        createdAt: '2026-01-02T00:00:00.000Z',
      },
      {
        id: '3',
        restaurantId,
        orderSource: 'keeta',
        phone: '00****97',
        customerName: 'Hidden',
        totalPrice: 2,
      },
    ],
  );
  assert.equal(result.scanned, 3);
  assert.equal(result.saved, 1);
  assert.equal(result.skippedShortPhone, 1);
  assert.equal(result.customers.length, 1);
  assert.equal(result.customers[0].customerName, 'Noura');
  assert.equal(result.customers[0].totalOrders, 2);
  assert.equal(result.customers[0].phone.length >= 8, true);
});
