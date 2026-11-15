'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  computePlatformDualTotals,
  isCashOnDelivery,
  normalizeCashierSettlementMethod,
  settlementLabel,
} = require('../lib/platformOrderFinance');
const { normalizeExternalOrder } = require('../lib/externalOrders');

test('dual totals keep delivery fees out of merchant sales', () => {
  const totals = computePlatformDualTotals({
    itemsTotal: 10,
    deliveryFee: 1.5,
    discount: 1,
  });
  assert.equal(totals.netMerchantSales, 9);
  assert.equal(totals.customerPayableTotal, 10.5);
  assert.equal(totals.priceLocked, true);
});

test('cash stays COD and card stays prepaid', () => {
  assert.equal(isCashOnDelivery('Cash'), true);
  assert.equal(settlementLabel('Cash'), 'CASH ON DELIVERY');
  assert.equal(settlementLabel('Prepaid'), 'PREPAID / ONLINE');
  assert.equal(settlementLabel('KNET'), 'PREPAID / ONLINE');
});

test('cashier settlement correction accepts only Cash or KNET', () => {
  assert.equal(normalizeCashierSettlementMethod('كاش'), 'Cash');
  assert.equal(normalizeCashierSettlementMethod('Cash on Delivery'), 'Cash');
  assert.equal(normalizeCashierSettlementMethod('كي نت'), 'KNET');
  assert.equal(normalizeCashierSettlementMethod('K-Net'), 'KNET');
  assert.equal(normalizeCashierSettlementMethod('Prepaid'), '');
  assert.equal(normalizeCashierSettlementMethod('Apple Pay'), '');
});

test('external ingest stores payable and merchant sales separately', () => {
  const order = normalizeExternalOrder(
    {
      platform: 'talabat',
      externalOrderId: 'T-1',
      customerName: 'Noura',
      phone: '+96550000000',
      address: 'Farwaniya',
      deliveryInstructions: 'الباب الخلفي',
      paymentMethod: 'Cash',
      items: [{ name: 'Juice', quantity: 2, unitPrice: 1.5 }],
      deliveryFee: 0.5,
      discountAmount: 0.25,
    },
    'rest_1',
  );
  assert.equal(order.subtotal, 3);
  assert.equal(order.netMerchantSales, 2.75);
  assert.equal(order.customerPayableTotal, 3.25);
  assert.equal(order.totalPrice, 3.25);
  assert.equal(order.priceLocked, true);
  assert.equal(order.deliveryInstructions, 'الباب الخلفي');
});
