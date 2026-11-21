const test = require('node:test');
const assert = require('node:assert/strict');

const { computeShiftSummary } = require('../lib/shiftSessions');
const { isPendingPaymentOrder } = require('../lib/orderPaymentStatus');

test('held pickup orders are excluded from shift revenue until paid', () => {
  const shift = {
    id: 'shift_1',
    openingFloat: 10,
    status: 'open',
  };
  const orders = [
    {
      id: 'held',
      shiftId: 'shift_1',
      status: 'confirmed',
      orderType: 'pickup',
      orderSource: 'pos',
      createdFromPos: true,
      paymentStatus: 'pending_payment',
      paymentMethod: 'غير مدفوع',
      totalPrice: 5.5,
    },
    {
      id: 'paid',
      shiftId: 'shift_1',
      status: 'delivered',
      orderType: 'pickup',
      orderSource: 'pos',
      createdFromPos: true,
      paymentStatus: 'paid',
      paymentMethod: 'كاش',
      totalPrice: 3,
    },
  ];
  const summary = computeShiftSummary(orders, shift, null, []);
  assert.equal(summary.grossSales, 3);
  assert.equal(summary.takeawaySales, 3);
  assert.equal(summary.cashSales, 3);
});

test('dine-in kitchen orders stay pending until checkout marks paid', () => {
  assert.equal(
    isPendingPaymentOrder({
      orderType: 'dineIn',
      orderSource: 'pos-dine-in',
      createdFromPos: true,
      paymentStatus: 'pending_payment',
      status: 'preparing',
    }),
    true,
  );
});