'use strict';

const mysqlStore = require('../lib/mysqlStore');
const dataStore = require('../lib/dataStore');

async function main() {
  if (!mysqlStore.isConfigured()) {
    console.error(
      'MySQL is not configured. Copy env.mysql.example to .env or set MYSQL_HOST / MYSQL_DATABASE.',
    );
    process.exit(2);
  }

  await mysqlStore.connect();
  await dataStore.initDataStore();
  const health = dataStore.storageHealth();
  console.log('health', health);

  const restaurants = await dataStore.readRestaurants();
  if (!Array.isArray(restaurants) || restaurants.length === 0) {
    throw new Error('expected seeded restaurants from data/*.json');
  }

  const marker = `mysql_smoke_${Date.now()}`;
  const orders = await dataStore.readOrders();
  await dataStore.prependOrder({
    id: marker,
    restaurant_id: restaurants[0].id,
    restaurantId: restaurants[0].id,
    status: 'new',
    items: [],
    total: 0,
  });
  const after = await dataStore.readOrders();
  const found = after.some((order) => String(order.id) === marker);
  if (!found) throw new Error('order was not persisted to MySQL');

  const raw = await mysqlStore.getDoc('orders');
  const inTable = Array.isArray(raw) && raw.some((order) => String(order.id) === marker);
  if (!inTable) throw new Error('platform_docs.orders payload missing smoke order');

  console.log(
    JSON.stringify(
      {
        ok: true,
        storage: health.storage,
        restaurants: restaurants.length,
        orders: after.length,
        smokeOrderId: marker,
      },
      null,
      2,
    ),
  );
  process.exit(0);
}

main().catch((error) => {
  console.error('mysql-smoke failed:', error?.message || error);
  process.exit(1);
});
