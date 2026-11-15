'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { DedupeStore } = require('../src/services/dedupe-store');
const { OrderSubmitQueue } = require('../src/services/order-submit-queue');

test('dedupe entries persist across store instances', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'almenupro-dedupe-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'dedupe.json');

  const first = new DedupeStore(filePath);
  first.add('restaurant\u0000talabat\u0000123');

  const second = new DedupeStore(filePath);
  assert.equal(second.has('restaurant\u0000talabat\u0000123'), true);
});

test('queue persists and submits external orders with scoped auth headers', async (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'almenupro-queue-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const calls = [];
  const queue = new OrderSubmitQueue({
    filePath: path.join(directory, 'queue.json'),
    apiUrl: 'https://api.example.test/api',
    apiToken: 'token-value',
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return { ok: true, status: 201 };
    },
  });

  assert.equal(
    queue.enqueue({
      key: 'key-1',
      restaurantId: 'rest-1',
      order: { platform: 'talabat', externalOrderId: 'T-1', items: [{}] },
    }),
    true,
  );
  queue.stop();
  await queue.process();
  queue.stop();

  assert.equal(calls[0].url, 'https://api.example.test/api/v1/orders/external');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer token-value');
  assert.equal(calls[0].options.headers['X-Restaurant-Id'], 'rest-1');
  assert.deepEqual(queue.status(), { pending: 0, failed: 0 });

  const reloaded = new OrderSubmitQueue({
    filePath: path.join(directory, 'queue.json'),
    apiUrl: 'https://api.example.test/api',
    fetchImpl: async () => ({ ok: true, status: 200 }),
  });
  reloaded.stop();
  assert.deepEqual(reloaded.status(), { pending: 0, failed: 0 });
});
