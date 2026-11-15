'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const {
  TalabatIngestionService,
  normalizeOrder,
  normalizeTalabatApiPayment,
} = require('../src/services/talabat-ingestion-service');
const {
  VendorCredentialStore,
} = require('../src/services/vendor-credential-store');
const { DedupeStore } = require('../src/services/dedupe-store');
const { OrderIngestor } = require('../src/services/order-ingestor');

function credentialStore() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'almenupro-creds-'));
  const safeStorage = {
    isEncryptionAvailable: () => true,
    encryptString: (value) => Buffer.from(`encrypted:${value}`),
    decryptString: (value) =>
      value.toString('utf8').replace(/^encrypted:/, ''),
  };
  return new VendorCredentialStore({
    filePath: path.join(directory, 'credentials.json'),
    safeStorage,
  });
}

test('API payment mapper keeps Cash and only maps explicit online gateways', () => {
  assert.equal(normalizeTalabatApiPayment('Cash'), 'Cash');
  assert.equal(normalizeTalabatApiPayment('Cash on Delivery'), 'Cash');
  assert.equal(normalizeTalabatApiPayment('Collect Cash'), 'Cash');
  assert.equal(normalizeTalabatApiPayment('ONLINE'), 'Prepaid');
  assert.equal(normalizeTalabatApiPayment('Credit Card'), 'Prepaid');
  assert.equal(normalizeTalabatApiPayment('KNET'), 'KNET');
  assert.equal(
    normalizeTalabatApiPayment('', { paid: true, payment_method: '' }),
    '',
  );
  assert.equal(
    normalizeTalabatApiPayment('ONLINE', { paid: true }),
    'Prepaid',
  );
});

test('zone catalog fee does not replace ingested Talabat totals', () => {
  const order = normalizeOrder({
    order_id: 'TB-1',
    items: [{ item_id: 'a', name: 'Meal', quantity: 1, unit_price: 10 }],
    delivery_fee: 0.5,
    total_amount: 10.5,
    zone_delivery_fee: 2.5,
    payment_method: 'Cash',
    customer: { address: 'غرب عبدالله المبارك' },
  });
  assert.equal(order.deliveryFee, 0.5);
  assert.equal(order.customerPayableTotal, 10.5);
  assert.equal(order.netMerchantSales, 10);
  assert.equal(order.priceLocked, true);
  assert.equal(order.address, 'غرب عبدالله المبارك');

  const withoutPlatformFee = normalizeOrder({
    order_id: 'TB-2',
    items: [{ item_id: 'a', name: 'Meal', quantity: 1, unit_price: 10 }],
    total_amount: 10,
    zone_delivery_fee: 2.5,
    payment_method: 'Prepaid',
  });
  assert.equal(withoutPlatformFee.deliveryFee, 0);
  assert.equal(withoutPlatformFee.customerPayableTotal, 10);
  assert.equal(withoutPlatformFee.totalAmount, 10);
});

test('credential store encrypts tokens and never exposes them in status', () => {
  const store = credentialStore();
  const status = store.save('talabat', {
    vendorId: '651304',
    authToken: 'header.payload.signature-token',
  });
  assert.equal(status.configured, true);
  assert.equal(Object.hasOwn(status, 'authToken'), false);
  assert.equal(
    store.get('talabat').authToken,
    'header.payload.signature-token',
  );
});

