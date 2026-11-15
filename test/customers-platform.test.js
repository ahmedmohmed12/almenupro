'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  customerNameFromPlatform,
  migrateCustomersFromOrders,
  phonesMatch,
  upsertCustomerFromSource,
} = require('../lib/customersStore');

const restaurantId = 'rest_beit';

test('missing platform name is stored as the platform customer label', () => {
  const customers = upsertCustomerFromSource(
    [],
    {
      id: 'order_1',
      customerName: '***',
      phone: '+965 5012 3456',
      address: 'السالمية، شارع 1',
      totalPrice: 4.5,
    },
    restaurantId,
  );
  assert.equal(customers.length, 1);
  assert.equal(customers[0].customerName, 'عميل منصات');
  assert.equal(customers[0].origin, 'almenupro');
  assert.equal(customers[0].address, 'السالمية، شارع 1');
  assert.equal(customers[0].phone, '96550123456');
  assert.deepEqual(customers[0].orderIds, ['order_1']);
  assert.equal(customers[0].totalOrders, 1);
});

test('the next order with the same phone keeps one customer and both invoices', () => {
  let customers = upsertCustomerFromSource(
    [],
    {
      id: 'order_1',
      customerName: '',
      phone: '96550123456',
      address: 'حولي',
      createdAt: '2026-10-09T07:00:00.000Z',
    },
    restaurantId,
  );
  customers = upsertCustomerFromSource(
    customers,
    {
      id: 'order_2',
      customerName: 'unknown',
      phone: '+96550123456',
      address: 'الجابرية، قطعة 2',
      orderSource: 'keeta',
      invoiceNumber: 'K-22',
      totalPrice: 6.5,
      createdAt: '2026-10-09T08:00:00.000Z',
    },
    restaurantId,
  );
  assert.equal(customers.length, 1);
  assert.equal(customers[0].customerName, 'عميل منصات');
  assert.equal(customers[0].totalOrders, 2);
  assert.equal(customers[0].address, 'الجابرية، قطعة 2');
  assert.deepEqual(
    customers[0].addresses.map((row) => row.address),
    ['الجابرية، قطعة 2', 'حولي'],
  );
  assert.equal(customers[0].invoices.length, 2);
  assert.equal(phonesMatch(customers[0].phone, '+965 5012 3456'), true);
  const again = upsertCustomerFromSource(
    customers,
    {
      id: 'order_2',
      customerName: '***',
      phone: '50123456',
      address: 'الجابرية، قطعة 2',
      orderSource: 'keeta',
      invoiceNumber: 'K-22',
      totalPrice: 6.5,
      createdAt: '2026-10-09T08:00:00.000Z',
    },
    restaurantId,
  );
  assert.equal(again, customers);
});

test('a saved name stays when a later pull hides it', () => {
  let customers = upsertCustomerFromSource(
    [],
    {
      id: 'order_1',
      customerName: 'Noura',
      phone: '96550000001',
      address: 'الفنطاس',
    },
    restaurantId,
  );
  customers = upsertCustomerFromSource(
    customers,
    {
      id: 'order_1',
      customerName: '***',
      phone: '96550000001',
      address: 'الفنطاس',
    },
    restaurantId,
  );
  assert.equal(customers[0].customerName, 'Noura');
  let named = upsertCustomerFromSource(
    [],
    { id: 'order_9', customerName: '', phone: '96550000002', address: '' },
    restaurantId,
  );
  named = upsertCustomerFromSource(
    named,
    {
      id: 'order_10',
      customerName: 'Ali',
      phone: '96550000002',
      address: 'العارضية',
    },
    restaurantId,
  );
  assert.equal(named[0].customerName, 'Ali');
  assert.equal(named[0].totalOrders, 2);
});

test('historical platform orders collapse onto one customer by phone', () => {
  const customers = migrateCustomersFromOrders([], [
    {
      id: 'a',
      restaurantId,
      customerName: 'customer',
      phone: '96551112233',
      address: 'عنوان أول',
      createdAt: '2026-10-08T10:00:00.000Z',
    },
    {
      id: 'b',
      restaurantId,
      customerName: '',
      phone: '+965 5111 2233',
      address: 'عنوان ثاني',
      createdAt: '2026-10-08T12:00:00.000Z',
    },
  ]);
  assert.equal(customers.length, 1);
  assert.equal(customers[0].customerName, 'عميل منصات');
  assert.equal(customers[0].address, 'عنوان ثاني');
  assert.equal(customers[0].totalOrders, 2);
  assert.equal(customerNameFromPlatform('n/a'), 'عميل منصات');
});
