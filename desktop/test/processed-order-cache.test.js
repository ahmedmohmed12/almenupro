'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ProcessedOrderCache,
} = require('../src/services/processed-order-cache');
const { fromDomOrder } = require('../src/services/orderParser');

test('network and DOM ids share one cache key for 24 hours', () => {
  const cache = new ProcessedOrderCache();
  cache.remember('Talabat', '3947000111', 'NETWORK');
  assert.equal(cache.has('talabat', 'TB_KW|3947000111'), true);
  assert.deepEqual(cache.processedIds('talabat', ['3947000111', '999']), [
    '3947000111',
  ]);
  const fallback = fromDomOrder({
    platform: 'talabat',
    externalOrderId: 'TB_KW|3947000111',
    paymentMethod: 'Cash',
    items: [{ name: 'مجبوس', quantity: 1, unitPrice: 2.5, lineTotal: 2.5 }],
    totalAmount: 2.5,
  });
  assert.equal(fallback.order_id, '3947000111');
  assert.equal(fallback.source, 'DOM 👁️');
  assert.equal(fallback.payment_method, 'Cash');
});

test('processed ids expire after a day and the cache stays capped', () => {
  const expired = new ProcessedOrderCache({ ttlMs: 1000 });
  expired.remember('keeta', '5484143597003335', 'NETWORK');
  expired.entries.get('keeta:5484143597003335').at = Date.now() - 5000;
  assert.equal(expired.has('keeta', '5484143597003335'), false);

  const capped = new ProcessedOrderCache({ maxEntries: 2 });
  capped.remember('jahez', '10001', 'NETWORK');
  capped.remember('jahez', '10002', 'DOM 👁️');
  capped.remember('jahez', '10003', 'NETWORK');
  assert.equal(capped.has('jahez', '10001'), false);
  assert.equal(capped.has('jahez', '10002'), true);
  assert.equal(capped.has('jahez', '10003'), true);
});
