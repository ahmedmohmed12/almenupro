'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  applyKitchenVoidPayrollDeductions,
  APPROVAL_STATUSES,
} = require('../lib/kitchenVoidLiabilities');

test('applyKitchenVoidPayrollDeductions marks rejected rows once', () => {
  const rows = [
    {
      id: 'kvl_1',
      approvalStatus: APPROVAL_STATUSES.REJECTED,
      amount: 3,
    },
    {
      id: 'kvl_2',
      approvalStatus: APPROVAL_STATUSES.PENDING,
      amount: 2,
    },
  ];
  const first = applyKitchenVoidPayrollDeductions(rows, {
    month: 3,
    year: 2026,
    liabilityIds: ['kvl_1'],
  });
  assert.equal(first.updated, 1);
  assert.ok(first.rows[0].payrollDeductedAt);
  assert.equal(first.rows[0].payrollDeductedMonth, 3);

  const second = applyKitchenVoidPayrollDeductions(first.rows, {
    month: 3,
    year: 2026,
    liabilityIds: ['kvl_1'],
  });
  assert.equal(second.updated, 0);
});