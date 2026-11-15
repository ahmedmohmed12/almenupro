'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  runIsolatedPlatformSync,
} = require('../src/services/sync-orchestrator');

test('one platform failure does not stop the others', async () => {
  const finished = [];
  const summary = await runIsolatedPlatformSync({
    providers: ['jahez', 'keeta', 'talabat'],
    runProvider: async (provider) => {
      if (provider === 'jahez') throw new Error('login page');
      return { checked: 4, ingested: 1, purged: 2 };
    },
    onPlatformResult: (row) => finished.push(row.provider),
  });
  assert.deepEqual(finished, ['jahez', 'keeta', 'talabat']);
  assert.equal(summary.synced, 2);
  assert.equal(summary.purged, 4);
  assert.equal(summary.details.find((row) => row.provider === 'jahez').unread, true);
  assert.equal(summary.details.find((row) => row.provider === 'keeta').synced, 1);
});

test('automatic capture notice names the platform and Keeta short id', () => {
  const { autoIngestNotice } = require('../src/services/sync-orchestrator');
  assert.equal(
    autoIngestNotice('keeta', { synced: 1, orderId: '5484143597003335' }),
    'تم جلب طلب جديد تلقائياً من كيتا #3335',
  );
  assert.equal(
    autoIngestNotice('talabat', { synced: 3, orderId: '3947327520' }),
    'تم جلب 3 طلبات جديدة تلقائياً من طلبات',
  );
});
