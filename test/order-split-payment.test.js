const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applyOrderPaymentsFromBody,
  resolvePaidPaymentPayload,
  shiftPaymentBreakdown,
  validatePaymentsForTotal,
} = require('../lib/orderPayments');
const { computeShiftSummary } = require('../lib/shiftSessions');

test('validatePaymentsForTotal accepts balanced cash + knet split', () => {
  const result = validatePaymentsForTotal(
    [
      { method: 'cash', amount: 2.5 },
      { method: 'knet', amount: 1.25 },
    ],
    3.75,
  );
  assert.equal(result.ok, true);
  assert.equal(result.cashPortion, 2.5);
  assert.equal(result.knetPortion, 1.25);
});

test('validatePaymentsForTotal rejects mismatch beyond 3-decimal precision', () => {
  const result = validatePaymentsForTotal(
    [
      { method: 'cash', amount: 1 },
      { method: 'knet', amount: 1.001 },
    ],
    2,
  );
  assert.equal(result.ok, false);
  assert.equal(result.code, 'PAYMENT_TOTAL_MISMATCH');
});

test('validatePaymentsForTotal rejects zero or negative lines', () => {
  assert.equal(
    validatePaymentsForTotal([{ method: 'cash', amount: 0 }], 3).ok,
    false,
  );
  assert.equal(
    validatePaymentsForTotal([{ method: 'knet', amount: -1 }], 3).ok,
    false,
  );
});

test('applyOrderPaymentsFromBody stores payments and legacy label', () => {
  const applied = applyOrderPaymentsFromBody(
    { totalPrice: 4.5 },
    {
      payments: [
        { method: 'cash', amount: 2 },
        { method: 'knet', amount: 2.5 },
      ],
    },
  );
  assert.equal(applied.ok, true);
  assert.equal(applied.order.paymentMethod, 'كاش + كي نت');
  assert.deepEqual(applied.order.payments, [
    { method: 'cash', amount: 2 },
    { method: 'knet', amount: 2.5 },
  ]);
});

test('resolvePaidPaymentPayload supports single cashier settlement method', () => {
  const resolved = resolvePaidPaymentPayload(
    { paymentMethod: 'كاش' },
    { totalPrice: 3.25 },
  );
  assert.equal(resolved.ok, true);
  assert.equal(resolved.cashPortion, 3.25);
  assert.equal(resolved.knetPortion, 0);
});

test('shift summary allocates split payments without double-counting revenue', () => {
  const shift = { id: 'shift_split', openingFloat: 5, status: 'open' };
  const orders = [
    {
      id: 'split_1',
      shiftId: 'shift_split',
      status: 'delivered',
      orderType: 'pickup',
      orderSource: 'pos',
      createdFromPos: true,
      paymentStatus: 'paid',
      paymentMethod: 'كاش + كي نت',
      payments: [
        { method: 'cash', amount: 2 },
        { method: 'knet', amount: 3 },
      ],
      totalPrice: 5,
    },
    {
      id: 'cash_only',
      shiftId: 'shift_split',
      status: 'delivered',
      orderType: 'pickup',
      orderSource: 'pos',
      createdFromPos: true,
      paymentStatus: 'paid',
      paymentMethod: 'كاش',
      totalPrice: 1.5,
    },
  ];
  const summary = computeShiftSummary(orders, shift, null, []);
  assert.equal(summary.grossSales, 6.5);
  assert.equal(summary.cashSales, 3.5);
  assert.equal(summary.knetSales, 3);
  assert.equal(shiftPaymentBreakdown(orders[0]).cash, 2);
  assert.equal(shiftPaymentBreakdown(orders[0]).knet, 3);
});