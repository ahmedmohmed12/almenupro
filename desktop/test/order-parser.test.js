'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  createOrderDispatcher,
  identifyPlatform,
  isArchiveEndpoint,
  parseIncomingOrders,
  reconcileTotals,
} = require('../src/services/orderParser');

test('parses a Keeta invoice into the shared order schema', () => {
  const [result] = parseIncomingOrders(
    {
      data: {
        orderInfo: {
          baseOrder: { orderViewIdStr: '5484143597003335', payTypeDesc: 'Cash' },
          recipientInfo: { recipientName: 'نورة', recipientPhone: '50000000', deliveryAddress: 'شارع ١' },
          products: [{ count: 1, name: 'مجبوس', priceWithGroup: { amount: 2500, unitPrice: 2500 } }],
        },
      },
    },
    { platform: 'keeta' },
  );
  assert.equal(result.ok, true);
  assert.equal(result.order.platform_name, 'Keeta');
  assert.equal(result.order.status, 'NEW');
  assert.equal(result.order.order_id, '5484143597003335');
  assert.equal(result.order.items[0].item_name, 'مجبوس');
  assert.equal(result.order.full_address.street, 'شارع ١');
  assert.equal(
    result.order.totals.grand_total,
    Number(
      (
        result.order.totals.subtotal -
        result.order.totals.discount +
        result.order.totals.delivery_fee
      ).toFixed(3),
    ),
  );
});

test('rejects a total that does not match items, discount, and delivery', () => {
  const [result] = parseIncomingOrders(
    {
      order_id: '3947327520',
      payment_method: 'Cash',
      total_amount: 9,
      delivery_fee: 0.5,
      discount_amount: 0.25,
      items: [{ name: 'مجبوس', quantity: 1, unit_price: 2.5 }],
    },
    { platform: 'talabat' },
  );
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'totals_mismatch');
});

test('marks a repeated order as updated and a cancelled order as cancelled', () => {
  const sent = [];
  const dispatcher = createOrderDispatcher({
    send: (order) => sent.push(order.status),
  });
  const payload = {
    orderId: '998877',
    customerName: 'عميل',
    items: [{ name: 'برجر', quantity: 2, unitPrice: 1.5 }],
    totalAmount: 3,
  };
  dispatcher.accept(payload, 'jahez');
  dispatcher.accept(
    { ...payload, items: [{ name: 'برجر', quantity: 1, unitPrice: 1.5 }], totalAmount: 1.5 },
    'jahez',
  );
  dispatcher.accept({ orderId: '998877', status: 'cancelled' }, 'jahez');
  assert.deepEqual(sent, ['NEW', 'UPDATED', 'CANCELLED']);
  assert.equal(identifyPlatform({ order_id: '1' }), 'talabat');
});

test('recalculates an unreliable subtotal without changing the grand total', () => {
  const items = [{ price: 2.5, quantity: 1 }];
  const totals = reconcileTotals(
    { subtotal: 0, delivery_fee: 0.5, discount: 0.25, grand_total: 2.75 },
    items,
  );
  assert.equal(totals.subtotal, 2.5);
  assert.equal(totals.grand_total, 2.75);
  assert.equal(totals.delivery_fee, 0.5);
  assert.equal(totals.discount, 0.25);
});

test('accepted then preparing updates keep the same order and fill the address', () => {
  const sent = [];
  const dispatcher = createOrderDispatcher({
    send: (order) => sent.push(order),
  });
  const base = {
    order_id: '3947000111',
    payment_method: 'Cash',
    subtotal: 0,
    delivery_fee: 0.5,
    discount_amount: 0.25,
    total_amount: 2.75,
    items: [{ name: 'مجبوس', quantity: 1, unit_price: 2.5 }],
  };
  dispatcher.accept(
    { ...base, order_status: 'ACCEPTED', customer: { name: 'عميل' } },
    'talabat',
    { url: 'https://vendor-portal-api.deliveryhero.io/v1/vendors/1/orders' },
  );
  dispatcher.accept(
    {
      ...base,
      order_status: 'PREPARING',
      customer: { name: 'سارة', address: 'شارع ١٠، مبنى ٤' },
      delivery_instructions: 'الطابق ٢',
    },
    'talabat',
  );
  dispatcher.accept(
    { order_id: '3947000111', order_status: 'CONFIRMED' },
    'talabat',
  );
  dispatcher.accept(base, 'talabat', {
    url: 'https://partner-app.talabat.com/orders/history',
  });

  assert.equal(sent.length, 3);
  assert.equal(sent[0].status, 'NEW');
  assert.equal(sent[0].platform_status, 'ACCEPTED');
  assert.equal(sent[0].totals.subtotal, 2.5);
  assert.equal(sent[0].totals.grand_total, 2.75);
  assert.equal(sent[0].payment_method, 'Cash');
  assert.equal(sent[1].status, 'UPDATED');
  assert.equal(sent[1].platform_status, 'PREPARING');
  assert.equal(sent[1].full_address.street, 'شارع ١٠، مبنى ٤');
  assert.equal(sent[1].full_address.notes, 'الطابق ٢');
  assert.equal(sent[2].status, 'UPDATED');
  assert.equal(sent[2].platform_status, 'CONFIRMED');
  assert.equal(sent[2].full_address.street, 'شارع ١٠، مبنى ٤');
  assert.equal(isArchiveEndpoint('https://partner-app.talabat.com/past-orders'), true);
});
