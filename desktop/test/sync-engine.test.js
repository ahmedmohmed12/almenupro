'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  DailyReconciliationEngine,
  SyncEngine,
} = require('../src/services/sync-engine');

test('sync engine dispatches five-order cycles in provider order and isolates failures', async () => {
  const dispatched = [];
  const errors = [];
  const engine = new SyncEngine({
    providers: ['talabat', 'jahez', 'keeta'],
    dispatch: async (provider, payload) => {
      dispatched.push({ provider, payload });
      if (provider === 'jahez') throw new Error('fixture failure');
    },
    logger: {
      error: (...args) => errors.push(args.join(' ')),
    },
  });

  const cycleId = await engine.runCycle();

  assert.deepEqual(
    dispatched.map((entry) => entry.provider),
    ['talabat', 'jahez', 'keeta'],
  );
  assert.equal(dispatched.every((entry) => entry.payload.limit === 5), true);
  assert.equal(dispatched.every((entry) => entry.payload.cycleId === cycleId), true);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /jahez dispatch failed/);
});

test('sync engine interval is idempotent and stoppable', () => {
  const engine = new SyncEngine({
    providers: ['talabat'],
    dispatch: async () => {},
  });
  assert.equal(engine.intervalMs, 60_000);

  engine.start();
  const firstTimer = engine.timer;
  engine.start();
  assert.equal(engine.timer, firstTimer);
  engine.stop();
  assert.equal(engine.timer, null);
});

test('daily reconciliation prevents overlapping full-history cycles', async () => {
  let release;
  const blocker = new Promise((resolve) => {
    release = resolve;
  });
  let dispatches = 0;
  const engine = new DailyReconciliationEngine({
    providers: ['talabat'],
    dispatch: async () => {
      dispatches += 1;
      await blocker;
    },
  });

  const first = engine.runCycle();
  assert.equal(await engine.runCycle(), null);
  release();
  await first;
  assert.equal(dispatches, 1);
});
