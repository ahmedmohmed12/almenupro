'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  dedupeKey,
  validateOrderPayload,
} = require('../src/services/payload-validator');

test('validator sanitizes and bounds scraper payloads', () => {
  const order = validateOrderPayload(
    {
      platform: 'keta',
      externalOrderId: ' K-100 ',
      customerName: '  Noor   A. ',
      items: [
        {
          name: ' Meal ',
          quantity: 5000,
          unitPrice: 2.34567,
          lineTotal: 2.34567,
          options: [{ name: ' Sauce ', price: 0.1 }],
        },
      ],
      totalAmount: 2.34567,
      createdAt: 'not-a-date',
      store_name: '  طلبات دار السعد  ',
    },
    'keeta',
  );

  assert.equal(order.platform, 'keeta');
  assert.equal(order.externalOrderId, 'K-100');
  assert.equal(order.invoiceNumber, 'K-100');
  assert.equal(order.customerName, 'Noor A.');
  assert.equal(order.store_name, 'طلبات دار السعد');
  assert.equal(order.items[0].quantity, 999);
  assert.equal(order.totalAmount, 2.346);
  assert.match(order.createdAt, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(dedupeKey('rest-1', order), 'rest-1\u0000keeta\u0000K-100');
});

test('validator treats customer, phone, address, and prices as optional', () => {
  const order = validateOrderPayload(
    {
      platform: 'talabat',
      externalOrderId: 'TB-MINIMAL',
      items: [{ name: 'Burger' }],
    },
    'talabat',
  );

  assert.equal(order.customerName, '');
  assert.equal(order.phone, '');
  assert.equal(order.address, '');
  assert.equal(order.items[0].quantity, 1);
  assert.equal(order.items[0].unitPrice, 0);
});

test('validator rejects provider spoofing and empty orders', () => {
  assert.throws(
    () =>
      validateOrderPayload(
        { platform: 'jahez', externalOrderId: '1', items: [{}] },
        'talabat',
      ),
    /does not match/,
  );
  assert.throws(
    () =>
      validateOrderPayload(
        { platform: 'talabat', externalOrderId: '1', items: [] },
        'talabat',
      ),
    /between 1 and 200/,
  );
  assert.throws(
    () =>
      validateOrderPayload(
        {
          platform: 'talabat',
          externalOrderId: '1',
          items: [{ name: 'Meal', quantity: 1, unitPrice: -1 }],
        },
        'talabat',
      ),
    /outside the allowed range/,
  );
});
