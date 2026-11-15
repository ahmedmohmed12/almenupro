'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isOrderApiEvent,
  matchesOrderEndpoint,
  parseOrderPayloads,
} = require('../src/services/platform-order-network');

test('order endpoint filter keeps invoice APIs and skips login urls', () => {
  assert.equal(
    matchesOrderEndpoint(
      'keeta',
      'https://merchant.mykeeta.com/api/order/getOrderDtl?token=secret',
    ),
    true,
  );
  assert.equal(
    matchesOrderEndpoint(
      'talabat',
      'https://vendor-portal-api.deliveryhero.io/v1/vendors/787662/orders',
    ),
    true,
  );
  assert.equal(
    matchesOrderEndpoint('jahez', 'https://portal.jahez.net/api/v1/incoming'),
    true,
  );
  assert.equal(
    matchesOrderEndpoint('keeta', 'https://merchant.mykeeta.com/api/auth/token'),
    false,
  );
  assert.equal(
    isOrderApiEvent('talabat', {
      type: 'Document',
      response: {
        url: 'https://partner-app.talabat.com/orders/history',
        mimeType: 'text/html',
        status: 200,
      },
    }),
    false,
  );
});

test('parsed platform payloads keep items, fees, and cash', () => {
  const keeta = parseOrderPayloads('keeta', {
    data: {
      orderInfo: {
        baseOrder: { orderViewIdStr: '5484143597003335', payTypeDesc: 'Cash' },
        products: [{ count: 1, name: 'Majboos', priceWithGroup: { amount: 2500, unitPrice: 2500 } }],
      },
    },
  });
  assert.equal(keeta[0].externalOrderId, '5484143597003335');
  assert.equal(keeta[0].paymentMethod, 'Cash');

  const talabat = parseOrderPayloads('talabat', {
    orders: [
      {
        order_id: '3947327520',
        payment_method: 'Cash',
        delivery_fee: 0.5,
        discount_amount: 0.25,
        items: [{ name: 'Majboos', quantity: 1, unit_price: 2.5 }],
        customer: { name: 'عميل', phone: '50000000', address: 'Kuwait' },
      },
    ],
  });
  assert.equal(talabat[0].paymentMethod, 'Cash');
  assert.equal(talabat[0].deliveryFee, 0.5);
  assert.equal(talabat[0].discountAmount, 0.25);
  assert.equal(talabat[0].address, 'Kuwait');

  assert.deepEqual(parseOrderPayloads('jahez', { orderId: '12345' }), []);
});
