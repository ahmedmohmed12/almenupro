'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ExternalOrderReconciliationService,
} = require('../src/services/external-order-reconciliation-service');

test('reconciliation service sends scoped authenticated canonical order data', async () => {
  let request;
  const service = new ExternalOrderReconciliationService({
    apiUrl: 'http://localhost:3000/api',
    apiToken: 'token',
    restaurantId: 'rest_test',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        json: async () => ({ action: 'updated' }),
      };
    },
  });
  const result = await service.reconcile({
    platform: 'talabat',
    externalOrderId: 'T-1',
    externalStatus: 'successful',
    items: [{ name: 'Meal', quantity: 1, unitPrice: 3 }],
  });

  assert.equal(result.action, 'updated');
  assert.equal(request.url, 'http://localhost:3000/api/v1/orders/external/reconcile');
  assert.equal(request.options.headers['X-Restaurant-Id'], 'rest_test');
  assert.equal(JSON.parse(request.options.body).externalOrderId, 'T-1');
});

test('reconciliation service serializes writes to the local datastore', async () => {
  let active = 0;
  let maxActive = 0;
  const service = new ExternalOrderReconciliationService({
    apiUrl: 'http://localhost:3000/api',
    apiToken: 'token',
    restaurantId: 'rest_test',
    fetchImpl: async () => {
      active += 1;
      maxActive = Math.max(maxActive, active);
      await new Promise((resolve) => setTimeout(resolve, 10));
      active -= 1;
      return { ok: true, json: async () => ({ action: 'updated' }) };
    },
  });

  await Promise.all([
    service.reconcile({ externalOrderId: 'T-1' }),
    service.reconcile({ externalOrderId: 'T-2' }),
    service.reconcile({ externalOrderId: 'T-3' }),
  ]);

  assert.equal(maxActive, 1);
});
