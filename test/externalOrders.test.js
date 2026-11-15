'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

const {
  findExistingExternalOrderIds,
  normalizeExternalOrder,
  normalizeExternalOutcome,
  normalizePlatform,
} = require('../lib/externalOrders');

const sample = {
  platform: 'talabat',
  externalOrderId: 'T-1007',
  customerName: 'Test Customer',
  deliveryType: 'delivery',
  items: [
    {
      name: 'Burger',
      quantity: 2,
      unitPrice: 3.25,
      options: ['No onions', { group: 'Size', name: 'Large', price: 0.5 }],
    },
  ],
  totalAmount: 6.5,
};

test('normalizes a scraped order into the existing AlMenuPro order shape', () => {
  const order = normalizeExternalOrder(sample, 'rest_test');

  assert.equal(order.orderSource, 'talabat');
  assert.equal(order.externalOrderId, 'T-1007');
  assert.equal(order.invoiceNumber, 'T-1007');
  assert.equal(order.restaurantId, 'rest_test');
  assert.equal(order.status, 'pending');
  assert.equal(order.createdFromPos, false);
  assert.equal(order.ingestion_source, 'DOM_SCRAPER');
  assert.equal(order.items[0].selectedOptions.length, 2);
  assert.equal(order.totalPrice, 6.5);
});

test('persists trusted API ingestion mode in both field styles', () => {
  const order = normalizeExternalOrder(
    { ...sample, ingestionSource: 'API' },
    'rest_test',
  );

  assert.equal(order.ingestionSource, 'API');
  assert.equal(order.ingestion_source, 'API');
});

test('accepts external invoices without customer contact or address fields', () => {
  const order = normalizeExternalOrder(
    {
      platform: 'talabat',
      externalOrderId: 'T-MINIMAL',
      items: [{ name: 'Meal', quantity: 1 }],
    },
    'rest_test',
  );

  assert.equal(order.invoiceNumber, 'T-MINIMAL');
  assert.equal(order.customerName, '');
  assert.equal(order.phone, '');
  assert.equal(order.address, '');
  assert.equal(order.items[0].name, 'Meal');
});

test('builds a stable internal id for endpoint idempotency', () => {
  const first = normalizeExternalOrder(sample, 'rest_test');
  const duplicate = normalizeExternalOrder({ ...sample, customerName: 'Changed' }, 'rest_test');
  const anotherRestaurant = normalizeExternalOrder(sample, 'rest_other');

  assert.equal(first.id, duplicate.id);
  assert.notEqual(first.id, anotherRestaurant.id);
});

test('maps the requested Keta spelling to the existing Keeta platform id', () => {
  assert.equal(normalizePlatform('Keta'), 'keeta');
});

test('classifies successful and cancelled provider outcomes', () => {
  assert.equal(normalizeExternalOutcome('Order accepted'), 'successful');
  assert.equal(normalizeExternalOutcome('Cancelled by customer'), 'cancelled');
  assert.equal(normalizeExternalOutcome('مسترد'), 'cancelled');
});

test('external order existence lookup is scoped by restaurant and platform', () => {
  const orders = [
    { restaurantId: 'rest_test', orderSource: 'talabat', externalOrderId: 'T-1' },
    { restaurantId: 'rest_other', orderSource: 'talabat', externalOrderId: 'T-2' },
    { restaurantId: 'rest_test', orderSource: 'jahez', externalOrderId: 'T-3' },
  ];
  assert.deepEqual(
    findExistingExternalOrderIds(orders, {
      restaurantId: 'rest_test',
      platform: 'talabat',
      externalOrderIds: ['T-1', 'T-2', 'T-3'],
    }),
    ['T-1'],
  );
});

test('rejects unsupported providers and malformed item lists', () => {
  assert.throws(
    () => normalizeExternalOrder({ ...sample, platform: 'unknown' }, 'rest_test'),
    { code: 'UNSUPPORTED_EXTERNAL_PLATFORM' },
  );
  assert.throws(
    () => normalizeExternalOrder({ ...sample, items: [] }, 'rest_test'),
    { code: 'INVALID_EXTERNAL_ORDER_ITEMS' },
  );
});

