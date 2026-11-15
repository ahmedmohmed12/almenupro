'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeKeetaOrderDetail,
  providerCreatedAt,
} = require('../src/services/keeta-order-response');

test('normalizes Keeta getOrderDtl products into an external order', () => {
  const order = normalizeKeetaOrderDetail({
    data: {
      orderInfo: {
        baseOrder: {
          orderViewIdStr: '5444144162913517',
          ctime: 1791230447217,
          payTypeDesc: 'Apple Pay',
        },
        merchantOrderDeliveries: [{ waybillId: 1 }],
        recipientInfo: {
          recipientName: 'Test Customer',
          recipientPhone: '+96550000000',
          deliveryAddress: 'Kuwait City',
        },
        courier: {
          courierName: 'Not the customer',
          courierPhone: '99999999',
        },
        products: [
          {
            count: 2,
            price: 1500,
            name: 'Chicken Majboos',
            priceWithGroup: { amount: 3000, unitPrice: 1500 },
          },
        ],
      },
    },
  });

  assert.equal(order.externalOrderId, '5444144162913517');
  assert.equal(order.platform, 'keeta');
  assert.equal(order.deliveryType, 'delivery');
  assert.equal(order.items[0].name, 'Chicken Majboos');
  assert.equal(order.items[0].quantity, 2);
  assert.equal(order.items[0].unitPrice, 1.5);
  assert.equal(order.totalAmount, 3);
  assert.equal(order.customerName, 'Test Customer');
  assert.equal(order.phone, '+96550000000');
  assert.equal(order.address, 'Kuwait City');
  assert.equal(order.createdAt, new Date(1791230447217).toISOString());
});

test('normalizes provider timestamps without replacing missing times on every sync', () => {
  assert.equal(
    providerCreatedAt(1791230447),
    new Date(1791230447 * 1000).toISOString(),
  );
  assert.equal(providerCreatedAt(null, ''), null);
});

test('rejects Keeta detail responses without an id or products', () => {
  assert.equal(normalizeKeetaOrderDetail({ data: { orderInfo: {} } }), null);
});
