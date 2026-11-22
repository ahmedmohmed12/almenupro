'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  createStaffRecord,
  updateStaffRecord,
} = require('../lib/staffUsers');

test('POS cashier create requires HR provision and employeeId', () => {
  assert.throws(
    () =>
      createStaffRecord(
        { name: 'Ali', roleId: 'cashier', pin: '1234' },
        'rest_1',
      ),
    /شؤون الموظفين/,
  );

  const row = createStaffRecord(
    {
      name: 'Ali',
      roleId: 'shift_supervisor',
      pin: '1234',
      employeeId: 'emp_1',
      provisionSource: 'hr',
    },
    'rest_1',
    { provisionSource: 'hr' },
  );
  assert.equal(row.roleId, 'cashier');
  assert.equal(row.employeeId, 'emp_1');
});

test('kitchen staff create bypasses HR gate', () => {
  const row = createStaffRecord(
    {
      name: 'Kitchen',
      roleId: 'kitchen',
      kitchenId: 'kit_1',
      pin: '1234',
    },
    'rest_1',
  );
  assert.equal(row.roleId, 'kitchen');
  assert.equal(row.employeeId, null);
});