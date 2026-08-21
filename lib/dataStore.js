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
  deliveryZones: path.join(DATA_DIR, 'delivery_zones.json'),
  offers: path.join(DATA_DIR, 'offers.json'),
  staffUsers: path.join(DATA_DIR, 'staff_users.json'),
  tables: path.join(DATA_DIR, 'tables.json'),
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
  deliveryZones: [],
  offers: [],
  staffUsers: [],
  tables: [],
  shiftSessions: [],
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
  const deliveryZones = loadJson(FILES.deliveryZones, []);
  const offers = loadJson(FILES.offers, []);
  const staffUsers = loadJson(FILES.staffUsers, []);
  const tables = loadJson(FILES.tables, []);
  const settings = migrateSettingsShape(loadJson(FILES.settings, {}));

  memory.menuItems = Array.isArray(menuItems)
    ? menuItems.map((item) => ensureRestaurantId(item))
    : [];
  memory.orders = Array.isArray(orders)
    ? orders.map((order) => ensureRestaurantId(order))
    : [];
  memory.restaurants = Array.isArray(restaurants) ? restaurants : [];
  memory.deliveryZones = Array.isArray(deliveryZones)
    ? deliveryZones.map((zone) => ensureRestaurantId(zone))
    : [];
  memory.offers = Array.isArray(offers)
    ? offers.map((offer) => ensureRestaurantId(offer))
    : [];
  memory.staffUsers = Array.isArray(staffUsers)
    ? staffUsers.map((user) => ensureRestaurantId(user))
    : [];
  memory.tables = Array.isArray(tables)
    ? tables.map((table) => ensureRestaurantId(table))
    : [];
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
    case 'delivery_zones':
      memory.deliveryZones = data;
      if (!IS_VERCEL) writeJson(FILES.deliveryZones, data);
      break;
    case 'offers':
      memory.offers = data;
      if (!IS_VERCEL) writeJson(FILES.offers, data);
      break;
    case 'staff_users':
      memory.staffUsers = data;
      if (!IS_VERCEL) writeJson(FILES.staffUsers, data);
      break;
    case 'dining_tables':
      memory.tables = data;
      if (!IS_VERCEL) writeJson(FILES.tables, data);
      break;
    case 'settings':
      memory.settings = data;
      if (!IS_VERCEL) writeJson(FILES.settings, data);
      break;
    case 'shift_sessions':
      memory.shiftSessions = data;
      break;
    default:
      break;
  }
}

