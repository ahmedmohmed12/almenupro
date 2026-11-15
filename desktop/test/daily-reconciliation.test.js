'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { missingOrderIds, scrollTarget } = require('../src/preload/daily-reconciliation');
const {
  extractTalabatColumnOrderId,
} = require('../src/services/talabat-ingestion-service');

test('missing order lookup keeps only ids the database does not have', async () => {
  const calls = [];
  const ipc = {
    async invoke(channel, ids) {
      calls.push({ channel, ids });
      return { missing: ids.filter((id) => id === 'NEW-1') };
    },
  };
  const missing = await missingOrderIds(ipc, ['OLD-1', 'NEW-1', 'OLD-2']);
  assert.deepEqual(calls[0].ids, ['OLD-1', 'NEW-1', 'OLD-2']);
  assert.deepEqual(missing, ['NEW-1']);
});

test('scroll target ignores a missing history container', () => {
  assert.equal(scrollTarget(null), null);
  assert.equal(scrollTarget(undefined), null);
});

test('talabat order id column keeps the portal number', () => {
  const {
    talabatHistoryCreatedAt,
    talabatStampIsToday,
  } = require('../src/services/talabat-ingestion-service');
  assert.equal(extractTalabatColumnOrderId('3947327520 Today, 22:32'), '3947327520');
  assert.equal(extractTalabatColumnOrderId('Order 3941518752'), '3941518752');
  assert.equal(talabatStampIsToday('3947327520 Today, 22:32', new Date('2026-10-09T20:00:00+03:00')), true);
  const created = talabatHistoryCreatedAt('Yesterday, 10:00', new Date('2026-10-09T20:00:00+03:00'));
  assert.equal(created.startsWith('2026-10-08'), true);
});
