'use strict';

const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { allowedUrlList, loadConfig } = require('../src/config');
const { MockOrderServer } = require('../src/services/mock-order-server');
const { OrderIngestor } = require('../src/services/order-ingestor');
const {
  orderScreenRedirect,
} = require('../src/services/provider-order-router');

const ENV_KEYS = [
  'DESKTOP_POS_URL',
  'DESKTOP_API_URL',
  'DESKTOP_RESTAURANT_ID',
  'DESKTOP_API_TOKEN',
  'DESKTOP_ENABLE_MOCK_ORDERS',
  'DESKTOP_MOCK_PORT',
  'DESKTOP_MOCK_SECRET',
];

test('desktop .env values bind to the normalized main-process config', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'almenupro-config-'));
  const saved = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
  for (const key of ENV_KEYS) delete process.env[key];
  t.after(() => {
    fs.rmSync(directory, { recursive: true, force: true });
    for (const key of ENV_KEYS) {
      if (saved[key] == null) delete process.env[key];
      else process.env[key] = saved[key];
    }
  });
  fs.writeFileSync(
    path.join(directory, '.env'),
    [
      'DESKTOP_POS_URL=http://127.0.0.1:8080/admin/pos',
      'DESKTOP_API_URL=http://127.0.0.1:3000/api/',
      'DESKTOP_RESTAURANT_ID=rest_fixture',
      'DESKTOP_API_TOKEN=test-token',
      'DESKTOP_ENABLE_MOCK_ORDERS=true',
      'DESKTOP_MOCK_PORT=17329',
      'DESKTOP_MOCK_SECRET=fixture-secret-12345',
    ].join('\n'),
  );

  const config = loadConfig(directory);
  assert.deepEqual(
    config.loadedEnvFiles.map((filePath) => path.basename(filePath)),
    ['.env'],
  );
  assert.equal(config.posUrl, 'http://127.0.0.1:8080/admin/pos');
  assert.equal(config.apiUrl, 'http://127.0.0.1:3000/api');
  assert.equal(config.restaurantId, 'rest_fixture');
  assert.equal(config.apiToken, 'test-token');
  assert.deepEqual(config.warnings, []);
  assert.deepEqual(config.mockOrders, {
    enabled: true,
    port: 17329,
    secret: 'fixture-secret-12345',
  });
});

test('production provider origins are explicit HTTPS origins without wildcards', () => {
  const raw = fs.readFileSync(
    path.resolve(__dirname, '..', '.env.production.example'),
    'utf8',
  );
  const values = Object.fromEntries(
    raw
      .split(/\r?\n/)
      .map((line) => line.match(/^([A-Z0-9_]+)=(.*)$/))
      .filter(Boolean)
      .map((match) => [match[1], match[2].trim()]),
  );
  for (const provider of ['TALABAT', 'JAHEZ', 'KEETA']) {
    const value = values[`DESKTOP_${provider}_ALLOWED_ORIGINS`];
    assert.ok(value, `${provider} allowed origin is required`);
    assert.equal(value.includes('*'), false);
    for (const origin of value.split(',')) {
      assert.equal(new URL(origin).protocol, 'https:');
      assert.equal(new URL(origin).origin, origin);
    }
  }
});

test('order-screen fallbacks cannot escape the provider allowlist', () => {
  assert.deepEqual(
    allowedUrlList(
      'https://merchant.mykeeta.com/orders,https://merchant.keeta-global.com/history',
      'KEETA_ORDER_URLS',
      ['https://merchant.mykeeta.com', 'https://merchant.keeta-global.com'],
    ),
    [
      'https://merchant.mykeeta.com/orders',
      'https://merchant.keeta-global.com/history',
    ],
  );
  assert.throws(
    () =>
      allowedUrlList(
        'https://example.invalid/orders',
        'KEETA_ORDER_URLS',
        ['https://merchant.mykeeta.com'],
      ),
    /outside the provider allowlist/,
  );
});

test('Talabat dashboard and portal root redirect to configured order history', () => {
  const history = 'https://partner-app.talabat.com/orders/history';
  assert.equal(
    orderScreenRedirect('talabat', 'https://partner-app.talabat.com/dashboard', [
      history,
    ]),
    history,
  );
  assert.equal(
    orderScreenRedirect('talabat', 'https://partner-app.talabat.com/', [history]),
    history,
  );
  assert.equal(
    orderScreenRedirect('talabat', history, [history]),
    '',
  );
  assert.equal(
    orderScreenRedirect('jahez', 'https://merchant.jahez.net/dashboard', [history]),
    '',
  );
});

test('shared ingestor validates, deduplicates, and isolates bad records', () => {
  const keys = new Set();
  const queued = [];
  const errors = [];
  const events = [];
  const logs = [];
  const ingestor = new OrderIngestor({
    restaurantId: 'rest-test',
    dedupe: {
      has: (key) => keys.has(key),
      add: (key) => keys.add(key),
    },
    queue: {
      enqueue: (record) => {
        queued.push(record);
        return true;
      },
    },
    onError: (error) => errors.push(error),
    onIngest: (event) => events.push(event),
    logger: {
      info: (message) => logs.push(message),
      warn: () => {},
    },
  });
  const valid = {
    platform: 'talabat',
    externalOrderId: 'T-INTEGRATION-1',
    customerName: 'Fixture',
    items: [{ name: 'Meal', quantity: 1, unitPrice: 2, lineTotal: 2 }],
    totalAmount: 2,
    createdAt: new Date().toISOString(),
  };

  assert.deepEqual(ingestor.ingest('talabat', [valid]), {
    accepted: 1,
    duplicates: 0,
    rejected: 0,
    errors: [],
  });
  assert.equal(ingestor.ingest('talabat', [valid]).duplicates, 1);
  assert.equal(
    ingestor.ingest('talabat', [{ ...valid, externalOrderId: '' }]).rejected,
    1,
  );
  assert.equal(queued.length, 1);
  assert.equal(queued[0].order.ingestionSource, 'DOM_SCRAPER');
  assert.equal(events[0].ingestionSource, 'DOM_SCRAPER');
  assert.match(logs[0], /\[INGESTION MODE\].*DOM_SCRAPER/);
  assert.equal(errors.length, 1);
});

test('localhost mock server rejects unauthenticated calls and uses the ingestor', async (t) => {
  const received = [];
  const server = new MockOrderServer({
    port: 0,
    secret: 'test-secret-123456',
    ingestor: {
      ingest: (provider, orders, options) => {
        received.push({ provider, orders, options });
        return { accepted: 1, duplicates: 0, rejected: 0, errors: [] };
      },
    },
  });
  await server.start();
  t.after(() => server.stop());
  const port = server.server.address().port;
  const post = (authorization) =>
    fetch(`http://127.0.0.1:${port}/inject`, {
      method: 'POST',
      headers: {
        ...(authorization ? { Authorization: authorization } : {}),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        platform: 'jahez',
        externalOrderId: 'J-1',
        items: [{ name: 'Meal' }],
      }),
    });

  assert.equal((await post()).status, 401);
  const accepted = await post('Bearer test-secret-123456');
  assert.equal(accepted.status, 202);
  assert.equal(received.length, 1);
  assert.equal(received[0].provider, 'jahez');
  assert.equal(received[0].options.source, 'mock-cli');
});
