'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isWalkInPosCustomerOptional,
  normalizePosOrderCustomerContact,
} = require('../lib/posCustomerContact');

test('dine-in orders treat customer contact as optional', () => {
  assert.equal(
    isWalkInPosCustomerOptional({ orderType: 'dineIn', tableId: 't1' }),
    true,
  );
});

test('pickup POS orders with استلام address treat contact as optional', () => {
  assert.equal(
    isWalkInPosCustomerOptional({
      orderSource: 'local',
      orderType: 'pickup',
      address: 'استلام من المحل',
    }),
    true,
  );
});

test('delivery orders keep customer contact required at normalization layer', () => {
  const normalized = normalizePosOrderCustomerContact({
    orderType: 'delivery',
    orderSource: 'local',
    customerName: '',
    phone: '',
    address: 'قطعة 1',
  });
  assert.equal(normalized.customerName, '');
  assert.equal(normalized.phone, '');
});

test('optional orders get walk-in defaults when name and phone are empty', () => {
  const normalized = normalizePosOrderCustomerContact({
    orderType: 'pickup',
    orderSource: 'local',
    address: 'استلام من المحل',
    customerName: '',
    phone: '',
  });
  assert.equal(normalized.phone, '00000000');
  assert.equal(normalized.customerName, 'استلام من المحل');
});

test('dine-in defaults use table label when name is empty', () => {
  const normalized = normalizePosOrderCustomerContact(
    {
      orderType: 'dineIn',
      orderSource: 'pos-dine-in',
      tableNumber: 7,
      customerName: '',
      phone: '',
    },
    {},
  );
  assert.equal(normalized.phone, '00000000');
  assert.equal(normalized.customerName, 'طاولة 7');
});