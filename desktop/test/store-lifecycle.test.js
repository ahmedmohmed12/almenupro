'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { getAdapter } = require('../src/adapters/platforms');
const { StoresConfig, sanitizeStoreUrl } = require('../src/services/stores-config');
const {
  StoreLifecycleManager,
  chromeDesktopUserAgent,
  stampStoreOrder,
} = require('../src/services/store-lifecycle-manager');

test('portal user agent is desktop Chrome without an Electron token', () => {
  const userAgent = chromeDesktopUserAgent();
  assert.match(userAgent, /^Mozilla\/5.0 \(Windows NT 10\.0; Win64; x64\)/);
  assert.match(userAgent, /Chrome\/\d+\.\d+\.\d+\.\d+ Safari\/537\.36$/);
  assert.equal(/electron/i.test(userAgent), false);
});

test('platform adapters parse a payload and expose selectors', () => {
  const talabat = getAdapter('talabat');
  const orders = talabat.parsePayload({
    order_id: '3947000111',
    payment_method: 'Cash',
    items: [{ name: 'مجبوس', quantity: 1, unit_price: 2.5 }],
  });
  assert.equal(orders[0].externalOrderId, '3947000111');
  assert.equal(orders[0].paymentMethod, 'Cash');
  assert.equal(typeof talabat.getSelectors().item, 'string');
  assert.equal(getAdapter('keeta').type, 'keeta');
  assert.equal(getAdapter('jahez').type, 'jahez');
});

test('store lifecycle spawns only enabled stores and toggles views', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'almenu-stores-'));
  const config = new StoresConfig({
    filePath: path.join(directory, 'storesConfig.json'),
    defaults: [
      {
        id: 'store_talabat',
        name: 'Talabat Branch 1',
        type: 'talabat',
        url: 'https://partner-app.talabat.com/',
        enabled: true,
        partition: 'persist:provider-talabat-test',
      },
      {
        id: 'store_keeta',
        name: 'Keeta Main',
        type: 'keeta',
        url: 'https://merchant.mykeeta.com/m/web/mach/b_pc_order_history_list',
        enabled: false,
        partition: 'persist:store_keeta',
      },
    ],
  });
  const alive = new Set();
  const manager = new StoreLifecycleManager({
    storeConfig: config,
    viewFactory(store) {
      alive.add(store.id);
      return { destroy() { alive.delete(store.id); } };
    },
  });
  manager.start();
  assert.deepEqual([...alive], ['store_talabat']);

  await manager.toggleStore('store_keeta', true);
  assert.equal(alive.has('store_keeta'), true);

  const added = await manager.addStore({
    name: 'Talabat Branch 2',
    type: 'talabat',
    url: 'https://partner-app.talabat.com/orders',
    enabled: true,
  });
  assert.equal(alive.has(added.id), true);
  assert.equal(added.partition, `persist:${added.id}`);

  await manager.toggleStore(added.id, false);
  assert.equal(alive.has(added.id), false);

  await manager.removeStore('store_keeta');
  assert.equal(alive.has('store_keeta'), false);
  assert.equal(manager.listStores().some((store) => store.id === 'store_keeta'), false);

  const stamped = stampStoreOrder(
    { order_id: '3947000111', source: 'NETWORK' },
    manager.getStore('store_talabat'),
  );
  assert.equal(stamped.store_id, 'store_talabat');
  assert.equal(stamped.store_name, 'Talabat Branch 1');
  assert.equal(stamped.platform_type, 'talabat');
});

test('store URLs drop a leading slash and keep an http origin', async () => {
  assert.equal(
    sanitizeStoreUrl('/https://partner-app.talabat.com'),
    'https://partner-app.talabat.com',
  );
  assert.equal(
    sanitizeStoreUrl('  partner-app.talabat.com/orders  '),
    'https://partner-app.talabat.com/orders',
  );

  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'almenu-store-url-'));
  const filePath = path.join(directory, 'storesConfig.json');
  fs.writeFileSync(
    filePath,
    JSON.stringify({
      stores: [
        {
          id: 'store_talabat',
          name: 'Talabat',
          type: 'talabat',
          url: '/https://partner-app.talabat.com',
          enabled: true,
          partition: 'persist:provider-talabat-test',
        },
      ],
    }),
  );
  const config = new StoresConfig({ filePath, defaults: [] });
  const store = config.get('store_talabat');
  assert.equal(store.url, 'https://partner-app.talabat.com/');
  const saved = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  assert.equal(saved.stores[0].url, 'https://partner-app.talabat.com/');

  const added = config.add({
    name: 'Second branch',
    type: 'talabat',
    url: '/https://partner-app.talabat.com/orders',
    enabled: true,
  });
  assert.equal(added.url, 'https://partner-app.talabat.com/orders');
});
