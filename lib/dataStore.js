const fs = require('fs');
const path = require('path');
const { MongoClient } = require('mongodb');
const { ensureRestaurantId, migrateSettingsShape, defaultSettingsPayload } = require('./tenantStore');
const { DEFAULT_RESTAURANT_ID } = require('./adminAuth');

const DATA_DIR = path.join(__dirname, '..', 'data');
const FILES = {
  menuItems: path.join(DATA_DIR, 'menu_items.json'),
  orders: path.join(DATA_DIR, 'orders.json'),
  settings: path.join(DATA_DIR, 'settings.json'),
  restaurants: path.join(DATA_DIR, 'restaurants.json'),
};

const IS_VERCEL = Boolean(process.env.VERCEL);
const MONGODB_URI = process.env.MONGODB_URI || '';
const MONGODB_DB = process.env.MONGODB_DB || 'almenupro';
const COLLECTION = 'platform_docs';

let mongoClient;
let mongoDb;
let mongoReady = false;
let mongoInitPromise;

const memory = {
  menuItems: [],
  orders: [],
  restaurants: [],
  settings: migrateSettingsShape({}),
};

function loadJson(filePath, fallback) {
  try {
    if (!fs.existsSync(filePath)) return fallback;
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return parsed ?? fallback;
  } catch {
    return fallback;
  }
}

function seedFromFiles() {
  const menuItems = loadJson(FILES.menuItems, []);
  const orders = loadJson(FILES.orders, []);
  const restaurants = loadJson(FILES.restaurants, []);
  const settings = migrateSettingsShape(loadJson(FILES.settings, {}));

  memory.menuItems = Array.isArray(menuItems)
    ? menuItems.map((item) => ensureRestaurantId(item))
    : [];
  memory.orders = Array.isArray(orders)
    ? orders.map((order) => ensureRestaurantId(order))
    : [];
  memory.restaurants = Array.isArray(restaurants) ? restaurants : [];
  memory.settings = settings;

  if (!memory.settings.byRestaurant?.[DEFAULT_RESTAURANT_ID]) {
    memory.settings.byRestaurant = memory.settings.byRestaurant || {};
    memory.settings.byRestaurant[DEFAULT_RESTAURANT_ID] = defaultSettingsPayload();
  }
}

function writeJson(filePath, value) {
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2), 'utf8');
}

function usesMongo() {
  return Boolean(MONGODB_URI);
}

async function initMongo() {
  if (!usesMongo()) return false;
  if (mongoReady) return true;
  if (mongoInitPromise) return mongoInitPromise;

  mongoInitPromise = (async () => {
    mongoClient = new MongoClient(MONGODB_URI);
    await mongoClient.connect();
    mongoDb = mongoClient.db(MONGODB_DB);
    mongoReady = true;

    const existing = await mongoDb.collection(COLLECTION).countDocuments();
    if (existing === 0) {
      seedFromFiles();
      await persistAllToMongo();
    }
    return true;
  })();

  return mongoInitPromise;
}

async function readDoc(id, fallback) {
  if (usesMongo()) {
    await initMongo();
    const doc = await mongoDb.collection(COLLECTION).findOne({ _id: id });
    return doc?.data ?? fallback;
  }

  return fallback;
}

async function writeDoc(id, data) {
  if (usesMongo()) {
    await initMongo();
    await mongoDb.collection(COLLECTION).updateOne(
      { _id: id },
      { $set: { data, updatedAt: new Date().toISOString() } },
      { upsert: true },
    );
    return;
  }

  switch (id) {
    case 'menu_items':
      memory.menuItems = data;
      if (!IS_VERCEL) writeJson(FILES.menuItems, data);
      break;
    case 'orders':
      memory.orders = data;
      if (!IS_VERCEL) writeJson(FILES.orders, data);
      break;
    case 'restaurants':
      memory.restaurants = data;
      if (!IS_VERCEL) writeJson(FILES.restaurants, data);
      break;
    case 'settings':
      memory.settings = data;
      if (!IS_VERCEL) writeJson(FILES.settings, data);
      break;
    default:
      break;
  }
}