async function persistAllToMongo() {
  await writeDoc('menu_items', memory.menuItems);
  await writeDoc('orders', memory.orders);
  await writeDoc('restaurants', memory.restaurants);
  await writeDoc('delivery_zones', memory.deliveryZones);
  await writeDoc('offers', memory.offers);
  await writeDoc('staff_users', memory.staffUsers);
  await writeDoc('dining_tables', memory.tables);
  await writeDoc('shift_sessions', memory.shiftSessions || []);
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
  originalPrice: 1,
  original_price: 1,
  image_url: 1,
  imageUrl: 1,
  is_available: 1,
  isAvailable: 1,
  display_order: 1,
  displayOrder: 1,
  options: 1,
  linkedItemIds: 1,
  linked_item_ids: 1,
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
    ...(Number.isFinite(Number(clean.originalPrice ?? clean.original_price)) &&
    Number(clean.originalPrice ?? clean.original_price) >
      (Number(clean.price) || 0) + 0.0005
      ? {
          originalPrice: Number(clean.originalPrice ?? clean.original_price),
          original_price: Number(clean.originalPrice ?? clean.original_price),
        }
      : {}),
    image_url: clean.image_url || '',
    is_available: clean.is_available ?? clean.isAvailable ?? 1,
    display_order: clean.display_order ?? clean.displayOrder ?? 0,
    ...(Array.isArray(clean.options) && clean.options.length
      ? { options: clean.options }
      : {}),
    ...(Array.isArray(clean.linkedItemIds) && clean.linkedItemIds.length
      ? { linkedItemIds: clean.linkedItemIds, linked_item_ids: clean.linkedItemIds }
      : Array.isArray(clean.linked_item_ids) && clean.linked_item_ids.length
        ? { linkedItemIds: clean.linked_item_ids, linked_item_ids: clean.linked_item_ids }
        : {}),
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
  const take = Math.min(Math.max(Number(limit) || 40, 1), 250);

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
        const storedZones = await readDoc('delivery_zones', null);
        if (Array.isArray(storedZones)) {
          memory.deliveryZones = storedZones.map((zone) => ensureRestaurantId(zone));
        } else if (memory.deliveryZones.length) {
          await writeDoc('delivery_zones', memory.deliveryZones);
        }
        const storedOffers = await readDoc('offers', null);
        if (Array.isArray(storedOffers)) {
          memory.offers = storedOffers.map((offer) => ensureRestaurantId(offer));
        } else if (memory.offers.length) {
          await writeDoc('offers', memory.offers);
        }
        const storedStaff = await readDoc('staff_users', null);
        if (Array.isArray(storedStaff)) {
          memory.staffUsers = storedStaff.map((user) => ensureRestaurantId(user));
        } else if (memory.staffUsers.length) {
          await writeDoc('staff_users', memory.staffUsers);
        }
        const storedTables = await readDoc('dining_tables', null);
        if (Array.isArray(storedTables)) {
          memory.tables = storedTables.map((table) => ensureRestaurantId(table));
        } else if (memory.tables.length) {
          await writeDoc('dining_tables', memory.tables);
        }
        const storedShifts = await readDoc('shift_sessions', null);
        if (Array.isArray(storedShifts)) {
          memory.shiftSessions = storedShifts.map((shift) => ensureRestaurantId(shift));
        } else if ((memory.shiftSessions || []).length) {
          await writeDoc('shift_sessions', memory.shiftSessions);
        }
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
      try {
        delete require.cache[require.resolve('../data/delivery_zones.json')];
        const freshZones = require('../data/delivery_zones.json');
        if (Array.isArray(freshZones) && memory.deliveryZones.length === 0) {
          memory.deliveryZones = freshZones.map((zone) => ensureRestaurantId(zone));
        }
      } catch (_) {}
      try {
        delete require.cache[require.resolve('../data/offers.json')];
        const freshOffers = require('../data/offers.json');
        if (Array.isArray(freshOffers) && memory.offers.length === 0) {
          memory.offers = freshOffers.map((offer) => ensureRestaurantId(offer));
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

async function readDeliveryZones() {
  if (usesMongo()) {
    const zones = await readDoc('delivery_zones', null);
    if (Array.isArray(zones)) {
      memory.deliveryZones = zones.map((zone) => ensureRestaurantId(zone));
      return memory.deliveryZones;
    }
    const seeded = Array.isArray(memory.deliveryZones) ? memory.deliveryZones : [];
    if (seeded.length) {
      await writeDoc('delivery_zones', seeded);
    }
    return seeded.map((zone) => ensureRestaurantId(zone));
  }

  if (IS_VERCEL) {
    return memory.deliveryZones.map((zone) => ensureRestaurantId(zone));
  }

  const zones = loadJson(FILES.deliveryZones, memory.deliveryZones);
  memory.deliveryZones = Array.isArray(zones)
    ? zones.map((zone) => ensureRestaurantId(zone))
    : [];
  return memory.deliveryZones;
}

async function writeDeliveryZones(zones) {
  const normalized = (Array.isArray(zones) ? zones : []).map((zone) =>
    ensureRestaurantId(zone),
  );
  memory.deliveryZones = normalized;
  await writeDoc('delivery_zones', normalized);
  return normalized;
}

async function readOffers() {
  if (usesMongo()) {
    const offers = await readDoc('offers', null);
    if (Array.isArray(offers)) {
      memory.offers = offers.map((offer) => ensureRestaurantId(offer));
      return memory.offers;
    }
    const seeded = Array.isArray(memory.offers) ? memory.offers : [];
    if (seeded.length) {
      await writeDoc('offers', seeded);
    }
    return seeded.map((offer) => ensureRestaurantId(offer));
  }

  if (IS_VERCEL) {
    return memory.offers.map((offer) => ensureRestaurantId(offer));
  }

  const offers = loadJson(FILES.offers, memory.offers);
  memory.offers = Array.isArray(offers)
    ? offers.map((offer) => ensureRestaurantId(offer))
    : [];
  return memory.offers;
}

async function writeOffers(offers) {
  const normalized = (Array.isArray(offers) ? offers : []).map((offer) =>
    ensureRestaurantId(offer),
  );
  memory.offers = normalized;
  await writeDoc('offers', normalized);
  return normalized;
}

async function readStaffUsers() {
  if (usesMongo()) {
    const users = await readDoc('staff_users', null);
    if (Array.isArray(users)) {
      memory.staffUsers = users.map((user) => ensureRestaurantId(user));
      return memory.staffUsers;
    }
    const seeded = Array.isArray(memory.staffUsers) ? memory.staffUsers : [];
    if (seeded.length) {
      await writeDoc('staff_users', seeded);
    }
    return seeded.map((user) => ensureRestaurantId(user));
  }

  if (IS_VERCEL) {
    return (memory.staffUsers || []).map((user) => ensureRestaurantId(user));
  }

  const users = loadJson(FILES.staffUsers, memory.staffUsers);
  memory.staffUsers = Array.isArray(users)
    ? users.map((user) => ensureRestaurantId(user))
    : [];
  return memory.staffUsers;
}

async function writeStaffUsers(users) {
  const normalized = (Array.isArray(users) ? users : []).map((user) =>
    ensureRestaurantId(user),
  );
  memory.staffUsers = normalized;
  await writeDoc('staff_users', normalized);
  return normalized;
}

async function readTables() {
  if (usesMongo()) {
    const tables = await readDoc('dining_tables', null);
    if (Array.isArray(tables)) {
      memory.tables = tables.map((table) => ensureRestaurantId(table));
      return memory.tables;
    }
    const seeded = Array.isArray(memory.tables) ? memory.tables : [];
    if (seeded.length) {
      await writeDoc('dining_tables', seeded);
    }
    return seeded.map((table) => ensureRestaurantId(table));
  }

  if (IS_VERCEL) {
    return (memory.tables || []).map((table) => ensureRestaurantId(table));
  }

  const tables = loadJson(FILES.tables, memory.tables);
  memory.tables = Array.isArray(tables)
    ? tables.map((table) => ensureRestaurantId(table))
    : [];
  return memory.tables;
}

async function writeTables(tables) {
  const normalized = (Array.isArray(tables) ? tables : []).map((table) =>
    ensureRestaurantId(table),
  );
  memory.tables = normalized;
  await writeDoc('dining_tables', normalized);
  return normalized;
}

async function readShiftSessions() {
  if (usesMongo()) {
    const shifts = await readDoc('shift_sessions', null);
    if (Array.isArray(shifts)) {
      memory.shiftSessions = shifts.map((shift) => ensureRestaurantId(shift));
      return memory.shiftSessions;
    }
    const seeded = Array.isArray(memory.shiftSessions) ? memory.shiftSessions : [];
    if (seeded.length) {
      await writeDoc('shift_sessions', seeded);
    }
    return seeded.map((shift) => ensureRestaurantId(shift));
  }

  if (IS_VERCEL) {
    return (memory.shiftSessions || []).map((shift) => ensureRestaurantId(shift));
  }

  return (memory.shiftSessions || []).map((shift) => ensureRestaurantId(shift));
}

async function writeShiftSessions(shifts) {
  const normalized = (Array.isArray(shifts) ? shifts : []).map((shift) =>
    ensureRestaurantId(shift),
  );
  memory.shiftSessions = normalized;
  await writeDoc('shift_sessions', normalized);
  return normalized;
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

function itemIdFilters(itemId, restaurantId) {
  const raw = String(itemId);
  const n = Number(itemId);
  const ids = [raw];
  if (Number.isFinite(n)) ids.unshift(n);
  const uniqueIds = [...new Set(ids)];
  const filters = uniqueIds.map((id) => ({ id }));
  if (restaurantId) {
    const rid = String(restaurantId);
    const scoped = filters.map((filter) => ({ ...filter, restaurant_id: rid }));
    scoped.push({ _id: `${rid}:${raw}` });
    if (Number.isFinite(n)) scoped.push({ _id: `${rid}:${n}` });
    return scoped;
  }
  filters.push({ _id: raw });
  return filters;
}

function blobItemMatchesId(item, itemId) {
  return String(item?.id) === String(itemId) || String(item?.talabat_id) === String(itemId);
}

async function findItemDoc(itemId, restaurantId) {
  const col = await ensureItemsCollection();
  if (!col) return null;
  let existing = await col.findOne({ $or: itemIdFilters(itemId, restaurantId) });
  if (!existing && restaurantId) {
    existing = await col.findOne({ $or: itemIdFilters(itemId) });
  }
  if (!existing) return null;
  const { _id, ...item } = existing;
  return sanitizeItem(item);
}

async function replaceItemDoc(item) {
  const col = await ensureItemsCollection();
  if (!col) return sanitizeItem(item);
  const next = sanitizeItem(ensureRestaurantId(item));
  const doc = itemToDoc(next);
  await col.replaceOne({ _id: doc._id }, doc, { upsert: true });
  return next;
}

async function patchItemAvailability(itemId, isAvailable, restaurantId) {
  const flag = isAvailable === false || isAvailable === 0 ? 0 : 1;
  const col = await ensureItemsCollection();
  if (!col) return null;
  const existing = await col.findOne({ $or: itemIdFilters(itemId, restaurantId) })
    || (!restaurantId ? null : await col.findOne({ $or: itemIdFilters(itemId) }));
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

async function deleteItemDoc(itemId, restaurantId) {
  const col = await ensureItemsCollection();
  if (!col) return;
  const result = await col.deleteMany({ $or: itemIdFilters(itemId, restaurantId) });
  if ((!result || result.deletedCount === 0) && restaurantId) {
    await col.deleteMany({ $or: itemIdFilters(itemId) });
  }
}

async function patchItemInBlob(itemId, restaurantId, mutator) {
  const items = await readItems();
  const index = items.findIndex((item) => {
    if (
      restaurantId &&
      String(item.restaurant_id || item.restaurantId) !== String(restaurantId)
    ) {
      return false;
    }
    return blobItemMatchesId(item, itemId);
  });
  if (index === -1) return false;
  const nextItem = mutator(items[index]);
  if (nextItem == null) {
    items.splice(index, 1);
  } else {
    items[index] = nextItem;
  }
  memory.menuItems = items;
  itemsMemoryAt = Date.now();
  await writeDoc('menu_items', items);
  return true;
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
  replaceItemDoc,
  deleteItemDoc,
  patchItemInBlob,
  readOrders,
  writeOrders,
  readRestaurants,
  writeRestaurants,
  readDeliveryZones,
  writeDeliveryZones,
  readOffers,
  writeOffers,
  readStaffUsers,
  writeStaffUsers,
  readTables,
  writeTables,
  readShiftSessions,
  writeShiftSessions,
  readSettingsMap,
  writeSettingsMap,
};
