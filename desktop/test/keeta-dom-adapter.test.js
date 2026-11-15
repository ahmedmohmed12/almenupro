'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  collectKeetaHistoryRows,
  extractKeetaCreatedAt,
  extractKeetaOrderIds,
  extractKeetaPortalOrderId,
  keetaTodayStamp,
  extractKeetaCustomerDetails,
  extractKeetaOrderStatus,
  mapKeetaDomOrderToPos,
} = require('../src/adapters/keeta-dom-adapter');
const { createAdapter } = require('../src/adapters/registry');

function leaf(text) {
  return { textContent: text, children: [] };
}

function drawerFromScreenshot() {
  const leaves = [
    leaf('# 9251'),
    leaf('5464144081829251'),
    leaf('Keeta delivery'),
    leaf('Q7D513704043'),
    leaf('+965 97921900'),
    leaf('Customer address:'),
    leaf('غرب عبدالله المبارك, 539,7,743,7'),
    leaf('Courier'),
    leaf('Order accepted by courier'),
    leaf('Order placed'),
    leaf('7 Oct at 22:15 (GMT+3)'),
    leaf('Item details'),
    leaf('1 item'),
  ];
  return {
    textContent: leaves.map((node) => node.textContent).join(' '),
    children: leaves,
    querySelectorAll: (selector) => {
      if (/item|product|addon|modifier/i.test(String(selector || ''))) {
        return [];
      }
      return leaves;
    },
    querySelector: () => null,
  };
}

test('Keeta DOM adapter extracts ids, customer, phone, address, and fulfillment', () => {
  const details = extractKeetaCustomerDetails(drawerFromScreenshot());
  assert.equal(details.shortOrderId, '9251');
  assert.equal(details.externalOrderId, '5464144081829251');
  assert.equal(details.invoiceNumber, '#9251');
  assert.equal(details.customerName, 'Q7D513704043');
  assert.equal(details.phone, '+965 97921900');
  assert.equal(details.address, 'غرب عبدالله المبارك, 539,7,743,7');
  assert.equal(details.deliveryType, 'Keeta delivery');
});

test('Keeta DOM order maps into the unified POS shape', () => {
  const order = mapKeetaDomOrderToPos(drawerFromScreenshot());
  assert.equal(order.platform, 'keeta');
  assert.equal(order.externalOrderId, '5464144081829251');
  assert.equal(order.invoiceNumber, '#9251');
  assert.equal(order.customerName, 'Q7D513704043');
  assert.equal(order.phone, '+965 97921900');
  assert.equal(order.address, 'غرب عبدالله المبارك, 539,7,743,7');
  assert.equal(order.deliveryType, 'Keeta delivery');
});

test('KetaAdapter parseOrder merges screenshot DOM into POS order fields', () => {
  const adapter = createAdapter('keeta', {
    querySelector: () => null,
    querySelectorAll: () => [],
  });
  const order = adapter.parseOrder(drawerFromScreenshot(), '5464144081829251');
  assert.equal(order.platform, 'keeta');
  assert.equal(order.externalOrderId, '5464144081829251');
  assert.equal(order.invoiceNumber, '#9251');
  assert.equal(order.customerName, 'Q7D513704043');
  assert.equal(order.phone, '+965 97921900');
  assert.equal(order.address, 'غرب عبدالله المبارك, 539,7,743,7');
  assert.equal(order.deliveryType, 'Keeta delivery');
});

test('Keeta history cell keeps the 15-digit id and Today stamp', () => {
  const cell = {
    textContent: '5484143597003335 #3335; Today, 22:12 (GMT+3)',
    children: [],
    querySelector: () => null,
    querySelectorAll: () => [],
  };
  const now = new Date('2026-10-09T20:00:00+03:00');
  assert.equal(extractKeetaPortalOrderId(cell.textContent), '5484143597003335');
  assert.equal(extractKeetaOrderIds(cell).shortOrderId, '3335');
  assert.equal(keetaTodayStamp(cell, now), '2026-10-09');
  assert.equal(
    collectKeetaHistoryRows({ querySelectorAll: () => [cell], body: { textContent: '' } }, 10, now).length,
    1,
  );
});

test('Keeta history rows keep the 09-10-2026 platform time and status', () => {
  const row = {
    textContent: '#4410 5464144081824410 Completed 09-10-2026 14:05 Cash',
    children: [],
    querySelectorAll: () => [],
  };
  assert.equal(extractKeetaOrderStatus(row), 'completed');
  assert.equal(extractKeetaCreatedAt(row), '2026-10-09T11:05:00.000Z');
  const rows = collectKeetaHistoryRows(
    { querySelectorAll: () => [row], body: { textContent: '' } },
    10,
    new Date('2026-10-09T12:00:00+03:00'),
  );
  assert.equal(rows.length, 1);
  assert.equal(mapKeetaDomOrderToPos(row).externalOrderId, '5464144081824410');
  assert.equal(mapKeetaDomOrderToPos(row).createdAt, '2026-10-09T11:05:00.000Z');
});