test('Talabat REST orders flow through the shared deduplicating ingestor', async () => {
  const ingested = [];
  const service = new TalabatIngestionService({
    credentialStore: credentialStore(),
    ingestor: {
      ingest: (provider, orders, options) => {
        ingested.push({ provider, orders, options });
        return { accepted: 1, duplicates: 0, rejected: 0, errors: [] };
      },
    },
    httpClient: {
      get: async () => ({
        data: {
          status: 'success',
          data: {
            orders: [
              {
                order_id: '3941518752',
                created_at: '2026-10-07T14:48:00Z',
                customer: { name: 'Wadha', phone: '+96550000000' },
                items: [
                  {
                    item_id: 'item_001',
                    name: 'Orange Juice',
                    quantity: 1,
                    unit_price: 1,
                  },
                ],
                total_amount: 1,
                payment_method: 'ONLINE',
              },
            ],
          },
        },
      }),
    },
  });

  const result = await service.fetchActiveOrders(
    '651304',
    'header.payload.signature-token',
  );

  assert.equal(service.intervalMs, 60_000);
  assert.equal(result.accepted, 1);
  assert.equal(ingested[0].provider, 'talabat');
  assert.equal(ingested[0].orders[0].externalOrderId, '3941518752');
  assert.equal(ingested[0].orders[0].items[0].platformItemId, 'item_001');
  assert.equal(ingested[0].options.source, 'talabat-rest-api');
});

test('authentication and network errors trigger DOM fallback', async () => {
  const fallbacks = [];
  const service = new TalabatIngestionService({
    credentialStore: credentialStore(),
    ingestor: { ingest: () => assert.fail('ingestor should not run') },
    httpClient: {
      get: async () => {
        const error = new Error('Unauthorized');
        error.response = { status: 401 };
        throw error;
      },
    },
    onFallback: async (payload) => fallbacks.push(payload),
    logger: { warn: () => {}, error: () => {} },
  });

  const result = await service.fetchActiveOrders(
    '651304',
    'header.payload.signature-token',
  );

  assert.equal(result.fallback, true);
  assert.equal(result.reason, 'http_401');
  assert.deepEqual(fallbacks, [{ provider: 'talabat', reason: 'http_401' }]);
});

test('server and invalid responses also fall back to DOM without dropping intake', async () => {
  const fallbacks = [];
  const statuses = [];
  const service = new TalabatIngestionService({
    credentialStore: credentialStore(),
    ingestor: { ingest: () => assert.fail('ingestor should not run') },
    httpClient: {
      get: async () => {
        const error = new Error('Bad Gateway');
        error.response = { status: 502 };
        throw error;
      },
    },
    onFallback: async (payload) => fallbacks.push(payload),
    onStatus: (payload) => statuses.push(payload),
    logger: { warn: () => {}, error: () => {} },
  });

  const result = await service.fetchActiveOrders(
    '651304',
    'header.payload.signature-token',
  );

  assert.equal(result.fallback, true);
  assert.equal(result.reason, 'http_502');
  assert.deepEqual(fallbacks, [{ provider: 'talabat', reason: 'http_502' }]);
  assert.equal(statuses.at(-1)?.mode, 'dom_fallback');
});

test('repeated REST polling enqueues one POS order only', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'almenupro-api-dedupe-'));
  const enqueued = [];
  const ingestor = new OrderIngestor({
    restaurantId: 'rest_test',
    dedupe: new DedupeStore(path.join(directory, 'dedupe.json')),
    queue: { enqueue: (record) => enqueued.push(record) },
  });
  const service = new TalabatIngestionService({
    credentialStore: credentialStore(),
    ingestor,
    httpClient: {
      get: async () => ({
        data: {
          status: 'success',
          data: {
            orders: [
              {
                order_id: '3941518752',
                created_at: '2026-10-07T14:48:00Z',
                items: [
                  {
                    item_id: 'item_001',
                    name: 'Orange Juice',
                    quantity: 1,
                    unit_price: 1,
                  },
                ],
                total_amount: 1,
              },
            ],
          },
        },
      }),
    },
  });

  const first = await service.fetchActiveOrders(
    '651304',
    'header.payload.signature-token',
  );
  const second = await service.fetchActiveOrders(
    '651304',
    'header.payload.signature-token',
  );

  assert.equal(first.accepted, 1);
  assert.equal(second.duplicates, 1);
  assert.equal(enqueued.length, 1);
  assert.equal(enqueued[0].order.ingestionSource, 'API');
});