async function persistAllToMongo() {
  await writeDoc('menu_items', memory.menuItems);
  await writeDoc('orders', memory.orders);
  await writeDoc('restaurants', memory.restaurants);
  await writeDoc('settings', memory.settings);
}

async function initDataStore() {
  seedFromFiles();

  if (usesMongo()) {
    await initMongo();
    memory.menuItems = (await readDoc('menu_items', memory.menuItems)).map((item) =>
      ensureRestaurantId(item),
    );
    memory.orders = (await readDoc('orders', memory.orders)).map((order) =>
      ensureRestaurantId(order),
    );
    memory.restaurants = await readDoc('restaurants', memory.restaurants);
    memory.settings = migrateSettingsShape(await readDoc('settings', memory.settings));
    return;
  }

  if (IS_VERCEL) {
    try {
      delete require.cache[require.resolve('../data/menu_items.json')];
      const freshItems = require('../data/menu_items.json');
      if (Array.isArray(freshItems)) {
        memory.menuItems = freshItems.map((item) => ensureRestaurantId(item));
      }
    } catch (_) {}

    try {
      delete require.cache[require.resolve('../data/restaurants.json')];
      const freshRestaurants = require('../data/restaurants.json');
      if (Array.isArray(freshRestaurants)) {
        memory.restaurants = freshRestaurants;
      }
    } catch (_) {}
  }
}

async function readItems() {
  if (usesMongo()) {
    const items = await readDoc('menu_items', memory.menuItems);
    return Array.isArray(items) ? items.map((item) => ensureRestaurantId(item)) : [];
  }

  if (IS_VERCEL) {
    return memory.menuItems.map((item) => ensureRestaurantId(item));
  }

  const items = loadJson(FILES.menuItems, memory.menuItems);
  memory.menuItems = Array.isArray(items)
    ? items.map((item) => ensureRestaurantId(item))
    : [];
  return memory.menuItems;
}

async function writeItems(items) {
  const normalized = items.map((item) => ensureRestaurantId(item));
  memory.menuItems = normalized;
  await writeDoc('menu_items', normalized);
}

async function readOrders() {
  if (usesMongo()) {
    const orders = await readDoc('orders', memory.orders);
    return Array.isArray(orders) ? orders.map((order) => ensureRestaurantId(order)) : [];
  }

  if (IS_VERCEL) {
    return memory.orders.map((order) => ensureRestaurantId(order));
  }

  const orders = loadJson(FILES.orders, memory.orders);
  memory.orders = Array.isArray(orders)
    ? orders.map((order) => ensureRestaurantId(order))
    : [];
  return memory.orders;
}

async function writeOrders(orders) {
  const normalized = orders.map((order) => ensureRestaurantId(order));
  memory.orders = normalized;
  await writeDoc('orders', normalized);
}

async function readRestaurants() {
  if (usesMongo()) {
    const restaurants = await readDoc('restaurants', memory.restaurants);
    return Array.isArray(restaurants) ? restaurants : [];
  }

  if (IS_VERCEL) {
    return memory.restaurants;
  }

  const restaurants = loadJson(FILES.restaurants, memory.restaurants);
  memory.restaurants = Array.isArray(restaurants) ? restaurants : [];
  return memory.restaurants;
}

async function writeRestaurants(restaurants) {
  memory.restaurants = restaurants;
  await writeDoc('restaurants', restaurants);
  return restaurants;
}

async function readSettingsMap() {
  if (usesMongo()) {
    return migrateSettingsShape(await readDoc('settings', memory.settings));
  }

  if (IS_VERCEL) {
    return migrateSettingsShape(memory.settings);
  }

  memory.settings = migrateSettingsShape(loadJson(FILES.settings, memory.settings));
  return memory.settings;
}

async function writeSettingsMap(map) {
  memory.settings = migrateSettingsShape(map);
  await writeDoc('settings', memory.settings);
  return memory.settings;
}

module.exports = {
  initDataStore,
  usesMongo,
  readItems,
  writeItems,
  readOrders,
  writeOrders,
  readRestaurants,
  writeRestaurants,
  readSettingsMap,
  writeSettingsMap,
};
