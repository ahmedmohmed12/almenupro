'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { computePlatformReconciliationReport } = require('../lib/platformReconciliationReport');
const { frozenOrderFinancials, matchDeliveryZone } = require('../lib/zoneAddressMatch');

test('platform report keeps customer payable separate from merchant sales', () => {
  const report = computePlatformReconciliationReport(
    [
      {
        id: 'ord_1',
        restaurantId: 'rest_beit',
        orderSource: 'talabat',
        externalOrderId: 'TB-1',
        invoiceNumber: 'TB-1',
        status: 'confirmed',
        createdAt: new Date().toISOString(),
        paymentMethod: 'Cash',
        deliveryType: 'Talabat delivery',
        items: [
          {
            name: 'مجبوس',
            quantity: 1,
            unitPrice: 3,
            lineTotal: 3.5,
            options: [{ name: 'زيادة', price: 0.5 }],
            discount: 0,
          },
        ],
        subtotal: 3.5,
        deliveryFee: 0.5,
        discountAmount: 0,
        customerPayableTotal: 4,
        netMerchantSales: 3.5,
        platformCommission: 0.7,
        totalPrice: 4,
      },
    ],
    'rest_beit',
    { days: 1 },
  );
  assert.equal(report.orderCount, 1);
  assert.equal(report.channels[0].customerPayableTotal, 4);
  assert.equal(report.channels[0].netMerchantSales, 3.5);
  assert.equal(report.channels[0].platformCommission, 0.7);
  assert.equal(report.channels[0].platformDeliveryFee, 0.5);
  assert.equal(report.channels[0].merchantDeliveryFee, 0);
  assert.equal(report.orders[0].items[0].modifiersTotal, 0.5);
  assert.equal(report.orders[0].paymentStatus, 'CASH ON DELIVERY');
});

test('merchant courier delivery fee is reported separately and zone match does not change money', () => {
  const order = {
    id: 'ord_2',
    restaurantId: 'rest_beit',
    orderSource: 'keeta',
    externalOrderId: 'K-2',
    status: 'confirmed',
    createdAt: new Date().toISOString(),
    paymentMethod: 'KNET',
    deliveryType: 'Merchant delivery',
    deliveryFee: 1,
    customerPayableTotal: 6,
    netMerchantSales: 5,
    totalPrice: 6,
    items: [],
  };
  const report = computePlatformReconciliationReport([order], 'rest_beit', { days: 1 });
  assert.equal(report.channels[0].merchantDeliveryFee, 1);
  assert.equal(report.channels[0].netMerchantSales, 5);
  const zone = matchDeliveryZone('السالمية، قطعة 2', [
    { id: 'z1', areaName: 'حولي', governorate: 'حولي', isActive: true },
    { id: 'z2', areaName: 'السالمية', governorate: 'حولي', isActive: true, deliveryFee: 2.5 },
  ]);
  assert.equal(zone.id, 'z2');
  const frozen = frozenOrderFinancials(order);
  assert.equal(frozen.customerPayableTotal, 6);
  assert.equal(frozen.netMerchantSales, 5);
  assert.equal(frozen.deliveryFee, 1);
  assert.equal(frozen.zoneDeliveryFee, undefined);
});
