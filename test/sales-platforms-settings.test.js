const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { normalizeSalesPlatformsList } = require('../lib/salesPlatformsSettings');

describe('normalizeSalesPlatformsList', () => {
  it('keeps commission percent', () => {
    const rows = normalizeSalesPlatformsList([
      {
        id: 'talabat',
        name: 'Talabat',
        commissionPercent: 18.5,
        color: '#ff5a00',
        isBuiltIn: true,
      },
    ]);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].commissionPercent, 18.5);
    assert.equal(rows[0].id, 'talabat');
  });
});