const fs = require('fs');
const path = require('path');
const { ensureRestaurantId, migrateSettingsShape, defaultSettingsPayload } = require('./tenantStore');
const { DEFAULT_RESTAURANT_ID } = require('./adminAuth');
const { normalizeDriver } = require('./deliveryDispatch');
const {
  isDynamicMenuSortingEnabled,
  sortCatalogItems,
  buildSalesContext,
} = require('./dynamicMenuSort');
const { buildCategoryRankMap } = require('./menuCategories');

let MongoClient = null;
try {
  ({ MongoClient } = require('mongodb'));
} catch {
  MongoClient = null;
}

const mysqlStore = require('./mysqlStore');

const DATA_DIR = path.join(__dirname, '..', 'data');
const FILES = {
  menuItems: path.join(DATA_DIR, 'menu_items.json'),
  orders: path.join(DATA_DIR, 'orders.json'),
  settings: path.join(DATA_DIR, 'settings.json'),
  signupRequests: path.join(DATA_DIR, 'signup_requests.json'),
  drivers: path.join(DATA_DIR, 'drivers.json'),
  deliveryRequests: path.join(DATA_DIR, 'delivery_requests.json'),
  restaurants: path.join(DATA_DIR, 'restaurants.json'),
  deliveryZones: path.join(DATA_DIR, 'delivery_zones.json'),
  kitchens: path.join(DATA_DIR, 'kitchens.json'),
  menuCategories: path.join(DATA_DIR, 'menu_categories.json'),
  reviews: path.join(DATA_DIR, 'reviews.json'),
  expenses: path.join(DATA_DIR, 'expenses.json'),
  offers: path.join(DATA_DIR, 'offers.json'),
  staffUsers: path.join(DATA_DIR, 'staff_users.json'),
  tables: path.join(DATA_DIR, 'tables.json'),
  customers: path.join(DATA_DIR, 'customers.json'),
  auditEvents: path.join(DATA_DIR, 'audit_events.json'),
  upsellEvents: path.join(DATA_DIR, 'upsell_events.json'),
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
let mysqlReady = false;
let mysqlDisabled = false;
let mysqlInitPromise;
let mysqlErrorMessage = '';
let dataStoreHydrated = false;
let dataStoreHydratedAt = 0;
const DATASTORE_HYDRATE_TTL_MS = 60000;
const DOC_MEMORY_TTL_MS = 20000;
let restaurantsMemoryAt = 0;
let settingsMemoryAt = 0;
let tablesMemoryAt = 0;
let itemsCollectionHasDocs = false;

const memory = {
  menuItems: [],
  orders: [],
  restaurants: [],
  deliveryZones: [],
  kitchens: [],
  menuCategories: [],
  reviews: [],
  expenses: [],
  offers: [],
  staffUsers: [],
  tables: [],
  shiftSessions: [],
  signupRequests: [],
  drivers: [],
  deliveryRequests: [],
  settings: migrateSettingsShape({}),
  storeAssets: {},
  customers: [],
  auditEvents: [],
  upsellEvents: [],
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
  const kitchens = loadJson(FILES.kitchens, []);
  const reviews = loadJson(FILES.reviews, []);
  const expenses = loadJson(FILES.expenses, []);
  const offers = loadJson(FILES.offers, []);
  const staffUsers = loadJson(FILES.staffUsers, []);
  const tables = loadJson(FILES.tables, []);
  const signupRequests = loadJson(FILES.signupRequests, []);
  const drivers = loadJson(FILES.drivers, []);
  const deliveryRequests = loadJson(FILES.deliveryRequests, []);
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
  memory.kitchens = Array.isArray(kitchens)
    ? kitchens.map((kitchen) => ensureRestaurantId(kitchen))
    : [];
  const menuCategories = loadJson(FILES.menuCategories, []);
  memory.menuCategories = Array.isArray(menuCategories)
    ? menuCategories.map((entry) => ensureRestaurantId(entry))
    : [];
  memory.reviews = Array.isArray(reviews)
    ? reviews.map((review) => ensureRestaurantId(review))
    : [];
  memory.expenses = Array.isArray(expenses)
    ? expenses.map((expense) => ensureRestaurantId(expense))
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
  memory.signupRequests = Array.isArray(signupRequests) ? signupRequests : [];
  memory.drivers = Array.isArray(drivers)
    ? drivers.map((row) => normalizeDriver(row))
    : [];
  memory.deliveryRequests = Array.isArray(deliveryRequests)
    ? deliveryRequests.map((row) => ensureRestaurantId(row))
    : [];
  const customers = loadJson(FILES.customers, []);
  const auditEvents = loadJson(FILES.auditEvents, []);
  const upsellEvents = loadJson(FILES.upsellEvents, []);
  memory.customers = Array.isArray(customers)
    ? customers.map((row) => ensureRestaurantId(row))
    : [];
  memory.auditEvents = Array.isArray(auditEvents) ? auditEvents : [];
  memory.upsellEvents = Array.isArray(upsellEvents) ? upsellEvents : [];
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
  const content = JSON.stringify(value, null, 2);
  for (let attempt = 0; ; attempt += 1) {
    try {
      fs.writeFileSync(filePath, content, 'utf8');
      return;
    } catch (error) {
      const retryable = ['EBUSY', 'EACCES', 'EPERM', 'UNKNOWN'].includes(
        String(error?.code || '').toUpperCase(),
      );
      if (!retryable || attempt >= 10) throw error;
      Atomics.wait(
        new Int32Array(new SharedArrayBuffer(4)),
        0,
        0,
        100 * (attempt + 1),
      );
    }
  }
}

function usesMysql() {
  return mysqlStore.isConfigured() && !mysqlDisabled;
}

function usesMongo() {
  if (usesMysql()) return false;
  return Boolean(MONGODB_URI) && Boolean(MongoClient) && !mongoDisabled;
}

function usesPersistent() {
  return usesMysql() || usesMongo();
}

function persistentReady() {
  return (usesMysql() && mysqlReady) || (usesMongo() && mongoReady);
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

async function initMysql() {
  if (!usesMysql()) return false;
  if (mysqlReady) return true;
  if (mysqlInitPromise) return mysqlInitPromise;

  mysqlInitPromise = (async () => {
    try {
      await mysqlStore.connect();
      mysqlReady = true;
      mysqlErrorMessage = '';
      const existing = await mysqlStore.countDocs();
      if (existing === 0) {
        seedFromFiles();
        await persistAllToMongo();
      }
      return true;
    } catch (error) {
      mysqlDisabled = true;
      mysqlReady = false;
      mysqlInitPromise = null;
      mysqlErrorMessage = String(error?.message || error);
      console.error(
        '[dataStore] MySQL unavailable, using JSON/memory fallback:',
        mysqlErrorMessage,
      );
      return false;
    }
  })();

  return mysqlInitPromise;
}

async function initPersistent() {
  if (usesMysql()) return initMysql();
  if (usesMongo()) return initMongo();
  return false;
}

async function readDoc(id, fallback) {
  if (usesMysql()) {
    const ready = await initMysql();
    if (!ready) return fallback;
    const stored = await mysqlStore.getDoc(id);
    return stored === undefined ? fallback : stored;
  }

  if (usesMongo()) {
    const ready = await initMongo();
    if (!ready || !mongoDb) return fallback;
    const doc = await mongoDb.collection(COLLECTION).findOne({ _id: id });
    return doc?.data ?? fallback;
  }

  return fallback;
}

async function writeDoc(id, data) {
  if (usesMysql()) {
    const ready = await initMysql();
    if (ready) {
      await mysqlStore.setDoc(id, data);
      memoryWrite(id, data);
      return;
    }
  }

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
    case 'kitchens':
      memory.kitchens = data;
      if (!IS_VERCEL) writeJson(FILES.kitchens, data);
      break;
    case 'menu_categories':
      memory.menuCategories = data;
      if (!IS_VERCEL) writeJson(FILES.menuCategories, data);
      break;
    case 'reviews':
      memory.reviews = data;
      if (!IS_VERCEL) writeJson(FILES.reviews, data);
      break;
    case 'expenses':
      memory.expenses = data;
      if (!IS_VERCEL) writeJson(FILES.expenses, data);
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
    case 'signup_requests':
      memory.signupRequests = data;
      if (!IS_VERCEL) writeJson(FILES.signupRequests, data);
      break;
    case 'drivers':
      memory.drivers = data;
      if (!IS_VERCEL) writeJson(FILES.drivers, data);
      break;
    case 'delivery_requests':
      memory.deliveryRequests = data;
      if (!IS_VERCEL) writeJson(FILES.deliveryRequests, data);
      break;
    case 'settings':
      memory.settings = data;
      if (!IS_VERCEL) writeJson(FILES.settings, data);
      break;
    case 'store_assets':
      memory.storeAssets = data;
      break;
    case 'shift_sessions':
      memory.shiftSessions = data;
      break;
    case 'customers':
      memory.customers = data;
      if (!IS_VERCEL && FILES.customers) writeJson(FILES.customers, data);
      break;
    case 'audit_events':
      memory.auditEvents = data;
      break;
    case 'upsell_events':
      memory.upsellEvents = data;
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
  await writeDoc('kitchens', memory.kitchens || []);
  await writeDoc('menu_categories', memory.menuCategories || []);
  await writeDoc('reviews', memory.reviews || []);
  await writeDoc('expenses', memory.expenses || []);
  await writeDoc('offers', memory.offers);
  await writeDoc('staff_users', memory.staffUsers);
  await writeDoc('dining_tables', memory.tables);
  await writeDoc('shift_sessions', memory.shiftSessions || []);
  await writeDoc('signup_requests', memory.signupRequests || []);
  await writeDoc('drivers', memory.drivers || []);
  await writeDoc('delivery_requests', memory.deliveryRequests || []);
  await writeDoc('settings', memory.settings);
  await writeDoc('customers', memory.customers || []);
  await writeDoc('audit_events', memory.auditEvents || []);
  await writeDoc('upsell_events', memory.upsellEvents || []);
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
  videoUrlWebm: 1,
  video_url_webm: 1,
  videoUrlMp4: 1,
  video_url_mp4: 1,
  isStory: 1,
  is_story: 1,
  is_available: 1,
  isAvailable: 1,
  showOnWebsite: 1,
  show_on_website: 1,
  posOnly: 1,
  pos_only: 1,
  display_order: 1,
  displayOrder: 1,
  costPrice: 1,
  cost_price: 1,
  options: 1,
  linkedItemIds: 1,
  linked_item_ids: 1,
};

let itemsColReady = false;
let itemsColPromise;

function itemShowsOnWebsite(item) {
  if (!item || typeof item !== 'object') return true;
  if (
    item.posOnly === true ||
    item.pos_only === true ||
    item.posOnly === 1 ||
    item.pos_only === 1
  ) {
    return false;
  }
  const value = item.showOnWebsite ?? item.show_on_website;
  if (value === false || value === 0 || value === '0' || value === 'false') {
    return false;
  }
  return true;
}

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
    videoUrlWebm: String(item.videoUrlWebm || item.video_url_webm || '').trim(),
    video_url_webm: String(item.videoUrlWebm || item.video_url_webm || '').trim(),
    videoUrlMp4: String(item.videoUrlMp4 || item.video_url_mp4 || '').trim(),
    video_url_mp4: String(item.videoUrlMp4 || item.video_url_mp4 || '').trim(),
    isStory:
      item.isStory === true ||
      item.is_story === true ||
      item.isStory === 1 ||
      item.is_story === 1,
    is_story:
      item.isStory === true ||
      item.is_story === true ||
      item.isStory === 1 ||
      item.is_story === 1,
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
    ...(Number.isFinite(Number(clean.costPrice ?? clean.cost_price)) &&
    Number(clean.costPrice ?? clean.cost_price) >= 0
      ? {
          costPrice: Number(clean.costPrice ?? clean.cost_price),
          cost_price: Number(clean.costPrice ?? clean.cost_price),
        }
      : {}),
    ...(Number.isFinite(Number(clean.originalPrice ?? clean.original_price)) &&
    Number(clean.originalPrice ?? clean.original_price) >
      (Number(clean.price) || 0) + 0.0005
      ? {
          originalPrice: Number(clean.originalPrice ?? clean.original_price),
          original_price: Number(clean.originalPrice ?? clean.original_price),
        }
      : {}),
    image_url: clean.image_url || '',
    videoUrlWebm: clean.videoUrlWebm || '',
    video_url_webm: clean.videoUrlWebm || '',
    videoUrlMp4: clean.videoUrlMp4 || '',
    video_url_mp4: clean.videoUrlMp4 || '',
    isStory: clean.isStory === true,
    is_story: clean.isStory === true,
    is_available: clean.is_available ?? clean.isAvailable ?? 1,
    showOnWebsite: itemShowsOnWebsite(clean),
    show_on_website: itemShowsOnWebsite(clean),
    display_order: clean.display_order ?? clean.displayOrder ?? 0,
    ...(Number.isFinite(Number(clean.orderCount ?? clean.order_count))
      ? {
          orderCount: Number(clean.orderCount ?? clean.order_count),
          order_count: Number(clean.orderCount ?? clean.order_count),
        }
      : {}),
    ...(clean.engineeringQuadrant || clean.engineering_quadrant
      ? {
          engineeringQuadrant: clean.engineeringQuadrant || clean.engineering_quadrant,
          engineering_quadrant: clean.engineeringQuadrant || clean.engineering_quadrant,
        }
      : {}),
    ...(clean.catalogBadge || clean.catalog_badge
      ? {
          catalogBadge: clean.catalogBadge || clean.catalog_badge,
          catalog_badge: clean.catalogBadge || clean.catalog_badge,
        }
      : {}),
    ...(Number.isFinite(Number(clean.profitMargin ?? clean.profit_margin))
      ? {
          profitMargin: Number(clean.profitMargin ?? clean.profit_margin),
          profit_margin: Number(clean.profitMargin ?? clean.profit_margin),
        }
      : {}),
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

async function catalogSettingsFor(restaurantId) {
  try {
    const map = await readSettingsMap();
    const id = String(restaurantId || DEFAULT_RESTAURANT_ID);
    const row = map?.byRestaurant?.[id];
    return {
      ...defaultSettingsPayload(),
      ...(row && typeof row === 'object' ? row : {}),
    };
  } catch (_) {
    return defaultSettingsPayload();
  }
}

async function readItemsPage({
  restaurantId,
  offset = 0,
  limit = 40,
  lite = true,
  websiteOnly = false,
} = {}) {
  const skip = Math.max(Number(offset) || 0, 0);
  const take = Math.min(Math.max(Number(limit) || 40, 1), 250);
  const settings = await catalogSettingsFor(restaurantId);
  const dynamicSort = isDynamicMenuSortingEnabled(settings);
  let categoryRanks = null;
  if (!dynamicSort && restaurantId) {
    try {
      const categories = (await readMenuCategories()).filter(
        (entry) =>
          String(entry.restaurant_id || entry.restaurantId) === String(restaurantId),
      );
      categoryRanks = buildCategoryRankMap(categories);
    } catch (_) {
      categoryRanks = null;
    }
  }

  if (usesMongo()) {
    try {
      const col = await ensureItemsCollection();
      if (col) {
        const existing = itemsCollectionHasDocs
          ? 1
          : await col.estimatedDocumentCount();
        if (existing === 0) {
          migrateItemsCollection(col).catch(() => {});
        } else {
          itemsCollectionHasDocs = true;
          const filter = restaurantId
            ? { restaurant_id: String(restaurantId) }
            : {};
          const query = col.find(filter, {
            projection: lite ? LITE_ITEM_PROJECTION : { _id: 0 },
          });
          itemsCollectionHasDocs = true;
          // Manual category+item order needs full list when ranks exist.
          if (dynamicSort || websiteOnly || (categoryRanks && categoryRanks.size > 0)) {
            const docs = await query.toArray();
            const sales = dynamicSort
              ? buildSalesContext(docs, await readOrders(), restaurantId)
              : null;
            const ordered = sortCatalogItems(
              docs,
              settings,
              new Date(),
              sales,
              categoryRanks,
            );
            const visible = websiteOnly
              ? ordered.filter(itemShowsOnWebsite)
              : ordered;
            const mapped = visible
              .slice(skip, skip + take)
              .map((item) => (lite ? toLiteItem(item) : sanitizeItem(item)));
            return {
              items: mapped,
              total: visible.length,
              limit: take,
              offset: skip,
            };
          }
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

    if (!dynamicSort && !websiteOnly && !(categoryRanks && categoryRanks.size > 0)) {
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
  }

  let items = await readItems();
  if (restaurantId) {
    items = items.filter(
      (item) =>
        String(item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID) ===
        String(restaurantId),
    );
  }
  items = sortCatalogItems(
    items,
    settings,
    new Date(),
    dynamicSort ? buildSalesContext(items, await readOrders(), restaurantId) : null,
    categoryRanks,
  );
  if (websiteOnly) {
    items = items.filter(itemShowsOnWebsite);
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
  if (mysqlReady) {
    return {
      ok: true,
      storage: 'mysql',
      persistent: true,
    };
  }

  if (mongoReady) {
    return {
      ok: true,
      storage: 'mongodb',
      persistent: true,
    };
  }

  const usingMysqlFallback = mysqlStore.isConfigured() && (mysqlDisabled || !mysqlStore.isConfigured());
  const usingMongoFallback = Boolean(MONGODB_URI) && (mongoDisabled || !MongoClient);
  return {
    ok: true,
    storage: IS_VERCEL ? 'memory' : 'json',
    persistent: !IS_VERCEL,
    persistenceMessage: mysqlErrorMessage
      ? `MySQL unavailable (${mysqlErrorMessage}); using JSON/memory fallback`
      : usingMongoFallback
        ? mongoErrorMessage
          ? `MongoDB unavailable (${mongoErrorMessage}); using JSON/memory fallback`
          : 'MongoDB driver unavailable; using JSON/memory fallback'
        : usingMysqlFallback && mysqlErrorMessage
          ? mysqlErrorMessage
          : undefined,
  };
}

async function initDataStore() {
  try {
    if (
      usesPersistent() &&
      persistentReady() &&
      dataStoreHydrated &&
      Date.now() - dataStoreHydratedAt < DATASTORE_HYDRATE_TTL_MS
    ) {
      return;
    }

    if (!dataStoreHydrated) {
      seedFromFiles();
    }

    if (usesPersistent()) {
      const ready = await initPersistent();
      if (ready && persistentReady()) {
        if (
          dataStoreHydrated &&
          Date.now() - dataStoreHydratedAt < DATASTORE_HYDRATE_TTL_MS
        ) {
          return;
        }
        const [
          restaurants,
          settings,
          storedZones,
          storedKitchens,
          storedMenuCategories,
          storedReviews,
          storedExpenses,
          storedOffers,
          storedStaff,
          storedTables,
          storedShifts,
          storedSignups,
          storedDrivers,
          storedDispatch,
        ] = await Promise.all([
          readDoc('restaurants', memory.restaurants),
          readDoc('settings', memory.settings),
          readDoc('delivery_zones', null),
          readDoc('kitchens', null),
          readDoc('menu_categories', null),
          readDoc('reviews', null),
          readDoc('expenses', null),
          readDoc('offers', null),
          readDoc('staff_users', null),
          readDoc('dining_tables', null),
          readDoc('shift_sessions', null),
          readDoc('signup_requests', null),
          readDoc('drivers', null),
          readDoc('delivery_requests', null),
        ]);
        memory.restaurants = Array.isArray(restaurants) ? restaurants : memory.restaurants;
        restaurantsMemoryAt = Date.now();
        memory.settings = migrateSettingsShape(settings);
        settingsMemoryAt = Date.now();
        if (Array.isArray(storedZones)) {
          memory.deliveryZones = storedZones.map((zone) => ensureRestaurantId(zone));
        } else if (memory.deliveryZones.length) {
          await writeDoc('delivery_zones', memory.deliveryZones);
        }
        if (Array.isArray(storedKitchens)) {
          memory.kitchens = storedKitchens.map((kitchen) => ensureRestaurantId(kitchen));
        } else if ((memory.kitchens || []).length) {
          await writeDoc('kitchens', memory.kitchens);
        }
        if (Array.isArray(storedMenuCategories)) {
          memory.menuCategories = storedMenuCategories.map((entry) =>
            ensureRestaurantId(entry),
          );
        } else if ((memory.menuCategories || []).length) {
          await writeDoc('menu_categories', memory.menuCategories);
        }
        if (Array.isArray(storedReviews)) {
          memory.reviews = storedReviews.map((review) => ensureRestaurantId(review));
        } else if ((memory.reviews || []).length) {
          await writeDoc('reviews', memory.reviews);
        }
        if (Array.isArray(storedExpenses)) {
          memory.expenses = storedExpenses.map((expense) => ensureRestaurantId(expense));
        } else if ((memory.expenses || []).length) {
          await writeDoc('expenses', memory.expenses);
        }
        if (Array.isArray(storedOffers)) {
          memory.offers = storedOffers.map((offer) => ensureRestaurantId(offer));
        } else if (memory.offers.length) {
          await writeDoc('offers', memory.offers);
        }
        if (Array.isArray(storedStaff)) {
          memory.staffUsers = storedStaff.map((user) => ensureRestaurantId(user));
        } else if (memory.staffUsers.length) {
          await writeDoc('staff_users', memory.staffUsers);
        }
        if (Array.isArray(storedTables)) {
          memory.tables = storedTables.map((table) => ensureRestaurantId(table));
          tablesMemoryAt = Date.now();
        } else if (memory.tables.length) {
          await writeDoc('dining_tables', memory.tables);
        }
        if (Array.isArray(storedShifts)) {
          memory.shiftSessions = storedShifts.map((shift) => ensureRestaurantId(shift));
        } else if ((memory.shiftSessions || []).length) {
          await writeDoc('shift_sessions', memory.shiftSessions);
        }
        if (Array.isArray(storedSignups)) {
          memory.signupRequests = storedSignups;
        } else if ((memory.signupRequests || []).length) {
          await writeDoc('signup_requests', memory.signupRequests);
        }
        if (Array.isArray(storedDrivers)) {
          memory.drivers = storedDrivers.map((row) => normalizeDriver(row));
        } else if ((memory.drivers || []).length) {
          await writeDoc('drivers', memory.drivers);
        }
        if (Array.isArray(storedDispatch)) {
          memory.deliveryRequests = storedDispatch.map((row) => ensureRestaurantId(row));
        } else if ((memory.deliveryRequests || []).length) {
          await writeDoc('delivery_requests', memory.deliveryRequests);
        }
        const [storedCustomers, storedAudit, storedUpsell] = await Promise.all([
          readDoc('customers', null),
          readDoc('audit_events', null),
          readDoc('upsell_events', null),
        ]);
        if (Array.isArray(storedCustomers)) {
          memory.customers = storedCustomers.map((row) => ensureRestaurantId(row));
        } else if ((memory.customers || []).length) {
          await writeDoc('customers', memory.customers);
        }
        if (Array.isArray(storedAudit)) {
          memory.auditEvents = storedAudit;
        } else if ((memory.auditEvents || []).length) {
          await writeDoc('audit_events', memory.auditEvents);
        }
        if (Array.isArray(storedUpsell)) {
          memory.upsellEvents = storedUpsell;
        } else if ((memory.upsellEvents || []).length) {
          await writeDoc('upsell_events', memory.upsellEvents);
        }
        dataStoreHydrated = true;
        dataStoreHydratedAt = Date.now();
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
    mysqlDisabled = true;
    mysqlReady = false;
    mongoDisabled = true;
    mongoReady = false;
    mysqlErrorMessage = String(error?.message || error);
    mongoErrorMessage = mysqlErrorMessage;
    seedFromFiles();
    console.error('[dataStore] initDataStore recovered via seed:', mongoErrorMessage);
  }
}

let itemsMemoryAt = 0;
const ITEMS_MEMORY_TTL_MS = 20000;

async function readItems() {
  if (usesPersistent()) {
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

/**
 * Reorder items for one restaurant by writing display_order into the
 * menu_item_docs collection (source of truth for GET /api/items) and the blob.
 */
async function applyItemDisplayOrder(restaurantId, orderedIds) {
  const rid = String(restaurantId || '').trim();
  const ids = (Array.isArray(orderedIds) ? orderedIds : []).map(String);
  if (!rid || !ids.length) {
    return { ok: false, count: 0 };
  }

  const orderMap = new Map();
  ids.forEach((id, index) => orderMap.set(id, index));

  const col = await ensureItemsCollection();
  let scoped = [];
  if (col) {
    try {
      const docs = await col.find({ restaurant_id: rid }).toArray();
      scoped = docs.map((doc) => {
        const { _id, ...rest } = doc;
        return sanitizeItem(rest);
      });
    } catch (error) {
      console.warn('[dataStore] applyItemDisplayOrder collection read:', error?.message || error);
    }
  }
  if (!scoped.length) {
    const all = await readItems();
    scoped = all.filter(
      (item) => String(item.restaurant_id || item.restaurantId) === rid,
    );
  }

  const byId = new Map(scoped.map((item) => [String(item.id), item]));
  const nextScoped = [];
  for (const id of ids) {
    const item = byId.get(id);
    if (!item) continue;
    const displayOrder = orderMap.get(id) ?? nextScoped.length;
    nextScoped.push(
      sanitizeItem({
        ...item,
        display_order: displayOrder,
        displayOrder,
        restaurant_id: rid,
        restaurantId: rid,
      }),
    );
    byId.delete(id);
  }
  for (const leftover of byId.values()) {
    nextScoped.push(
      sanitizeItem({
        ...leftover,
        display_order: nextScoped.length,
        displayOrder: nextScoped.length,
        restaurant_id: rid,
        restaurantId: rid,
      }),
    );
  }

  if (col && nextScoped.length) {
    await col.bulkWrite(
      nextScoped.map((item) => {
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

  // Keep blob in sync for this restaurant only.
  const all = await readItems();
  const others = all.filter(
    (item) => String(item.restaurant_id || item.restaurantId) !== rid,
  );
  memory.menuItems = [...others, ...nextScoped];
  itemsMemoryAt = Date.now();
  await writeDoc('menu_items', memory.menuItems);

  return { ok: true, count: nextScoped.length };
}

async function renameItemCategory(restaurantId, fromName, toName) {
  const rid = String(restaurantId || '').trim();
  const from = String(fromName || '').trim();
  const to = String(toName || '').trim();
  if (!rid || !from || !to || from === to) return { updated: 0 };

  const col = await ensureItemsCollection();
  let updated = 0;
  if (col) {
    const result = await col.updateMany(
      {
        restaurant_id: rid,
        $or: [{ category_name: from }, { categoryName: from }],
      },
      {
        $set: {
          category_name: to,
          categoryName: to,
          category_name_ar: to,
        },
      },
    );
    updated = result?.modifiedCount || 0;
  }

  const all = await readItems();
  let blobUpdated = 0;
  const next = all.map((item) => {
    if (String(item.restaurant_id || item.restaurantId) !== rid) return item;
    const name = String(item.category_name || item.categoryName || '').trim();
    if (name !== from) return item;
    blobUpdated += 1;
    return sanitizeItem({
      ...item,
      category_name: to,
      categoryName: to,
    });
  });
  if (blobUpdated) {
    memory.menuItems = next;
    itemsMemoryAt = Date.now();
    await writeDoc('menu_items', next);
  }
  return { updated: updated || blobUpdated };
}

async function readOrders() {
  if (usesPersistent()) {
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

async function prependOrder(order, existingOrders) {
  const next = ensureRestaurantId(order);
  const current = Array.isArray(existingOrders)
    ? existingOrders.map((entry) => ensureRestaurantId(entry))
    : await readOrders();
  const orders = [next, ...current.filter((entry) => String(entry.id) !== String(next.id))];
  memory.orders = orders;

  if (usesMongo()) {
    const ready = await initMongo();
    if (ready && mongoDb) {
      try {
        await mongoDb.collection(COLLECTION).updateOne(
          { _id: 'orders' },
          {
            $push: { data: { $each: [next], $position: 0 } },
            $set: { updatedAt: new Date().toISOString() },
          },
          { upsert: true },
        );
        try {
          const { scheduleSuperAdminOrderNotify } = require('./orderNotify');
          // Await on serverless so Resend finishes before the function freezes.
          await scheduleSuperAdminOrderNotify(next, { readRestaurants });
        } catch (notifyError) {
          console.warn(
            '[dataStore] order notify skipped:',
            notifyError?.message || notifyError,
          );
        }
        return next;
      } catch (error) {
        console.warn('[dataStore] prependOrder fallback:', error?.message || error);
      }
    }
  }

  await writeDoc('orders', orders);
  try {
    const { scheduleSuperAdminOrderNotify } = require('./orderNotify');
    await scheduleSuperAdminOrderNotify(next, { readRestaurants });
  } catch (notifyError) {
    console.warn(
      '[dataStore] order notify skipped:',
      notifyError?.message || notifyError,
    );
  }
  return next;
}

async function patchOrderById(orderId, nextOrder, existingOrders) {
  const wanted = String(orderId);
  const next = ensureRestaurantId(nextOrder);
  const current = Array.isArray(existingOrders)
    ? existingOrders.map((order) => ensureRestaurantId(order))
    : await readOrders();
  const index = current.findIndex((order) => String(order.id) === wanted);
  if (index === -1) return null;
  current[index] = next;
  memory.orders = current;

  const idCandidates = [wanted, next.id, nextOrder && nextOrder.id].filter(
    (value) => value !== undefined && value !== null && value !== '',
  );
  const asNum = Number(wanted);
  if (Number.isFinite(asNum)) idCandidates.push(asNum);

  if (usesMongo()) {
    const ready = await initMongo();
    if (ready && mongoDb) {
      try {
        const result = await mongoDb.collection(COLLECTION).updateOne(
          { _id: 'orders' },
          {
            $set: {
              'data.$[ord]': next,
              updatedAt: new Date().toISOString(),
            },
          },
          { arrayFilters: [{ 'ord.id': { $in: idCandidates } }] },
        );
        if (result.modifiedCount > 0) {
          return next;
        }
      } catch (error) {
        console.warn('[dataStore] patchOrderById arrayFilter fallback:', error?.message || error);
      }
    }
  }

  await writeDoc('orders', current);
  return next;
}

async function readRestaurants() {
  if (usesPersistent()) {
    if (
      Array.isArray(memory.restaurants) &&
      memory.restaurants.length > 0 &&
      Date.now() - restaurantsMemoryAt < DOC_MEMORY_TTL_MS
    ) {
      return memory.restaurants;
    }
    const restaurants = await readDoc('restaurants', memory.restaurants);
    memory.restaurants = Array.isArray(restaurants) ? restaurants : [];
    restaurantsMemoryAt = Date.now();
    return memory.restaurants;
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
  restaurantsMemoryAt = Date.now();
  await writeDoc('restaurants', restaurants);
  return restaurants;
}

async function readDeliveryZones() {
  if (usesPersistent()) {
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

async function readKitchens() {
  if (usesPersistent()) {
    const kitchens = await readDoc('kitchens', null);
    if (Array.isArray(kitchens)) {
      memory.kitchens = kitchens.map((kitchen) => ensureRestaurantId(kitchen));
      return memory.kitchens;
    }
    const seeded = Array.isArray(memory.kitchens) ? memory.kitchens : [];
    if (seeded.length) {
      await writeDoc('kitchens', seeded);
    }
    return seeded.map((kitchen) => ensureRestaurantId(kitchen));
  }

  if (IS_VERCEL) {
    return (memory.kitchens || []).map((kitchen) => ensureRestaurantId(kitchen));
  }

  const kitchens = loadJson(FILES.kitchens, memory.kitchens);
  memory.kitchens = Array.isArray(kitchens)
    ? kitchens.map((kitchen) => ensureRestaurantId(kitchen))
    : [];
  return memory.kitchens;
}

async function writeKitchens(kitchens) {
  const normalized = (Array.isArray(kitchens) ? kitchens : []).map((kitchen) =>
    ensureRestaurantId(kitchen),
  );
  memory.kitchens = normalized;
  await writeDoc('kitchens', normalized);
  return normalized;
}

async function readMenuCategories() {
  if (usesPersistent()) {
    const rows = await readDoc('menu_categories', null);
    if (Array.isArray(rows)) {
      memory.menuCategories = rows.map((entry) => ensureRestaurantId(entry));
      return memory.menuCategories;
    }
    const seeded = Array.isArray(memory.menuCategories) ? memory.menuCategories : [];
    if (seeded.length) {
      await writeDoc('menu_categories', seeded);
    }
    return seeded.map((entry) => ensureRestaurantId(entry));
  }

  if (IS_VERCEL) {
    return (memory.menuCategories || []).map((entry) => ensureRestaurantId(entry));
  }

  const rows = loadJson(FILES.menuCategories, memory.menuCategories);
  memory.menuCategories = Array.isArray(rows)
    ? rows.map((entry) => ensureRestaurantId(entry))
    : [];
  return memory.menuCategories;
}

async function writeMenuCategories(categories) {
  const normalized = (Array.isArray(categories) ? categories : []).map((entry) =>
    ensureRestaurantId(entry),
  );
  memory.menuCategories = normalized;
  await writeDoc('menu_categories', normalized);
  return normalized;
}

async function readReviews() {
  if (usesPersistent()) {
    const reviews = await readDoc('reviews', null);
    if (Array.isArray(reviews)) {
      memory.reviews = reviews.map((review) => ensureRestaurantId(review));
      return memory.reviews;
    }
    const seeded = Array.isArray(memory.reviews) ? memory.reviews : [];
    if (seeded.length) {
      await writeDoc('reviews', seeded);
    }
    return seeded.map((review) => ensureRestaurantId(review));
  }

  if (IS_VERCEL) {
    return (memory.reviews || []).map((review) => ensureRestaurantId(review));
  }

  const reviews = loadJson(FILES.reviews, memory.reviews);
  memory.reviews = Array.isArray(reviews)
    ? reviews.map((review) => ensureRestaurantId(review))
    : [];
  return memory.reviews;
}

async function writeReviews(reviews) {
  const normalized = (Array.isArray(reviews) ? reviews : []).map((review) =>
    ensureRestaurantId(review),
  );
  memory.reviews = normalized;
  await writeDoc('reviews', normalized);
  return normalized;
}

async function readExpenses() {
  if (usesPersistent()) {
    const expenses = await readDoc('expenses', null);
    if (Array.isArray(expenses)) {
      memory.expenses = expenses.map((expense) => ensureRestaurantId(expense));
      return memory.expenses;
    }
    const seeded = Array.isArray(memory.expenses) ? memory.expenses : [];
    if (seeded.length) {
      await writeDoc('expenses', seeded);
    }
    return seeded.map((expense) => ensureRestaurantId(expense));
  }

  if (IS_VERCEL) {
    return (memory.expenses || []).map((expense) => ensureRestaurantId(expense));
  }

  const expenses = loadJson(FILES.expenses, memory.expenses);
  memory.expenses = Array.isArray(expenses)
    ? expenses.map((expense) => ensureRestaurantId(expense))
    : [];
  return memory.expenses;
}

async function writeExpenses(expenses) {
  const normalized = (Array.isArray(expenses) ? expenses : []).map((expense) =>
    ensureRestaurantId(expense),
  );
  memory.expenses = normalized;
  await writeDoc('expenses', normalized);
  return normalized;
}

async function readOffers() {
  if (usesPersistent()) {
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
  if (usesPersistent()) {
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
  if (usesPersistent()) {
    if (
      Array.isArray(memory.tables) &&
      memory.tables.length > 0 &&
      Date.now() - tablesMemoryAt < DOC_MEMORY_TTL_MS
    ) {
      return memory.tables;
    }
    const tables = await readDoc('dining_tables', null);
    if (Array.isArray(tables)) {
      memory.tables = tables.map((table) => ensureRestaurantId(table));
      tablesMemoryAt = Date.now();
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
  tablesMemoryAt = Date.now();
  await writeDoc('dining_tables', normalized);
  return normalized;
}

async function readShiftSessions() {
  if (usesPersistent()) {
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

async function readSignupRequests() {
  if (usesPersistent()) {
    const stored = await readDoc('signup_requests', null);
    if (Array.isArray(stored)) {
      memory.signupRequests = stored;
      return memory.signupRequests;
    }
    const seeded = Array.isArray(memory.signupRequests) ? memory.signupRequests : [];
    if (seeded.length) {
      await writeDoc('signup_requests', seeded);
    }
    return seeded;
  }
  if (IS_VERCEL) {
    return Array.isArray(memory.signupRequests) ? memory.signupRequests : [];
  }
  memory.signupRequests = loadJson(FILES.signupRequests, memory.signupRequests || []);
  return Array.isArray(memory.signupRequests) ? memory.signupRequests : [];
}

async function writeSignupRequests(requests) {
  const normalized = Array.isArray(requests) ? requests : [];
  memory.signupRequests = normalized;
  await writeDoc('signup_requests', normalized);
  return normalized;
}

async function readDrivers() {
  if (usesPersistent()) {
    const stored = await readDoc('drivers', null);
    if (Array.isArray(stored)) {
      memory.drivers = stored.map((row) => normalizeDriver(row));
      return memory.drivers;
    }
    const seeded = Array.isArray(memory.drivers) ? memory.drivers : [];
    if (seeded.length) await writeDoc('drivers', seeded);
    return seeded;
  }
  if (IS_VERCEL) {
    return Array.isArray(memory.drivers) ? memory.drivers : [];
  }
  memory.drivers = loadJson(FILES.drivers, memory.drivers || []).map((row) =>
    normalizeDriver(row),
  );
  return memory.drivers;
}

async function writeDrivers(rows) {
  const normalized = (Array.isArray(rows) ? rows : []).map((row) => normalizeDriver(row));
  memory.drivers = normalized;
  await writeDoc('drivers', normalized);
  return normalized;
}

async function readDeliveryRequests() {
  if (usesPersistent()) {
    const stored = await readDoc('delivery_requests', null);
    if (Array.isArray(stored)) {
      memory.deliveryRequests = stored.map((row) => ensureRestaurantId(row));
      return memory.deliveryRequests;
    }
    const seeded = Array.isArray(memory.deliveryRequests) ? memory.deliveryRequests : [];
    if (seeded.length) await writeDoc('delivery_requests', seeded);
    return seeded;
  }
  if (IS_VERCEL) {
    return Array.isArray(memory.deliveryRequests) ? memory.deliveryRequests : [];
  }
  memory.deliveryRequests = loadJson(FILES.deliveryRequests, memory.deliveryRequests || []).map(
    (row) => ensureRestaurantId(row),
  );
  return memory.deliveryRequests;
}

async function writeDeliveryRequests(rows) {
  const normalized = (Array.isArray(rows) ? rows : []).map((row) => ensureRestaurantId(row));
  memory.deliveryRequests = normalized;
  await writeDoc('delivery_requests', normalized);
  return normalized;
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
  if (usesPersistent()) {
    if (memory.settings && Date.now() - settingsMemoryAt < DOC_MEMORY_TTL_MS) {
      return migrateSettingsShape(memory.settings);
    }
    memory.settings = migrateSettingsShape(
      await readDoc('settings', memory.settings),
    );
    settingsMemoryAt = Date.now();
    return memory.settings;
  }

  if (IS_VERCEL) {
    return migrateSettingsShape(memory.settings);
  }

  memory.settings = migrateSettingsShape(loadJson(FILES.settings, memory.settings));
  return memory.settings;
}

async function writeSettingsMap(map) {
  memory.settings = migrateSettingsShape(map);
  settingsMemoryAt = Date.now();
  await writeDoc('settings', memory.settings);
  return memory.settings;
}

async function readStoreAssets() {
  const fallback = memory.storeAssets || {};
  if (usesPersistent()) {
    return (await readDoc('store_assets', fallback)) || {};
  }
  return fallback;
}

async function readNamedDoc(id, fallback) {
  return readDoc(id, fallback);
}

async function writeNamedDoc(id, data) {
  await writeDoc(id, data);
  return data;
}

async function writeStoreAssets(map) {
  memory.storeAssets = map && typeof map === 'object' ? map : {};
  await writeDoc('store_assets', memory.storeAssets);
  return memory.storeAssets;
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

async function allocateItemId() {
  const col = await ensureItemsCollection();
  if (col) {
    try {
      const last = await col
        .find({}, { projection: { id: 1 } })
        .sort({ id: -1 })
        .limit(1)
        .next();
      const n = Number(last?.id);
      if (Number.isFinite(n) && n > 0) return n + 1;
    } catch (_) {}
  }
  return Date.now();
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
  itemsCollectionHasDocs = true;
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
  const col = await ensureItemsCollection();
  if (col) {
    if (Array.isArray(memory.menuItems) && memory.menuItems.length) {
      const index = memory.menuItems.findIndex((item) => {
        if (
          restaurantId &&
          String(item.restaurant_id || item.restaurantId) !== String(restaurantId)
        ) {
          return false;
        }
        return blobItemMatchesId(item, itemId);
      });
      if (index !== -1) {
        const nextItem = mutator(memory.menuItems[index]);
        if (nextItem == null) {
          memory.menuItems.splice(index, 1);
        } else {
          memory.menuItems[index] = nextItem;
        }
        itemsMemoryAt = Date.now();
      }
    }
    return true;
  }
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
  usesMysql,
  usesPersistent,
  readNamedDoc,
  writeNamedDoc,
  storageHealth,
  readItems,
  readItemsPage,
  writeItems,
  applyItemDisplayOrder,
  renameItemCategory,
  patchItemAvailability,
  findItemDoc,
  replaceItemDoc,
  allocateItemId,
  deleteItemDoc,
  patchItemInBlob,
  readOrders,
  writeOrders,
  prependOrder,
  patchOrderById,
  readRestaurants,
  writeRestaurants,
  readDeliveryZones,
  writeDeliveryZones,
  readKitchens,
  writeKitchens,
  readMenuCategories,
  writeMenuCategories,
  readReviews,
  writeReviews,
  readExpenses,
  writeExpenses,
  readOffers,
  writeOffers,
  readStaffUsers,
  writeStaffUsers,
  readTables,
  writeTables,
  readShiftSessions,
  writeShiftSessions,
  readSignupRequests,
  writeSignupRequests,
  readDrivers,
  writeDrivers,
  readDeliveryRequests,
  writeDeliveryRequests,
  readSettingsMap,
  writeSettingsMap,
  readStoreAssets,
  writeStoreAssets,
};
