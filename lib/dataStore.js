const fs = require('fs');
const path = require('path');
const { ensureRestaurantId, migrateSettingsShape, defaultSettingsPayload } = require('./tenantStore');
const { DEFAULT_RESTAURANT_ID } = require('./adminAuth');

let MongoClient = null;
try {
  ({ MongoClient } = require('mongodb'));
} catch {
  MongoClient = null;
}

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
let mongoDisabled = false;
let mongoInitPromise;
let mongoErrorMessage = '';

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
  return Boolean(MONGODB_URI) && Boolean(MongoClient) && !mongoDisabled;
}

async function initMongo() {
  if (!usesMongo()) return false;
  if (mongoReady) return true;
  if (mongoInitPromise) return mongoInitPromise;

  mongoInitPromise = (async () => {
    try {
      mongoClient = new MongoClient(MONGODB_URI, {
        serverSelectionTimeoutMS: 10000,
        connectTimeoutMS: 10000,
        maxPoolSize: 5,
      });
      await mongoClient.connect();
      mongoDb = mongoClient.db(MONGODB_DB);
      mongoReady = true;
      mongoErrorMessage = '';

      const existing = await mongoDb.collection(COLLECTION).countDocuments();
      if (existing === 0) {
        seedFromFiles();
        await persistAllToMongo();
      }
      return true;
    } catch (error) {
      mongoDisabled = true;
      mongoReady = false;
      mongoClient = null;
      mongoDb = null;
      mongoInitPromise = null;
      mongoErrorMessage = String(error?.message || error);
      console.error(
        '[dataStore] MongoDB unavailable, using JSON/memory fallback:',
        mongoErrorMessage,
      );
      return false;
    }
  })();

  return mongoInitPromise;
}

async function readDoc(id, fallback) {
  if (usesMongo()) {
    const ready = await initMongo();
    if (!ready || !mongoDb) return fallback;
    const doc = await mongoDb.collection(COLLECTION).findOne({ _id: id });
    return doc?.data ?? fallback;
  }

  return fallback;
}

async function writeDoc(id, data) {
  if (usesMongo()) {
    const ready = await initMongo();
    if (ready && mongoDb) {
      await mongoDb.collection(COLLECTION).updateOne(
        { _id: id },
        { $set: { data, updatedAt: new Date().toISOString() } },
        { upsert: true },
      );
      return;
    }
  }

  memoryWrite(id, data);
}