test('external-order endpoint requires an authorized cashier or administrator session', async () => {
  const dataStore = require('../lib/dataStore');
  const extraStore = require('../lib/extraStore');
  const { loginCashierSession } = require('../lib/adminAuth');
  const originals = {
    initDataStore: dataStore.initDataStore,
    readRestaurants: dataStore.readRestaurants,
    readOrders: dataStore.readOrders,
    readKitchens: dataStore.readKitchens,
    prependOrder: dataStore.prependOrder,
    patchOrderById: dataStore.patchOrderById,
    readSettingsMap: dataStore.readSettingsMap,
    customerRead: extraStore.customers.read,
    customerWrite: extraStore.customers.write,
  };
  const storedOrders = [];
  dataStore.initDataStore = async () => {};
  dataStore.readRestaurants = async () => [
    { id: 'rest_test', slug: 'test', name: 'Test Restaurant' },
  ];
  dataStore.readOrders = async () => [...storedOrders];
  dataStore.readKitchens = async () => [
    {
      id: 'kitchen-test',
      restaurantId: 'rest_test',
      restaurant_id: 'rest_test',
      name: 'Test Kitchen',
      status: 'active',
      isDefault: true,
    },
  ];
  dataStore.prependOrder = async (order) => {
    storedOrders.unshift(order);
  };
  dataStore.patchOrderById = async (orderId, next) => {
    const index = storedOrders.findIndex((order) => order.id === orderId);
    if (index !== -1) storedOrders[index] = next;
    return next;
  };
  dataStore.readSettingsMap = async () => ({ byRestaurant: {} });
  extraStore.customers.read = async () => [];
  extraStore.customers.write = async () => {};
  const handler = require('../apiServer');
  const server = http.createServer(handler);

  try {
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    const response = await fetch(
      `http://127.0.0.1:${address.port}/api/v1/orders/external`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(sample),
      },
    );
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: 'Unauthorized' });

    const kitchenToken = loginCashierSession({
      restaurantId: 'rest_test',
      restaurantName: 'Test',
      staffId: 'kitchen-1',
      staffName: 'Kitchen',
      asKitchen: true,
    });
    const forbidden = await fetch(
      `http://127.0.0.1:${address.port}/api/v1/orders/external`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${kitchenToken}`,
          'Content-Type': 'application/json',
          'X-Restaurant-Id': 'rest_test',
        },
        body: JSON.stringify(sample),
      },
    );
    assert.equal(forbidden.status, 403);
    const forbiddenLookup = await fetch(
      `http://127.0.0.1:${address.port}/api/v1/orders/external/exists?platform=talabat&id=T-1007`,
      {
        headers: {
          Authorization: `Bearer ${kitchenToken}`,
          'X-Restaurant-Id': 'rest_test',
        },
      },
    );
    assert.equal(forbiddenLookup.status, 403);

    const cashierToken = loginCashierSession({
      restaurantId: 'rest_test',
      restaurantName: 'Test',
      staffId: 'cashier-1',
      staffName: 'Cashier',
    });
    const submit = () =>
      fetch(`http://127.0.0.1:${address.port}/api/v1/orders/external`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${cashierToken}`,
          'Content-Type': 'application/json',
          'X-Restaurant-Id': 'rest_test',
        },
        body: JSON.stringify(sample),
      });
    const created = await submit();
    assert.equal(created.status, 201);
    const createdBody = await created.json();
    assert.equal(createdBody.status, 'pending');
    assert.equal(createdBody.orderSource, 'talabat');

    const duplicate = await submit();
    assert.equal(duplicate.status, 200);
    assert.equal(storedOrders.length, 1);

    const lookup = await fetch(
      `http://127.0.0.1:${address.port}/api/v1/orders/external/exists?platform=talabat&id=T-1007&id=T-MISSING`,
      {
        headers: {
          Authorization: `Bearer ${cashierToken}`,
          'X-Restaurant-Id': 'rest_test',
        },
      },
    );
    assert.equal(lookup.status, 200);
    assert.deepEqual(await lookup.json(), {
      platform: 'talabat',
      existing: ['T-1007'],
    });

    const enrich = await fetch(
      `http://127.0.0.1:${address.port}/api/v1/orders/external/enrich`,
      {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${cashierToken}`,
          'Content-Type': 'application/json',
          'X-Restaurant-Id': 'rest_test',
        },
        body: JSON.stringify({
          platform: 'talabat',
          externalOrderId: 'T-1007',
          phone: '+96550000000',
          address: 'Kuwait City',
        }),
      },
    );
    assert.equal(enrich.status, 200);
    assert.equal(storedOrders[0].phone, '+96550000000');
    assert.equal(storedOrders[0].address, 'Kuwait City');

    const reconciliationPayload = {
      ...sample,
      createdAt: new Date().toISOString(),
      externalStatus: 'successful',
      totalAmount: 7.5,
    };
    const reconcile = (payload) =>
      fetch(`http://127.0.0.1:${address.port}/api/v1/orders/external/reconcile`, {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${cashierToken}`,
          'Content-Type': 'application/json',
          'X-Restaurant-Id': 'rest_test',
        },
        body: JSON.stringify(payload),
      });
    const updated = await reconcile(reconciliationPayload);
    assert.equal(updated.status, 200);
    assert.equal((await updated.json()).action, 'updated');
    assert.equal(storedOrders[0].totalPrice, 7.5);

    const unchanged = await reconcile(reconciliationPayload);
    assert.equal(unchanged.status, 200);
    assert.equal((await unchanged.json()).action, 'unchanged');

    const createdByReconciliation = await reconcile({
      ...reconciliationPayload,
      externalOrderId: 'T-NEW',
    });
    assert.equal(createdByReconciliation.status, 201);
    assert.equal((await createdByReconciliation.json()).action, 'created');

    const cancelled = await reconcile({
      ...reconciliationPayload,
      externalStatus: 'cancelled',
    });
    assert.equal(cancelled.status, 200);
    assert.equal((await cancelled.json()).action, 'cancelled');
    assert.equal(
      storedOrders.find((order) => order.externalOrderId === 'T-1007').status,
      'cancelled',
    );

    const missingCancelled = await reconcile({
      ...reconciliationPayload,
      externalOrderId: 'T-CANCELLED-ONLY',
      externalStatus: 'cancelled',
    });
    assert.equal(missingCancelled.status, 201);
    assert.equal(
      (await missingCancelled.json()).action,
      'created_cancelled',
    );
    assert.equal(
      storedOrders.find(
        (order) => order.externalOrderId === 'T-CANCELLED-ONLY',
      ).status,
      'cancelled',
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
    dataStore.initDataStore = originals.initDataStore;
    dataStore.readRestaurants = originals.readRestaurants;
    dataStore.readOrders = originals.readOrders;
    dataStore.readKitchens = originals.readKitchens;
    dataStore.prependOrder = originals.prependOrder;
    dataStore.patchOrderById = originals.patchOrderById;
    dataStore.readSettingsMap = originals.readSettingsMap;
    extraStore.customers.read = originals.customerRead;
    extraStore.customers.write = originals.customerWrite;
  }
});