function memoryWrite(id, data) {
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

const ITEMS_COLLECTION = 'menu_item_docs';
const LITE_ITEM_PROJECTION = {
  _id: 0,
  id: 1,
  restaurant_id: 1,
  restaurantId: 1,
  category_id: 1,
  categoryId: 1,
  category_name: 1,
  categoryName: 1,
  category_name_en: 1,
  name: 1,
  name_ar: 1,
  name_en: 1,
  price: 1,
  image_url: 1,
  imageUrl: 1,
  is_available: 1,
  isAvailable: 1,
  display_order: 1,
  displayOrder: 1,
};

let itemsColReady = false;
let itemsColPromise;

function sanitizeImageUrl(value) {
  const url = String(value || '').trim();
  if (!url) return '';
  if (url.startsWith('data:')) return '';
  if (url.length > 2048) return '';
  return url;
}

function sanitizeItem(item) {
  if (!item || typeof item !== 'object') return item;
  const imageUrl = sanitizeImageUrl(
    item.image_url || item.imageUrl || item.image || item.photo || item.thumbnail,
  );
  return {
    ...item,
    image_url: imageUrl,
    imageUrl,
  };
}

function toLiteItem(item) {
  const clean = sanitizeItem(item);
  return {
    id: clean.id,
    restaurant_id: clean.restaurant_id || clean.restaurantId,
    category_id: clean.category_id || clean.categoryId || 0,
    category_name: clean.category_name || clean.categoryName || '',
    category_name_en: clean.category_name_en || clean.categoryNameEn || '',
    name: clean.name,
    name_ar: clean.name_ar || clean.nameAr || clean.name,
    name_en: clean.name_en || clean.nameEn || '',
    price: clean.price,
    image_url: clean.image_url || '',
    is_available: clean.is_available ?? clean.isAvailable ?? 1,
    display_order: clean.display_order ?? clean.displayOrder ?? 0,
  };
}

function itemToDoc(item) {
  const clean = sanitizeItem(ensureRestaurantId(item));
  const restaurantId = String(clean.restaurant_id || DEFAULT_RESTAURANT_ID);
  return {
    ...clean,
    _id: `${restaurantId}:${clean.id}`,
    restaurant_id: restaurantId,
  };
}

async function ensureItemsCollection() {
  if (itemsColReady && mongoDb) return mongoDb.collection(ITEMS_COLLECTION);
  if (itemsColPromise) return itemsColPromise;

  itemsColPromise = (async () => {
    const ready = await initMongo();
    if (!ready || !mongoDb) return null;
    const col = mongoDb.collection(ITEMS_COLLECTION);
    await Promise.all([
      col.createIndex({ restaurant_id: 1, display_order: 1 }),
      col.createIndex({ restaurant_id: 1, id: 1 }),
    ]);
    itemsColReady = true;
    return col;
  })();

  return itemsColPromise;
}

async function migrateItemsCollection(col) {
  const existing = await col.estimatedDocumentCount();
  if (existing > 0) return;
  const blob = await readDoc('menu_items', memory.menuItems);
  const source = Array.isArray(blob) ? blob : [];
  if (source.length === 0) return;
  const docs = source.map(itemToDoc);
  for (let i = 0; i < docs.length; i += 50) {
    try {
      await col.insertMany(docs.slice(i, i + 50), { ordered: false });
    } catch (_) {
      // Duplicate keys on retry are fine.
    }
  }
}

async function readItemsPage({
  restaurantId,
  offset = 0,
  limit = 40,
  lite = true,
} = {}) {
  const skip = Math.max(Number(offset) || 0, 0);
  const take = Math.min(Math.max(Number(limit) || 40, 1), 100);

  if (usesMongo()) {
    try {
      const col = await ensureItemsCollection();
      if (col) {
        const existing = await col.estimatedDocumentCount();
        if (existing === 0) {
          migrateItemsCollection(col).catch(() => {});
        } else {
          const filter = restaurantId
            ? { restaurant_id: String(restaurantId) }
            : {};
          const query = col.find(filter, {
            projection: lite ? LITE_ITEM_PROJECTION : { _id: 0 },
          });
          const [total, docs] = await Promise.all([
            col.countDocuments(filter),
            query
              .sort({ display_order: 1, id: 1 })
              .skip(skip)
              .limit(take)
              .toArray(),
          ]);
          const mapped = docs.map((item) =>
            lite ? toLiteItem(item) : sanitizeItem(item),
          );
          return { items: mapped, total, limit: take, offset: skip };
        }
      }
    } catch (error) {
      console.error('[dataStore] readItemsPage collection fallback:', error?.message || error);
    }

    try {
      const fromBlob = await readItemsPageFromBlob({
        restaurantId,
        skip,
        take,
        lite,
      });
      if (fromBlob) return fromBlob;
    } catch (error) {
      console.error('[dataStore] readItemsPage blob slice fallback:', error?.message || error);
    }
  }

  let items = await readItems();
  if (restaurantId) {
    items = items.filter(
      (item) =>
        String(item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID) ===
        String(restaurantId),
    );
  }
  const total = items.length;
  const sliced = items
    .slice(skip, skip + take)
    .map((item) => (lite ? toLiteItem(item) : sanitizeItem(item)));
  return { items: sliced, total, limit: take, offset: skip };
}

async function readItemsPageFromBlob({ restaurantId, skip, take, lite }) {
  const ready = await initMongo();
  if (!ready || !mongoDb) return null;

  const matchId = restaurantId ? String(restaurantId) : null;
  const pipeline = [
    { $match: { _id: 'menu_items' } },
    {
      $project: {
        filtered: matchId
          ? {
              $filter: {
                input: { $ifNull: ['$data', []] },
                as: 'item',
                cond: {
                  $eq: [
                    {
                      $ifNull: [
                        '$$item.restaurant_id',
                        { $ifNull: ['$$item.restaurantId', DEFAULT_RESTAURANT_ID] },
                      ],
                    },
                    matchId,
                  ],
                },
              },
            }
          : { $ifNull: ['$data', []] },
      },
    },
    {
      $project: {
        total: { $size: '$filtered' },
        items: { $slice: ['$filtered', skip, take] },
      },
    },
  ];

  const [row] = await mongoDb.collection(COLLECTION).aggregate(pipeline).toArray();
  if (!row) return { items: [], total: 0, limit: take, offset: skip };
  const mapped = (row.items || []).map((item) =>
    lite ? toLiteItem(item) : sanitizeItem(item),
  );
  return { items: mapped, total: row.total || 0, limit: take, offset: skip };
}

function storageHealth() {
  if (mongoReady) {
    return {
      ok: true,
      storage: 'mongodb',
      persistent: true,
    };
  }

  const usingFallback = Boolean(MONGODB_URI) && (mongoDisabled || !MongoClient);
  return {
    ok: true,
    storage: IS_VERCEL ? 'memory' : 'json',
    persistent: !IS_VERCEL,
    persistenceMessage: usingFallback
      ? mongoErrorMessage
        ? `MongoDB unavailable (${mongoErrorMessage}); using JSON/memory fallback`
        : 'MongoDB driver unavailable; using JSON/memory fallback'
      : undefined,
  };
}

async function initDataStore() {
  try {
    seedFromFiles();

    if (usesMongo()) {
      const ready = await initMongo();
      if (ready && mongoReady) {
        memory.restaurants = await readDoc('restaurants', memory.restaurants);
        memory.settings = migrateSettingsShape(await readDoc('settings', memory.settings));
        return;
      }
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
  } catch (error) {
    mongoDisabled = true;
    mongoReady = false;
    mongoErrorMessage = String(error?.message || error);
    seedFromFiles();
    console.error('[dataStore] initDataStore recovered via seed:', mongoErrorMessage);
  }
}

let itemsMemoryAt = 0;
const ITEMS_MEMORY_TTL_MS = 20000;

async function readItems() {
  if (usesMongo()) {
    if (
      Array.isArray(memory.menuItems) &&
      memory.menuItems.length > 0 &&
      Date.now() - itemsMemoryAt < ITEMS_MEMORY_TTL_MS
    ) {
      return memory.menuItems;
    }
    const items = await readDoc('menu_items', memory.menuItems);
    memory.menuItems = Array.isArray(items)
      ? items.map((item) => ensureRestaurantId(item))
      : [];
    itemsMemoryAt = Date.now();
    return memory.menuItems;
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
  const normalized = items.map((item) => sanitizeItem(ensureRestaurantId(item)));
  memory.menuItems = normalized;
  itemsMemoryAt = Date.now();
  await writeDoc('menu_items', normalized);

  if (usesMongo()) {
    try {
      const col = await ensureItemsCollection();
      if (col && normalized.length) {
        await col.bulkWrite(
          normalized.map((item) => {
            const doc = itemToDoc(item);
            return {
              replaceOne: {
                filter: { _id: doc._id },
                replacement: doc,
                upsert: true,
              },
            };
          }),
          { ordered: false },
        );
      }
    } catch (error) {
      console.error('[dataStore] items collection sync skipped:', error?.message || error);
    }
  }
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

function itemIdFilters(itemId) {
  const n = Number(itemId);
  const filters = [{ id: itemId }, { id: String(itemId) }];
  if (Number.isFinite(n)) filters.unshift({ id: n });
  return filters;
}

async function findItemDoc(itemId) {
  const col = await ensureItemsCollection();
  if (!col) return null;
  const existing = await col.findOne({ $or: itemIdFilters(itemId) });
  if (!existing) return null;
  const { _id, ...item } = existing;
  return sanitizeItem(item);
}

async function patchItemAvailability(itemId, isAvailable) {
  const flag = isAvailable === false || isAvailable === 0 ? 0 : 1;
  const col = await ensureItemsCollection();
  if (!col) return null;
  const existing = await col.findOne({ $or: itemIdFilters(itemId) });
  if (!existing) return null;
  const next = sanitizeItem({
    ...existing,
    is_available: flag,
    isAvailable: flag === 1,
  });
  const doc = itemToDoc(next);
  await col.replaceOne({ _id: existing._id }, { ...doc, _id: existing._id });
  return next;
}

async function deleteItemDoc(itemId) {
  const col = await ensureItemsCollection();
  if (!col) return;
  await col.deleteMany({ $or: itemIdFilters(itemId) });
}

module.exports = {
  initDataStore,
  usesMongo,
  storageHealth,
  readItems,
  readItemsPage,
  writeItems,
  patchItemAvailability,
  findItemDoc,
  deleteItemDoc,
  readOrders,
  writeOrders,
  readRestaurants,
  writeRestaurants,
  readSettingsMap,
  writeSettingsMap,
};
