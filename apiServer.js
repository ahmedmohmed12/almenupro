'use strict';

const http = require('http');

const dataStore = require('./lib/dataStore');
const extraStore = require('./lib/extraStore');
const {
  applyCorsHeaders,
  handleCorsPreflight,
  parseAuthHeader,
  loginSuperAdmin,
  loginRestaurantAdmin,
  loginCashierSession,
  isSuperAdmin,
  isCashier,
  isKitchen,
  isDriver,
  canAccessRestaurant,
  resolveRestaurantId,
  authError,
  DEFAULT_RESTAURANT_ID,
  SUPER_ADMIN_USER,
} = require('./lib/adminAuth');
const {
  filterByRestaurant,
  defaultSettingsPayload,
  createRestaurantRecord,
  resolveRestaurantFromQuery,
  assertRestaurantAccess,
  nextNumericItemId,
} = require('./lib/tenantStore');
const {
  readRestaurantIdParam,
  resolveReportRestaurantId,
} = require('./lib/restaurantScopeUtils');
const { handlePosRoutes } = require('./lib/posRoutes');
const {
  findDuplicateOrder,
  stampOfflineTx,
  preferNewerOrder,
} = require('./lib/orderIdempotency');
const { handleKitchenRoutes } = require('./lib/kitchenRoutes');
const { handleMenuCategoryRoutes } = require('./lib/menuCategoryRoutes');
const {
  syncCategoriesFromItemNames,
} = require('./lib/menuCategories');
const { assignTargetKitchen, findKitchenByLogin, orderTargetKitchenId } = require('./lib/kitchenRouting');
const { handleTableRoutes, normalizeFeatures, isKitchenManagementEnabled, isTableManagementEnabled, isDeliveryManagementEnabled } = require('./lib/tableRoutes');
const { applyGuestOrderToTable } = require('./lib/diningTables');
const { handleReviewRoutes } = require('./lib/reviewRoutes');
const { handleOrderRatingRoutes, createRatingToken } = require('./lib/orderRating');
const { handleExpenseRoutes } = require('./lib/expenseRoutes');
const { handleSignupRoutes } = require('./lib/signupRoutes');
const { handleDeliveryRoutes, enqueueDeliveryForAcceptedOrder } = require('./lib/deliveryRoutes');
const { stampTimeline, stampFromOrderStatus } = require('./lib/orderTimeline');
const { computeProfitAndLoss } = require('./lib/pnlAnalytics');
const { ALL_PERMISSION_KEYS } = require('./lib/posPermissions');
const { serveMenuImage, persistMenuItemsImages, proxyExternalImage, fetchUpstreamImage } = require('./lib/menuImageStorage');
const { normalizeMenuItemsForApi, normalizeMenuItemForApi } = require('./lib/bilingualItemMigration');
const { migrateMenuItems } = require('./lib/bilingualMenu');
const { scrapeTalabatMenu } = require('./lib/talabatScraper');
const { computeTopMenuItems } = require('./lib/topItemsAnalytics');
const { computeDailySalesAnalytics } = require('./lib/platformSalesAnalytics');
const { computeFoodCostReport } = require('./lib/foodCostReportAnalytics');
const { computeUpsellAnalytics, normalizeIncomingEvent, trimEvents } = require('./lib/upsellAnalytics');
const { previewEarnedCashback, applyLoyaltyCashbackToOrder, redeemCustomerWallet, normalizeLoyaltySettings, isDeliveredStatus } = require('./lib/loyaltyCashback');
const { normalizeOffer, isOfferLive, collectOfferIdsFromOrder, evaluateOfferUsage, findExhaustedOfferIds, repriceOrderIfOffersExhausted, assertOffersUsageAllowed, OFFER_USAGE_LIMIT_MESSAGE } = require('./lib/offers');
const {
  enrichCustomersForRestaurant,
  upsertCustomerFromSource,
  findCustomerByPhone,
  customerProfileFromRecord,
  migrateCustomersFromOrders,
  identifyCustomerByPhone,
} = require('./lib/customersStore');
const { normalizeWhatsappSettings } = require('./lib/whatsappPhone');
const { clampPaydayStartDay } = require('./lib/dynamicMenuSort');
const { sendWhatsAppNotification } = require('./lib/whatsappNotification');
const {
  buildRestaurantOgData,
  buildOgMenuHtml,
  isSocialCrawler,
  parseRestaurantOgRequest,
} = require('./lib/ogMenuMeta');
const {
  applyShiftBindingOnAccept,
  applyShiftAdjustmentOnCancel,
  attachReceivingCashier,
  attachAcceptedBy,
} = require('./lib/shiftOrderBinding');

const PORT = Number(process.env.PORT || 3000);
const PKG = require('./package.json');

function rootStatusPayload() {
  return {
    ok: true,
    message: 'AlMenuPro API is running successfully',
    service: PKG.name || 'almenupro-api',
    version: PKG.version || '0.0.0',
  };
}

function sendJson(res, statusCode, body) {
  applyCorsHeaders(res.req || { headers: {} }, res);
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(body));
}

function sendHtml(res, statusCode, html) {
  applyCorsHeaders(res.req || { headers: {} }, res);
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(html);
}

async function readBody(req) {
  if (typeof req.body === 'string') return req.body;
  if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
    return JSON.stringify(req.body);
  }
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

function parseJson(raw) {
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

const ACTIVE_ORDER_STATUSES = new Set(['pending', 'confirmed', 'preparing', 'ready']);

function isAutoAcceptedStatus(raw) {
  const value = String(raw || '')
    .trim()
    .toLowerCase()
    .replace(/-/g, '_');
  return value === 'auto_accepted' || value === 'autoaccepted';
}

function persistOrderStatus(raw, fallback) {
  if (isAutoAcceptedStatus(raw)) return 'confirmed';
  const value = String(raw || '')
    .trim()
    .toLowerCase()
    .replace(/-/g, '_');
  if (value === 'driver_pending') return 'confirmed';
  if (value === 'driver_accepted' || value === 'on_the_way' || value === 'picked_up') {
    return 'preparing';
  }
  return value || fallback || 'pending';
}

function isOrderHeldByDriver(order) {
  const status = String(order?.status || '').toLowerCase();
  if (status === 'delivered' || status === 'cancelled' || status === 'canceled') {
    return false;
  }
  const delivery = String(order?.delivery_status || order?.deliveryStatus || '')
    .trim()
    .toLowerCase()
    .replace(/-/g, '_');
  if (
    delivery === 'driver_accepted' ||
    delivery === 'picked_up' ||
    delivery === 'on_the_way' ||
    delivery === 'in_transit' ||
    delivery === 'accepted'
  ) {
    return true;
  }
  const driverId = String(order?.assigned_driver_id || order?.assignedDriverId || '').trim();
  const driverName = String(order?.assigned_driver_name || order?.assignedDriverName || '').trim();
  const orderType = String(order?.orderType || order?.order_type || '').toLowerCase();
  if (
    (driverId || driverName) &&
    orderType !== 'pickup' &&
    orderType !== 'dinein' &&
    (status === 'preparing' || status === 'ready')
  ) {
    return true;
  }
  return false;
}

function selectRecentOrders(orders, limit = 250) {
  const list = Array.isArray(orders) ? [...orders] : [];
  list.sort(
    (a, b) =>
      Date.parse(b.createdAt || b.created_at || 0) -
      Date.parse(a.createdAt || a.created_at || 0),
  );
  const selected = [];
  const seen = new Set();
  for (const order of list) {
    const id = String(order.id || '');
    if (!id || seen.has(id)) continue;
    const status = String(order.status || '').toLowerCase();
    const keepActive = ACTIVE_ORDER_STATUSES.has(status);
    if (!keepActive && selected.length >= limit) continue;
    seen.add(id);
    selected.push(order);
  }
  return selected;
}

function requestUrl(req) {
  const host = req.headers.host || 'localhost';
  const proto = req.headers['x-forwarded-proto'] || 'http';
  return new URL(req.url || '/', `${proto}://${host}`);
}

function requestFrontendOrigin(req) {
  const forwarded = String(req.headers['x-forwarded-host'] || '')
    .split(',')[0]
    .trim();
  const host = forwarded || String(req.headers.host || '').split(':')[0];
  const proto = String(req.headers['x-forwarded-proto'] || 'https')
    .split(',')[0]
    .trim();
  if (
    host &&
    !/backend-henna|almenupro-api|onrender\.com|localhost/i.test(host)
  ) {
    return `${proto}://${host}`.replace(/\/+$/, '');
  }
  return process.env.FRONTEND_ORIGIN || 'https://frontend-six-lime-13.vercel.app';
}

function publicRestaurant(entry) {
  if (!entry || typeof entry !== 'object') return entry;
  const { adminPassword, ...rest } = entry;
  return {
    ...rest,
    features: normalizeFeatures(entry.features),
    location: parseRestaurantLocation(entry.location, null),
  };
}

function parseRestaurantLocation(raw, fallback = null) {
  if (raw && typeof raw === 'object') {
    const lat = Number(raw.lat ?? raw.latitude);
    const lng = Number(raw.lng ?? raw.longitude);
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      return {
        lat,
        lng,
        address: String(raw.address || raw.label || '').trim(),
      };
    }
  }
  return fallback;
}

function requireAuth(req, res) {
  const auth = parseAuthHeader(req);
  if (!auth) {
    authError(res, 401, 'Unauthorized');
    return null;
  }
  return auth;
}

function fullAccessPermissions() {
  return Object.fromEntries(ALL_PERMISSION_KEYS.map((key) => [key, true]));
}

async function resolveScopedRestaurantId(req, url, auth, { allowPublicDefault = false } = {}) {
  const restaurants = await dataStore.readRestaurants();
  const requested =
    readRestaurantIdParam(req, url) || resolveRestaurantFromQuery(url, restaurants);
  return resolveRestaurantId(auth, requested, { allowPublicDefault });
}

function parseOriginalPrice(body, existing, price) {
  const clearing =
    Object.prototype.hasOwnProperty.call(body, 'originalPrice') ||
    Object.prototype.hasOwnProperty.call(body, 'original_price');
  const raw = body.originalPrice ?? body.original_price;
  if (clearing && (raw === null || raw === '' || raw === undefined)) {
    return undefined;
  }
  const source = raw ?? existing.originalPrice ?? existing.original_price;
  const value = Number(source);
  if (!Number.isFinite(value) || value <= price + 0.0005) return undefined;
  return value;
}

function parseOptionalCostPrice(body) {
  const raw = body?.costPrice ?? body?.cost_price;
  if (raw == null || raw === '') return null;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : null;
}

function applyCostPriceFields(target, body, existing = {}) {
  if (body && (body.costPrice != null || body.cost_price != null)) {
    const costPrice = parseOptionalCostPrice(body);
    if (costPrice == null) {
      delete target.costPrice;
      delete target.cost_price;
    } else {
      target.costPrice = costPrice;
      target.cost_price = costPrice;
    }
    return;
  }
  const existingCost = parseOptionalCostPrice(existing);
  if (existingCost == null) {
    delete target.costPrice;
    delete target.cost_price;
  } else {
    target.costPrice = existingCost;
    target.cost_price = existingCost;
  }
}

function normalizeIncomingItem(body, restaurantId, existing = {}) {
  const isAvailable = body.isAvailable ?? body.is_available ?? existing.is_available ?? true;
  const posOnly = body.posOnly ?? body.pos_only;
  const showOnWebsiteRaw =
    body.showOnWebsite ??
    body.show_on_website ??
    existing.showOnWebsite ??
    existing.show_on_website;
  const showOnWebsite =
    posOnly === true || posOnly === 1
      ? false
      : showOnWebsiteRaw === false ||
          showOnWebsiteRaw === 0 ||
          showOnWebsiteRaw === '0' ||
          showOnWebsiteRaw === 'false'
        ? false
        : true;
  const price = Number(body.price ?? existing.price ?? 0);
  const originalPrice = parseOriginalPrice(body, existing, price);
  const displayOrderRaw =
    body.display_order ?? body.displayOrder ?? existing.display_order ?? existing.displayOrder;
  const displayOrder =
    displayOrderRaw == null || displayOrderRaw === ''
      ? 0
      : Number(displayOrderRaw) || 0;
  const talabatRaw =
    body.talabat_id ?? body.talabatId ?? existing.talabat_id ?? existing.talabatId;
  const talabatId =
    talabatRaw == null || talabatRaw === ''
      ? null
      : Number.isFinite(Number(talabatRaw))
        ? Number(talabatRaw)
        : String(talabatRaw);
  const normalized = normalizeMenuItemForApi({
    ...existing,
    ...body,
    restaurant_id: restaurantId,
    restaurantId,
    name: body.name ?? existing.name,
    name_ar: body.name_ar ?? body.nameAr ?? body.name ?? existing.name_ar,
    name_en: body.name_en ?? body.nameEn ?? existing.name_en ?? '',
    description: body.description ?? existing.description ?? '',
    description_ar:
      body.description_ar ?? body.descriptionAr ?? body.description ?? existing.description_ar ?? '',
    description_en: body.description_en ?? body.descriptionEn ?? existing.description_en ?? '',
    price,
    category_name: body.categoryName ?? body.category_name ?? existing.category_name ?? 'عام',
    image_url: body.imageUrl ?? body.image_url ?? existing.image_url ?? '',
    is_available: isAvailable === false || isAvailable === 0 ? 0 : 1,
    showOnWebsite,
    show_on_website: showOnWebsite,
    source: body.source ?? existing.source ?? 'Manual',
    options: body.options ?? existing.options ?? [],
    linkedItemIds: body.linkedItemIds ?? body.linked_item_ids ?? existing.linkedItemIds ?? [],
    display_order: displayOrder,
    displayOrder: displayOrder,
    ...(talabatId != null
      ? { talabat_id: talabatId, talabatId }
      : {}),
  });
  if (originalPrice != null) {
    normalized.originalPrice = originalPrice;
    normalized.original_price = originalPrice;
  } else {
    delete normalized.originalPrice;
    delete normalized.original_price;
  }
  applyCostPriceFields(normalized, body, existing);
  return normalized;
}

function itemMatchesId(item, itemId) {
  return String(item.id) === String(itemId) || String(item.talabat_id) === String(itemId);
}

function posDeps() {
  return {
    readBody,
    sendJson,
    authError,
    parseAuthHeader,
    requireAuth,
    isSuperAdmin,
    assertRestaurantAccess,
    resolveScopedRestaurantId: (req, url, auth) =>
      resolveScopedRestaurantId(req, url, auth, { allowPublicDefault: false }),
    filterByRestaurant,
    readSettings: async (restaurantId) => {
      const map = await dataStore.readSettingsMap();
      return map.byRestaurant?.[restaurantId] || defaultSettingsPayload();
    },
    readRestaurants: () => dataStore.readRestaurants(),
    readStaffUsers: () => extraStore.staffUsers.read(),
    writeStaffUsers: (value) => extraStore.staffUsers.write(value),
    readShiftSessions: () => extraStore.shiftSessions.read(),
    writeShiftSessions: (value) => extraStore.shiftSessions.write(value),
    readOrders: () => dataStore.readOrders(),
    writeOrders: (value) => dataStore.writeOrders(value),
    readDeliveryRequests: () => dataStore.readDeliveryRequests(),
    readItemsPage: (options) => dataStore.readItemsPage(options),
    appendAuditEvents: async (events) => {
      const current = await extraStore.auditEvents.read();
      current.unshift(...events);
      await extraStore.auditEvents.write(current.slice(0, 5000));
    },
  };
}

async function handleRequest(req, res) {
  // Preflight must short-circuit before Mongo/datastore for every /api and /og route.
  applyCorsHeaders(req, res);
  if (handleCorsPreflight(req, res)) {
    return;
  }

  const url = requestUrl(req);
  let pathname = url.pathname || '/';
  if (pathname.length > 1 && pathname.endsWith('/')) {
    pathname = pathname.slice(0, -1);
  }
  url.pathname = pathname;

  // Root readiness — no datastore required (Render / local health checks).
  if ((pathname === '/' || pathname === '/api') && req.method === 'GET') {
    sendJson(res, 200, rootStatusPayload());
    return;
  }

  const imageMatch = pathname.match(/^\/api\/uploads\/menu\/([^/]+)$/);
  if (imageMatch && (req.method === 'GET' || req.method === 'HEAD')) {
    serveMenuImage(res, decodeURIComponent(imageMatch[1]));
    return;
  }

  if (pathname === '/api/image-proxy' && (req.method === 'GET' || req.method === 'HEAD')) {
    await proxyExternalImage(res, url.searchParams.get('url'));
    return;
  }

  try {
    await dataStore.initDataStore();
    extraStore.seed();
  } catch (error) {
    // Never fail the whole API on store init; JSON/memory fallback keeps dashboard alive.
    console.error('[apiServer] initDataStore failed, continuing with fallback:', error);
  }

  try {
    const handled = await routeRequest(req, res, url, pathname);
    if (!handled && !res.writableEnded) {
      sendJson(res, 404, { error: 'Not found' });
    }
  } catch (error) {
    console.error('[apiServer]', error);
    if (!res.writableEnded) {
      applyCorsHeaders(req, res);
      sendJson(res, 500, { error: error.message || 'Internal server error' });
    }
  }
}

/**
 * Vercel/Node entry: OPTIONS is answered with writeHead(200) inside
 * handleCorsPreflight BEFORE any Mongo/datastore work.
 */
async function vercelHandler(req, res) {
  try {
    if (handleCorsPreflight(req, res)) {
      return;
    }
    await handleRequest(req, res);
  } catch (error) {
    console.error('[apiServer] unhandled:', error);
    if (!res.writableEnded) {
      applyCorsHeaders(req, res);
      res.statusCode = 500;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.end(JSON.stringify({ error: error.message || 'Internal server error' }));
    }
  }
}

async function routeRequest(req, res, url, pathname) {
  if (await handlePosRoutes(req, res, url, posDeps())) {
    return true;
  }

  if (await handleKitchenRoutes(req, res, url, {
    readBody,
    sendJson,
    authError,
    parseAuthHeader,
    requireAuth,
    rejectCashier: (auth, res, message) => {
      if (isCashier(auth) || isKitchen(auth)) {
        sendJson(res, 403, { error: message, code: 'STATION_FORBIDDEN' });
        return true;
      }
      return false;
    },
    resolveScopedRestaurantId,
    resolveRestaurantId,
    assertRestaurantAccess,
    filterByRestaurant,
    readKitchens: () => dataStore.readKitchens(),
    writeKitchens: (value) => dataStore.writeKitchens(value),
    readOrders: () => dataStore.readOrders(),
    readRestaurants: () => dataStore.readRestaurants(),
    isKitchenManagementEnabled,
    DEFAULT_RESTAURANT_ID,
  })) {
    return true;
  }

  if (await handleMenuCategoryRoutes(req, res, url, {
    readBody,
    sendJson,
    authError,
    requireAuth,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readMenuCategories: () => dataStore.readMenuCategories(),
    writeMenuCategories: (value) => dataStore.writeMenuCategories(value),
    readItems: () => dataStore.readItems(),
    renameItemCategory: (restaurantId, fromName, toName) =>
      dataStore.renameItemCategory(restaurantId, fromName, toName),
  })) {
    return true;
  }

  if (await handleDeliveryRoutes(req, res, url, {
    readBody,
    sendJson,
    parseJson,
    requireAuth,
    parseAuthHeader,
    authError,
    isDriver,
    isKitchen,
    isCashier,
    isSuperAdmin,
    resolveScopedRestaurantId,
    assertRestaurantAccess,
    filterByRestaurant,
    readDrivers: () => dataStore.readDrivers(),
    writeDrivers: (value) => dataStore.writeDrivers(value),
    readDeliveryRequests: () => dataStore.readDeliveryRequests(),
    writeDeliveryRequests: (value) => dataStore.writeDeliveryRequests(value),
    readDeliveryZones: () => dataStore.readDeliveryZones(),
    readRestaurants: () => dataStore.readRestaurants(),
    readOrders: () => dataStore.readOrders(),
    patchOrderById: (orderId, next, existing) => dataStore.patchOrderById(orderId, next, existing),
  })) {
    return true;
  }

  if (await handleTableRoutes(req, res, url, {
    readBody,
    sendJson,
    authError,
    requireAuth,
    isCashier,
    assertRestaurantAccess,
    resolveScopedRestaurantId: (req, url, auth) =>
      resolveScopedRestaurantId(req, url, auth, { allowPublicDefault: false }),
    filterByRestaurant,
    readRestaurants: () => dataStore.readRestaurants(),
    readTables: () => dataStore.readTables(),
    writeTables: (value) => dataStore.writeTables(value),
    readOrders: () => dataStore.readOrders(),
    writeOrders: (value) => dataStore.writeOrders(value),
  })) {
    return true;
  }

  if (await handleReviewRoutes(req, res, url, {
    readBody,
    sendJson,
    authError,
    requireAuth,
    parseAuthHeader,
    isCashier,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readReviews: () => dataStore.readReviews(),
    writeReviews: (value) => dataStore.writeReviews(value),
    readOrders: () => dataStore.readOrders(),
    rejectCashier: (auth, res, message) => {
      if (isCashier(auth) || isKitchen(auth)) {
        sendJson(res, 403, { error: message, code: 'STATION_FORBIDDEN' });
        return true;
      }
      return false;
    },
  })) {
    return true;
  }

  if (await handleOrderRatingRoutes(req, res, url, {
    readBody,
    sendJson,
    requireAuth,
    parseJson,
    assertRestaurantAccess,
    authError,
    readOrders: () => dataStore.readOrders(),
    patchOrderById: (id, next, existing) => dataStore.patchOrderById(id, next, existing),
    readRestaurants: () => dataStore.readRestaurants(),
    readReviews: () => dataStore.readReviews(),
    writeReviews: (value) => dataStore.writeReviews(value),
  })) {
    return true;
  }

  if (await handleExpenseRoutes(req, res, url, {
    readBody,
    sendJson,
    authError,
    requireAuth,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readExpenses: () => dataStore.readExpenses(),
    writeExpenses: (value) => dataStore.writeExpenses(value),
    rejectCashier: (auth, res, message) => {
      if (isCashier(auth) || isKitchen(auth)) {
        sendJson(res, 403, { error: message, code: 'STATION_FORBIDDEN' });
        return true;
      }
      return false;
    },
  })) {
    return true;
  }

  const ogImageMatch = pathname.match(/^\/api\/og-image\/([^/]+)$/);
  if (ogImageMatch && (req.method === 'GET' || req.method === 'HEAD')) {
    const slug = decodeURIComponent(ogImageMatch[1]).replace(/\/+$/, '');
    const restaurants = await dataStore.readRestaurants();
    const restaurant = restaurants.find(
      (entry) => String(entry.slug || '').toLowerCase() === slug.toLowerCase(),
    );
    const settingsMap = restaurant ? await dataStore.readSettingsMap() : { byRestaurant: {} };
    const settings = restaurant ? settingsMap.byRestaurant?.[restaurant.id] || {} : {};
    const logoUrl = String(
      settings.logoUrl ||
        settings.logo_url ||
        restaurant?.logoUrl ||
        restaurant?.logo_url ||
        '',
    ).trim();
    const source =
      logoUrl || 'https://frontend-six-lime-13.vercel.app/icons/Icon-512.png';
    const result = await fetchUpstreamImage(source);
    if (result.error) {
      sendJson(res, result.status || 502, { error: result.error });
      return true;
    }
    res.statusCode = 200;
    res.setHeader('Content-Type', result.contentType);
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    if (req.method === 'HEAD') {
      res.setHeader('Content-Length', String(result.buffer.length));
      res.end();
      return true;
    }
    res.end(result.buffer);
    return true;
  }

  if (pathname === '/api/health' && req.method === 'GET') {
    sendJson(res, 200, dataStore.storageHealth());
    return true;
  }

  if (pathname === '/api/auth/login' && req.method === 'POST') {
    const body = parseJson(await readBody(req));
    const username = body.username;
    const password = body.password;
    const restaurantSlug = body.restaurantSlug || body.restaurant_slug;

    if (username) {
      const token = loginSuperAdmin(username, password);
      if (!token) {
        sendJson(res, 401, { error: 'Invalid credentials' });
        return true;
      }
      sendJson(res, 200, {
        token,
        role: 'super_admin',
        staffId: 'super_admin',
        staffName: SUPER_ADMIN_USER,
      });
      return true;
    }

    const restaurants = await dataStore.readRestaurants();
    const token = loginRestaurantAdmin(restaurantSlug, password, restaurants);
    if (!token) {
      sendJson(res, 401, { error: 'Invalid credentials' });
      return true;
    }
    const restaurant = restaurants.find(
      (entry) => String(entry.slug || '').toLowerCase() === String(restaurantSlug || '').toLowerCase(),
    );
    sendJson(res, 200, {
      token,
      role: 'restaurant_admin',
      restaurantId: restaurant?.id || null,
      restaurantName: restaurant?.name || null,
      staffId: restaurant?.id ? `admin:${restaurant.id}` : 'restaurant_admin',
      staffName: restaurant?.name || null,
    });
    return true;
  }

  if (pathname === '/api/auth/cashier-login' && req.method === 'POST') {
    const body = parseJson(await readBody(req));
    const restaurantKey = String(
      body.restaurantSlug ||
        body.restaurant_slug ||
        body.restaurantName ||
        body.restaurant_name ||
        '',
    )
      .trim()
      .toLowerCase();
    const cashierName = String(body.cashierName || body.cashier_name || body.name || '').trim();
    const pin = String(body.pin || body.password || body.pinCode || '').trim();
    if (!restaurantKey || !cashierName || !pin) {
      sendJson(res, 400, { error: 'restaurant, cashier name, and PIN are required' });
      return true;
    }

    const restaurants = await dataStore.readRestaurants();
    const restaurant = restaurants.find(
      (entry) =>
        String(entry.slug || '').toLowerCase() === restaurantKey ||
        String(entry.name || '').toLowerCase() === restaurantKey,
    );
    if (!restaurant) {
      sendJson(res, 401, { error: 'Invalid credentials' });
      return true;
    }

    const { findStaffByNameAndPin, resolveStaffPermissions, sanitizeStaffPublic } = require('./lib/staffUsers');
    const { normalizePosRoles, findRoleById } = require('./lib/posPermissions');
    const staffUsers = await extraStore.staffUsers.read();
    let staff = findStaffByNameAndPin(staffUsers, restaurant.id, cashierName, pin);
    const kitchens = await dataStore.readKitchens();
    const kitchenFromLogin = findKitchenByLogin(kitchens, restaurant.id, cashierName, pin);
    if (!staff && kitchenFromLogin) {
      staff = {
        id: `kitchen_login_${kitchenFromLogin.id}`,
        name: kitchenFromLogin.loginName || kitchenFromLogin.login_name,
        roleId: 'kitchen',
        kitchenId: kitchenFromLogin.id,
        kitchen_id: kitchenFromLogin.id,
        restaurantId: restaurant.id,
        isActive: true,
      };
    }
    if (!staff) {
      sendJson(res, 401, { error: 'Invalid credentials' });
      return true;
    }

    const kitchenId = String(staff.kitchenId || staff.kitchen_id || kitchenFromLogin?.id || '').trim();
    const isDriverRole = String(staff.roleId || staff.role_id || '').toLowerCase() === 'driver';
    const isKitchenRole =
      !isDriverRole &&
      (String(staff.roleId || staff.role_id || '').toLowerCase() === 'kitchen' || Boolean(kitchenId));
    if (isKitchenRole && !isKitchenManagementEnabled(restaurant)) {
      sendJson(res, 403, {
        error: 'شاشات المطابخ غير مفعّلة في اشتراك هذا المطعم',
        code: 'KITCHEN_MANAGEMENT_DISABLED',
      });
      return true;
    }
    const kitchenRecord =
      (kitchenId && kitchens.find((entry) => String(entry.id) === kitchenId)) ||
      kitchenFromLogin ||
      null;
    const kitchenName = kitchenRecord
      ? kitchenRecord.name_ar || kitchenRecord.name || kitchenRecord.name_en || kitchenRecord.id
      : null;

    const settingsMap = await dataStore.readSettingsMap();
    const posRoles = normalizePosRoles(
      settingsMap.byRestaurant?.[restaurant.id]?.posRoles ||
        settingsMap.byRestaurant?.[restaurant.id]?.pos_roles,
    );
    const token = loginCashierSession({
      restaurantId: restaurant.id,
      restaurantName: restaurant.name,
      staffId: staff.id,
      staffName: staff.name,
      kitchenId: isKitchenRole ? kitchenId || null : null,
      kitchenName: isKitchenRole ? kitchenName : null,
      asKitchen: isKitchenRole,
      asDriver: isDriverRole,
    });
    sendJson(res, 200, {
      token,
      role: isDriverRole ? 'driver' : isKitchenRole ? 'kitchen' : 'cashier',
      restaurantId: restaurant.id,
      restaurantName: restaurant.name,
      staffId: staff.id,
      staffName: staff.name,
      kitchenId: isKitchenRole ? kitchenId || null : null,
      kitchenName: isKitchenRole ? kitchenName : null,
      staff: sanitizeStaffPublic(staff),
      permissions: isKitchenRole || isDriverRole ? {} : resolveStaffPermissions(staff, posRoles),
      posRole: isKitchenRole || isDriverRole ? null : findRoleById(posRoles, staff.roleId || staff.role_id),
    });
    return true;
  }

  if (pathname === '/api/auth/driver-login' && req.method === 'POST') {
    const body = parseJson(await readBody(req));
    const identifier = String(body.phone || body.name || body.login || '').trim();
    const pin = String(body.pin || body.password || '').trim();
    if (identifier.length < 2 || !/^\d{4}$/.test(pin)) {
      sendJson(res, 400, { error: 'رقم الهاتف ورمز PIN المكون من 4 أرقام مطلوبان' });
      return true;
    }
    const { verifyPin, sanitizeStaffPublic } = require('./lib/staffUsers');
    const { normalizeDriver, publicDriver } = require('./lib/deliveryDispatch');
    const digits = identifier.replace(/\D/g, '');
    const nameKey = identifier.toLowerCase();
    const drivers = await dataStore.readDrivers();
    const matchesLogin = (row) => {
      if (String(row.name || '').trim().toLowerCase() === nameKey) return true;
      const phone = String(row.phone || '').replace(/\D/g, '');
      return Boolean(
        digits.length >= 7 &&
          phone &&
          (phone === digits || phone.endsWith(digits) || digits.endsWith(phone)),
      );
    };
    let driver = (drivers || []).find(
      (row) => verifyPin(pin, row.pin_hash || row.pinHash, 'fleet') && matchesLogin(row),
    );
    if (!driver) {
      const staffUsers = await extraStore.staffUsers.read();
      const restaurants = await dataStore.readRestaurants();
      const staff = (staffUsers || []).find((entry) => {
        if (String(entry.roleId || entry.role_id || '').toLowerCase() !== 'driver') return false;
        if (String(entry.name || '').trim().toLowerCase() !== nameKey) return false;
        return verifyPin(pin, entry.pinHash || entry.pin_hash, entry.restaurantId || entry.restaurant_id);
      });
      if (staff) {
        driver = (drivers || []).find(
          (row) =>
            String(row.staff_id || '') === String(staff.id) ||
            String(row.name || '').trim().toLowerCase() === nameKey,
        );
        if (!driver) {
          driver = normalizeDriver({
            name: staff.name,
            staff_id: staff.id,
            phone: identifier,
            pin,
            restaurant_id: staff.restaurantId || staff.restaurant_id,
          });
          drivers.push(driver);
          await dataStore.writeDrivers(drivers);
        }
        const restaurant = restaurants.find(
          (entry) => String(entry.id) === String(staff.restaurantId || staff.restaurant_id),
        );
        const token = loginCashierSession({
          restaurantId: staff.restaurantId || staff.restaurant_id || 'fleet',
          restaurantName: restaurant?.name || 'أسطول المنصة',
          staffId: driver.id,
          staffName: driver.name,
          asDriver: true,
        });
        sendJson(res, 200, {
          token,
          role: 'driver',
          restaurantId: staff.restaurantId || staff.restaurant_id || null,
          restaurantName: restaurant?.name || 'أسطول المنصة',
          staffId: driver.id,
          staffName: driver.name,
          staff: sanitizeStaffPublic({ ...staff, id: driver.id, roleId: 'driver' }),
          driver: publicDriver(driver),
        });
        return true;
      }
      sendJson(res, 401, { error: 'رقم الهاتف أو رمز PIN غير صحيح' });
      return true;
    }
    if (!driver.staff_id) {
      const index = drivers.findIndex((row) => String(row.id) === String(driver.id));
      if (index >= 0) {
        drivers[index] = normalizeDriver({ ...driver, staff_id: driver.id });
        driver = drivers[index];
        await dataStore.writeDrivers(drivers);
      }
    }
    const token = loginCashierSession({
      restaurantId: driver.restaurant_id || driver.restaurantId || 'fleet',
      restaurantName: 'أسطول المنصة',
      staffId: driver.id,
      staffName: driver.name,
      asDriver: true,
    });
    sendJson(res, 200, {
      token,
      role: 'driver',
      restaurantId: driver.restaurant_id || driver.restaurantId || null,
      restaurantName: 'أسطول المنصة',
      staffId: driver.id,
      staffName: driver.name,
      driver: publicDriver(driver),
    });
    return true;
  }

  if (pathname === '/api/pos/session/permissions' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    sendJson(res, 200, {
      roleId: isSuperAdmin(auth) ? 'super_admin' : 'restaurant_admin',
      permissions: fullAccessPermissions(),
    });
    return true;
  }

  if (await handleSignupRoutes(req, res, url, {
    readBody,
    sendJson,
    requireAuth,
    isSuperAdmin,
    authError,
    parseJson,
    readSignupRequests: () => dataStore.readSignupRequests(),
    writeSignupRequests: (value) => dataStore.writeSignupRequests(value),
    readSettingsMap: () => dataStore.readSettingsMap(),
    writeSettingsMap: (value) => dataStore.writeSettingsMap(value),
  })) {
    return true;
  }

    if (pathname === '/api/public/restaurants' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    sendJson(
      res,
      200,
      restaurants
        .filter((entry) => String(entry.status || 'active') === 'active')
        .map(publicRestaurant),
    );
    return true;
  }

  const publicRestaurantMatch = pathname.match(/^\/api\/public\/restaurants\/([^/]+)$/);
  if (publicRestaurantMatch && req.method === 'GET') {
    const key = decodeURIComponent(publicRestaurantMatch[1]).toLowerCase();
    const restaurants = await dataStore.readRestaurants();
    const match = restaurants.find(
      (entry) =>
        String(entry.slug || '').toLowerCase() === key ||
        String(entry.id || '').toLowerCase() === key,
    );
    if (!match || String(match.status || 'active') !== 'active') {
      sendJson(res, 404, { error: 'Restaurant not found' });
      return true;
    }
    sendJson(res, 200, publicRestaurant(match));
    return true;
  }

  if (pathname === '/api/restaurants' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurants = await dataStore.readRestaurants();
    if (isSuperAdmin(auth)) {
      sendJson(res, 200, restaurants.map(publicRestaurant));
      return true;
    }
    const scoped = restaurants.filter((entry) => canAccessRestaurant(auth, entry.id));
    sendJson(res, 200, scoped.map(publicRestaurant));
    return true;
  }

  if (pathname === '/api/restaurants' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      authError(res, 403, 'Super admin required');
      return true;
    }
    try {
      const body = parseJson(await readBody(req));
      const created = {
        ...createRestaurantRecord(body),
        ownerName: body.ownerName || body.owner_name || '',
        phone: body.phone || '',
        status: body.status || 'active',
        subscriptionPlan: body.subscriptionPlan || body.subscription_plan || 'free',
        subscriptionStatus: body.subscriptionStatus || body.subscription_status || 'active',
        subscriptionExpiresAt: body.subscriptionExpiresAt || body.subscription_expires_at || null,
        subscriptionNotes: body.subscriptionNotes || body.subscription_notes || '',
        features: normalizeFeatures(
          body.features || {
            tableManagement: body.tableManagement,
            kitchenManagement: body.kitchenManagement,
            deliveryManagement: body.deliveryManagement ?? body.deliveryManagementEnabled,
          },
        ),
        location: parseRestaurantLocation(body.location, null),
        updatedAt: new Date().toISOString(),
      };
      const restaurants = await dataStore.readRestaurants();
      if (restaurants.some((entry) => String(entry.slug).toLowerCase() === created.slug)) {
        sendJson(res, 409, { error: 'Restaurant slug already exists' });
        return true;
      }
      restaurants.push(created);
      await dataStore.writeRestaurants(restaurants);
      sendJson(res, 201, publicRestaurant(created));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid restaurant payload' });
    }
    return true;
  }

  const restaurantMatch = pathname.match(/^\/api\/restaurants\/([^/]+)$/);
  if (restaurantMatch && req.method === 'PATCH') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = decodeURIComponent(restaurantMatch[1]);
    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const restaurants = await dataStore.readRestaurants();
    const index = restaurants.findIndex((entry) => String(entry.id) === restaurantId);
    if (index === -1) {
      sendJson(res, 404, { error: 'Restaurant not found' });
      return true;
    }
    const body = parseJson(await readBody(req));
    const current = restaurants[index];
    const next = {
      ...current,
      name: body.name ?? current.name,
      slug: body.slug ?? current.slug,
      ownerName: body.ownerName ?? body.owner_name ?? current.ownerName ?? '',
      phone: body.phone ?? current.phone ?? '',
      status: body.status ?? current.status,
      adminPassword: body.adminPassword || current.adminPassword,
      updatedAt: new Date().toISOString(),
    };
    if (isSuperAdmin(auth)) {
      next.subscriptionPlan =
        body.subscriptionPlan ?? body.subscription_plan ?? current.subscriptionPlan;
      next.subscriptionStatus =
        body.subscriptionStatus ?? body.subscription_status ?? current.subscriptionStatus;
      next.subscriptionExpiresAt =
        body.subscriptionExpiresAt ?? body.subscription_expires_at ?? current.subscriptionExpiresAt;
      next.subscriptionNotes =
        body.subscriptionNotes ?? body.subscription_notes ?? current.subscriptionNotes ?? '';
      const tableEnabled =
        body.tableManagement ??
        body.tableManagementEnabled ??
        body.features?.tableManagement ??
        body.features?.table_management;
      const kitchenEnabled =
        body.kitchenManagement ??
        body.kitchenManagementEnabled ??
        body.features?.kitchenManagement ??
        body.features?.kitchen_management;
      const deliveryEnabled =
        body.deliveryManagement ??
        body.deliveryManagementEnabled ??
        body.features?.deliveryManagement ??
        body.features?.delivery_management;
      next.features = {
        ...normalizeFeatures(current.features),
        ...(tableEnabled !== undefined ? { tableManagement: tableEnabled === true } : {}),
        ...(kitchenEnabled !== undefined ? { kitchenManagement: kitchenEnabled === true } : {}),
        ...(deliveryEnabled !== undefined ? { deliveryManagement: deliveryEnabled === true } : {}),
      };
    } else {
      next.subscriptionPlan = current.subscriptionPlan;
      next.subscriptionStatus = current.subscriptionStatus;
      next.subscriptionExpiresAt = current.subscriptionExpiresAt;
      next.subscriptionNotes = current.subscriptionNotes;
      next.features = normalizeFeatures(current.features);
    }
    if (body.location !== undefined || body.lat != null || body.lng != null) {
      next.location = parseRestaurantLocation(body.location || body, current.location || null);
    }
    restaurants[index] = next;
    await dataStore.writeRestaurants(restaurants);
    sendJson(res, 200, publicRestaurant(next));
    return true;
  }

  if (pathname === '/api/items' && req.method === 'GET') {
    const restaurantId =
      readRestaurantIdParam(req, url) ||
      resolveRestaurantFromQuery(url, await dataStore.readRestaurants());
    const lite =
      url.searchParams.get('full') !== '1' &&
      url.searchParams.get('full') !== 'true';
    const limit = Math.min(
      Math.max(Number(url.searchParams.get('limit')) || 40, 1),
      250,
    );
    const offset = Math.max(Number(url.searchParams.get('offset')) || 0, 0);
    const channel = String(url.searchParams.get('channel') || '').toLowerCase();
    const websiteOnly =
      channel === 'website' ||
      channel === 'public' ||
      url.searchParams.get('public') === '1';
    const page = await dataStore.readItemsPage({
      restaurantId,
      offset,
      limit,
      lite,
      websiteOnly,
    });
    res.setHeader('Cache-Control', 'public, max-age=20');
    res.setHeader('X-Total-Count', String(page.total || 0));
    res.setHeader('X-Limit', String(page.limit || limit));
    res.setHeader('X-Offset', String(page.offset || offset));
    sendJson(res, 200, Array.isArray(page.items) ? page.items : []);
    return true;
  }

  if (pathname === '/api/items' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const body = parseJson(await readBody(req));
    const created = normalizeIncomingItem(
      { ...body, id: body.id || (await dataStore.allocateItemId()) },
      restaurantId,
    );
    await dataStore.replaceItemDoc(created);
    sendJson(res, 201, created);
    return true;
  }

  if (pathname === '/api/items/sync' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const body = parseJson(await readBody(req));
    const restaurantId =
      body.restaurantId || (await resolveScopedRestaurantId(req, url, auth));
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const incoming = Array.isArray(body.items) ? body.items : [];
    let items = await dataStore.readItems();
    const others = items.filter(
      (item) => String(item.restaurant_id || item.restaurantId) !== String(restaurantId),
    );
    const scoped = incoming.map((item, index) =>
      normalizeIncomingItem({ ...item, id: item.id ?? index + 1 }, restaurantId),
    );
    const withImages = body.downloadImages ? await persistMenuItemsImages(scoped) : scoped;
    items = [...others, ...withImages];
    await dataStore.writeItems(items);
    sendJson(res, 200, { synced: withImages.length, items: withImages });
    return true;
  }

  const availabilityMatch = pathname.match(/^\/api\/items\/([^/]+)\/availability$/);
  if (availabilityMatch && req.method === 'PATCH') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const itemId = decodeURIComponent(availabilityMatch[1]);
    const body = parseJson(await readBody(req));
    const isAvailable = body.isAvailable ?? body.is_available;
    const restaurantHint = await resolveScopedRestaurantId(req, url, auth);
    const existingDoc = await dataStore.findItemDoc(itemId, restaurantHint);
    if (existingDoc) {
      if (!assertRestaurantAccess(
        auth,
        existingDoc.restaurant_id || existingDoc.restaurantId,
        authError,
        res,
      )) {
        return true;
      }
      const restaurantId = existingDoc.restaurant_id || existingDoc.restaurantId;
      const fromCollection = await dataStore.patchItemAvailability(
        itemId,
        isAvailable,
        restaurantId,
      );
      const flag = isAvailable === false || isAvailable === 0 ? 0 : 1;
      await dataStore.patchItemInBlob(itemId, restaurantId, (item) => ({
        ...item,
        is_available: flag,
        isAvailable: flag === 1,
      }));
      sendJson(res, 200, normalizeMenuItemForApi(fromCollection || existingDoc));
      return true;
    }
    const items = await dataStore.readItems();
    const index = items.findIndex((item) => itemMatchesId(item, itemId));
    if (index === -1) {
      sendJson(res, 404, { error: 'Item not found' });
      return true;
    }
    const restaurantId = items[index].restaurant_id || items[index].restaurantId;
    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    items[index] = {
      ...items[index],
      is_available: isAvailable === false || isAvailable === 0 ? 0 : 1,
    };
    await dataStore.writeItems(items);
    sendJson(res, 200, normalizeMenuItemForApi(items[index]));
    return true;
  }

  const itemMatch = pathname.match(/^\/api\/items\/([^/]+)$/);
  if (itemMatch && (req.method === 'PUT' || req.method === 'DELETE')) {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const itemId = decodeURIComponent(itemMatch[1]);
    const restaurantHint = await resolveScopedRestaurantId(req, url, auth);
    let existing = await dataStore.findItemDoc(itemId, restaurantHint);
    if (!existing) {
      const items = await dataStore.readItems();
      existing = items.find((item) => {
        if (
          restaurantHint &&
          String(item.restaurant_id || item.restaurantId) !== String(restaurantHint)
        ) {
          return false;
        }
        return itemMatchesId(item, itemId);
      }) || items.find((item) => itemMatchesId(item, itemId));
    }
    if (!existing) {
      sendJson(res, 404, { error: 'Item not found' });
      return true;
    }
    const restaurantId = existing.restaurant_id || existing.restaurantId;
    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    if (req.method === 'DELETE') {
      await dataStore.deleteItemDoc(itemId, restaurantId);
      await dataStore.patchItemInBlob(itemId, restaurantId, () => null);
      sendJson(res, 200, { ok: true });
      return true;
    }
    const body = parseJson(await readBody(req));
    const updated = normalizeIncomingItem(body, restaurantId, existing);
    await dataStore.replaceItemDoc(updated);
    await dataStore.patchItemInBlob(itemId, restaurantId, () => updated);
    sendJson(res, 200, updated);
    return true;
  }

  if (pathname === '/api/orders' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    let orders = filterByRestaurant(await dataStore.readOrders(), restaurantId);
    if (isKitchen(auth)) {
      const kitchenId = String(auth.kitchenId || '').trim();
      orders = kitchenId
        ? orders.filter((order) => {
            const status = String(order.status || '').toLowerCase();
            return (
              orderTargetKitchenId(order) === kitchenId &&
              status !== 'pending'
            );
          })
        : [];
    }
    const fromRaw = String(url.searchParams.get('from') || '').trim();
    const fromTs = fromRaw ? Date.parse(fromRaw) : NaN;
    if (Number.isFinite(fromTs)) {
      orders = orders.filter((order) => {
        const ts = Date.parse(order.createdAt || order.created_at || 0);
        return Number.isFinite(ts) && ts >= fromTs;
      });
    }
    sendJson(res, 200, selectRecentOrders(orders, Number.isFinite(fromTs) ? 4000 : 250));
    return true;
  }

  if (pathname === '/api/orders' && req.method === 'POST') {
    const body = parseJson(await readBody(req));
    const requestedDineInTableId = String(
      body.tableId || body.table_id || '',
    ).trim();
    const [restaurants, existingOrders, customersSeed, tableRows] = await Promise.all([
      dataStore.readRestaurants(),
      dataStore.readOrders(),
      extraStore.customers.read(),
      requestedDineInTableId
        ? dataStore.readTables()
        : Promise.resolve(null),
    ]);
    const restaurantId =
      body.restaurantId ||
      body.restaurant_id ||
      resolveRestaurantFromQuery(url, restaurants);
    const duplicate = findDuplicateOrder(existingOrders, body);
    if (duplicate) {
      const incomingTs =
        Date.parse(body.updatedAt || body.createdAt || 0) || 0;
      const existingTs =
        Date.parse(duplicate.updatedAt || duplicate.createdAt || 0) || 0;
      if (incomingTs > existingTs) {
        const merged = preferNewerOrder(duplicate, stampOfflineTx({ ...duplicate, ...body }, body));
        const patched = await dataStore.patchOrderById(duplicate.id, merged, existingOrders);
        sendJson(res, 200, patched || merged);
        return true;
      }
      sendJson(res, 200, duplicate);
      return true;
    }
    if (requestedDineInTableId && Array.isArray(tableRows)) {
      const requestedTable = tableRows.find(
        (table) =>
          String(table.restaurant_id || table.restaurantId) ===
            String(restaurantId) &&
          (String(table.id) === requestedDineInTableId ||
            String(table.number) === requestedDineInTableId),
      );
      if (
        requestedTable &&
        (requestedTable.status === 'awaiting_check' ||
          requestedTable.activeSession?.checkRequested === true)
      ) {
        sendJson(res, 409, {
          error: 'تم طلب حساب هذه الطاولة ولا يمكن إضافة أصناف جديدة',
          code: 'TABLE_AWAITING_CHECK',
        });
        return true;
      }
    }

    const deliveryZoneId = String(
      body.deliveryZoneId || body.delivery_zone_id || '',
    ).trim();
    const orderSource = String(body.orderSource || body.order_source || '').toLowerCase();
    const orderType = String(body.orderType || body.order_type || '').toLowerCase();
    const isDineInOrder =
      Boolean(requestedDineInTableId) ||
      orderSource.includes('dine') ||
      orderType.includes('dine');
    if (deliveryZoneId && !isDineInOrder) {
      const zones = filterByRestaurant(
        await extraStore.deliveryZones.read(),
        restaurantId,
      );
      const zone = zones.find((entry) => String(entry.id) === deliveryZoneId);
      const minOrder = Math.max(
        0,
        Number(zone?.minOrder ?? zone?.min_order ?? zone?.minimumOrder ?? 0) || 0,
      );
      if (minOrder > 0) {
        const subtotal = Number(
          body.subtotal ??
            body.subTotal ??
            body.itemsSubtotal ??
            body.items_subtotal ??
            0,
        );
        let effectiveSubtotal = Number.isFinite(subtotal) ? subtotal : 0;
        if (!(effectiveSubtotal > 0) && Array.isArray(body.items)) {
          effectiveSubtotal = body.items.reduce((sum, item) => {
            const line =
              Number(item.totalPrice ?? item.total_price ?? item.lineTotal) ||
              (Number(item.price ?? item.unitPrice ?? 0) || 0) *
                (Number(item.quantity ?? item.qty ?? 1) || 1);
            return sum + (Number(line) || 0);
          }, 0);
        }
        if (effectiveSubtotal + 1e-9 < minOrder) {
          sendJson(res, 400, {
            error: `الحد الأدنى للطلب في هذه المنطقة هو ${minOrder.toFixed(3)} د.ك`,
            code: 'MIN_ORDER_NOT_MET',
            minOrder,
            subtotal: effectiveSubtotal,
          });
          return true;
        }
      }
    }

    const offerIds = collectOfferIdsFromOrder(body);
    let orderPayload = { ...body };
    if (offerIds.length > 0) {
      const offers = filterByRestaurant(await extraStore.offers.read(), restaurantId)
        .map((offer) => normalizeOffer(offer, restaurantId));
      const exhaustedIds = findExhaustedOfferIds({
        offers,
        orders: existingOrders,
        offerIds,
        phone: body.phone,
        restaurantId,
      });
      if (exhaustedIds.length > 0) {
        orderPayload = repriceOrderIfOffersExhausted(body, exhaustedIds).body;
      } else if (!body.phone) {
        try {
          assertOffersUsageAllowed({
            offers,
            orders: existingOrders,
            offerIds,
            phone: body.phone,
            restaurantId,
          });
        } catch (error) {
          if (error && error.code === 'OFFER_PHONE_REQUIRED') {
            sendJson(res, error.statusCode || 400, {
              error: error.message,
              code: error.code,
            });
            return true;
          }
          throw error;
        }
      }
    }
    const createdAt = body.createdAt || new Date().toISOString();
    const createdStatus = persistOrderStatus(body.status || 'pending', 'pending');
    const ratingToken = createRatingToken();
    let created = stampFromOrderStatus(
      stampOfflineTx(
        {
          ...orderPayload,
          id: body.id || `ord_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
          restaurant_id: restaurantId,
          restaurantId,
          status: createdStatus,
          createdAt,
          created_at: createdAt,
          ratingToken,
          rating_token: ratingToken,
          isRated: false,
          is_rated: false,
        },
        body,
      ),
      createdStatus,
      createdAt,
    );
    try {
      const assignment = await assignTargetKitchen({
        body: created,
        restaurantId,
        auth: parseAuthHeader(req),
        deliveryZoneId: created.deliveryZoneId || created.delivery_zone_id,
      });
      if (assignment && assignment.targetKitchenId) {
        Object.assign(created, assignment);
      }
    } catch (error) {
      if (error && error.code === 'INVALID_TARGET_KITCHEN') {
        sendJson(res, 400, { error: error.message, code: error.code });
        return true;
      }
      throw error;
    }
    let customers = customersSeed;
    const requestedRedeem = Number(
      body.walletRedeemAmount ?? body.wallet_redeem_amount ?? 0,
    ) || 0;
    if (requestedRedeem > 0 && created.phone) {
      const redemption = redeemCustomerWallet(customers, {
        phone: created.phone,
        restaurantId,
        amount: requestedRedeem,
        orderId: created.id,
      });
      customers = redemption.customers;
      created.walletRedeemed = redemption.redeemed;
      created.wallet_redeemed = redemption.redeemed;
      const currentTotal = Number(created.totalPrice ?? created.total_price ?? 0) || 0;
      created.totalPrice = Math.max(0, Number((currentTotal - redemption.redeemed).toFixed(3)));
    }
    await dataStore.prependOrder(created, existingOrders);
    const dineInTableId = String(created.tableId || created.table_id || '').trim();
    if (dineInTableId && restaurantId) {
      try {
        const currentTableRows = tableRows || await dataStore.readTables();
        const attached = applyGuestOrderToTable(currentTableRows, {
          restaurantId,
          tableId: dineInTableId,
          items: created.items || [],
          customerName: created.customerName,
          phone: created.phone,
          orderId: created.id,
        });
        if (attached.changed) {
          await dataStore.writeTables(attached.tables);
        }
      } catch (error) {
        console.error('QR dine-in table attach failed:', error);
      }
    }
    if (created.phone) {
      customers = upsertCustomerFromSource(customers, created, restaurantId);
      await extraStore.customers.write(customers);
    }
    try {
      const settingsMap = await dataStore.readSettingsMap();
      const restaurantSettings =
        settingsMap.byRestaurant?.[restaurantId] || {};
      const restaurant = restaurants.find(
        (entry) => String(entry.id) === String(restaurantId),
      );
      const whatsapp = normalizeWhatsappSettings(restaurantSettings);
      const staffPhone =
        whatsapp.whatsappNumber ||
        restaurant?.whatsappNumber ||
        restaurant?.whatsapp_number ||
        '';
      const invoice = created.invoiceNumber || created.id;
      const messageBody =
        `طلب جديد #${invoice}\n${created.customerName || ''}\n` +
        `${Number(created.totalPrice || 0).toFixed(3)} د.ك`;
      sendWhatsAppNotification({
        to: staffPhone,
        messageBody,
        order: created,
      }).catch((error) => {
        console.error('WhatsApp staff notification failed:', error);
      });
    } catch (error) {
      console.error('WhatsApp staff notification failed:', error);
    }
    sendJson(res, 201, created);
    return true;
  }

  const orderStatusMatch = pathname.match(/^\/api\/orders\/([^/]+)\/status$/);
  if (orderStatusMatch && req.method === 'PATCH') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const orderId = decodeURIComponent(orderStatusMatch[1]);
    const orders = await dataStore.readOrders();
    const index = orders.findIndex((order) => String(order.id) === orderId);
    if (index === -1) {
      sendJson(res, 404, { error: 'Order not found' });
      return true;
    }
    const restaurantId = orders[index].restaurant_id || orders[index].restaurantId;
    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    if (isKitchen(auth)) {
      const kitchenId = String(auth.kitchenId || '').trim();
      if (!kitchenId || orderTargetKitchenId(orders[index]) !== kitchenId) {
        sendJson(res, 403, {
          error: 'Order is not assigned to this kitchen',
          code: 'KITCHEN_FORBIDDEN',
        });
        return true;
      }
      sendJson(res, 403, {
        error: 'Cashier must accept and complete orders; kitchen is view and print only',
        code: 'CASHIER_MUST_ACCEPT',
      });
      return true;
    }
    const body = parseJson(await readBody(req));
    const previous = orders[index];
    const previousStatus = previous.status;
    const requestedStatus = body.status || previous.status;
    const persistedStatus = persistOrderStatus(requestedStatus, previous.status);
    if (
      !isSuperAdmin(auth) &&
      isOrderHeldByDriver(previous) &&
      String(persistedStatus || '').toLowerCase() !== String(previousStatus || '').toLowerCase()
    ) {
      sendJson(res, 403, {
        error: 'الطلب بحوزة السائق - التحديث عبر تطبيق السائق فقط',
        code: 'DRIVER_CUSTODY',
      });
      return true;
    }
    let next = {
      ...previous,
      status: persistedStatus,
      updatedAt: new Date().toISOString(),
    };
    if (isAutoAcceptedStatus(requestedStatus)) {
      next.autoAccepted = true;
      next.auto_accepted = true;
      next.acceptedAt = next.acceptedAt || new Date().toISOString();
    }
    next = attachReceivingCashier(next, previous, {
      ...body,
      status: persistedStatus,
    });
    next = attachAcceptedBy(next, previous, auth, body, persistedStatus);
    next = stampFromOrderStatus(next, persistedStatus);
    const nextStatus = String(persistedStatus || '').toLowerCase();
    if (
      String(previousStatus || '').toLowerCase() === 'pending' &&
      nextStatus === 'confirmed'
    ) {
      try {
        const dispatched = await enqueueDeliveryForAcceptedOrder(next, {
          readRestaurants: () => dataStore.readRestaurants(),
          readDeliveryZones: () => dataStore.readDeliveryZones(),
          readDeliveryRequests: () => dataStore.readDeliveryRequests(),
          writeDeliveryRequests: (value) => dataStore.writeDeliveryRequests(value),
          readDrivers: () => dataStore.readDrivers(),
        });
        if (dispatched) {
          next.delivery_status = 'driver_pending';
          next.delivery_request_id = dispatched.id;
          next.driver_fee = Number(dispatched.driver_fee ?? 0) || 0;
          next.assigned_driver_fee = next.driver_fee;
        }
      } catch (_) {}
    }
    const prevStatus = String(previousStatus || '').toLowerCase();
    const needsShiftIo =
      prevStatus === 'pending' ||
      nextStatus === 'cancelled' ||
      nextStatus === 'canceled';
    if (needsShiftIo) {
      const shifts = await extraStore.shiftSessions.read();
      const bound = applyShiftBindingOnAccept({
        order: next,
        previousOrder: previous,
        previousStatus,
        nextStatus: persistedStatus,
        shifts,
        restaurantId,
        auth,
        body,
      });
      if (bound.bound) {
        next = bound.order;
      }
      const cancelled = applyShiftAdjustmentOnCancel({
        order: next,
        previousStatus,
        shifts: bound.shifts || shifts,
      });
      next = cancelled.order || next;
      if (cancelled.shifts) {
        await extraStore.shiftSessions.write(cancelled.shifts);
      }
    }
    if (isDeliveredStatus(next.status)) {
      const settingsMap = await dataStore.readSettingsMap();
      const settings = settingsMap.byRestaurant?.[restaurantId] || {};
      const customers = await extraStore.customers.read();
      const loyalty = applyLoyaltyCashbackToOrder(next, settings, customers, restaurantId);
      next = loyalty.order;
      if (loyalty.customers) {
        await extraStore.customers.write(loyalty.customers);
      }
    }
    orders[index] = next;
    const patched = await dataStore.patchOrderById(orderId, next, orders);
    sendJson(res, 200, patched || next);
    return true;
  }

  const orderKitchenMatch = pathname.match(/^\/api\/orders\/([^/]+)\/kitchen$/);
  if (orderKitchenMatch && req.method === 'PATCH') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const orderId = decodeURIComponent(orderKitchenMatch[1]);
    const orders = await dataStore.readOrders();
    const index = orders.findIndex((order) => String(order.id) === orderId);
    if (index === -1) {
      sendJson(res, 404, { error: 'Order not found' });
      return true;
    }
    const restaurantId = orders[index].restaurant_id || orders[index].restaurantId;
    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    if (isKitchen(auth)) {
      sendJson(res, 403, {
        error: 'Kitchen stations cannot reassign orders',
        code: 'KITCHEN_FORBIDDEN',
      });
      return true;
    }
    const body = parseJson(await readBody(req));
    try {
      const assignment = await assignTargetKitchen({
        body: { ...orders[index], ...body, orderType: orders[index].orderType || orders[index].order_type },
        restaurantId,
        auth,
        deliveryZoneId: orders[index].deliveryZoneId || orders[index].delivery_zone_id,
      });
      if (!assignment || !assignment.targetKitchenId) {
        sendJson(res, 400, { error: 'No kitchen configured' });
        return true;
      }
      const next = { ...orders[index], ...assignment, updatedAt: new Date().toISOString() };
      orders[index] = next;
      const patched = await dataStore.patchOrderById(orderId, next, orders);
      sendJson(res, 200, { order: patched || next });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid kitchen' });
    }
    return true;
  }

  if (pathname === '/api/store-assets' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const body = parseJson(await readBody(req));
    const driverId = String(body.driverId || body.driver_id || '').trim();
    const requestedKind = String(body.kind || 'hero').trim().toLowerCase();
    if (driverId) {
      if (!isSuperAdmin(auth)) {
        sendJson(res, 403, { error: 'رفع مستندات السائق للسوبر أدمن فقط' });
        return true;
      }
      const kind = requestedKind === 'license' || requestedKind === 'driver_license' ? 'license' : 'civil_id';
      const contentType = String(body.contentType || body.content_type || 'image/jpeg')
        .split(';')[0]
        .trim()
        .toLowerCase();
      if (!contentType.startsWith('image/')) {
        sendJson(res, 400, { error: 'Expected an image file' });
        return true;
      }
      const raw = String(body.data || body.base64 || '').replace(/^data:image\/[a-zA-Z0-9.+-]+;base64,/, '');
      let buffer;
      try {
        buffer = Buffer.from(raw, 'base64');
      } catch {
        sendJson(res, 400, { error: 'Invalid image data' });
        return true;
      }
      if (!buffer.length || buffer.length > 2 * 1024 * 1024) {
        sendJson(res, 413, { error: 'Image too large. Use a smaller photo (max 2MB).' });
        return true;
      }
      const id = `drv_${String(driverId).replace(/[^\w.-]/g, '_')}_${kind}`;
      const assets = await dataStore.readStoreAssets();
      assets[id] = {
        driverId,
        kind,
        contentType,
        data: buffer.toString('base64'),
        updatedAt: new Date().toISOString(),
      };
      await dataStore.writeStoreAssets(assets);
      sendJson(res, 200, { ok: true, id, url: `/api/store-assets/${id}` });
      return true;
    }
    const restaurantId =
      body.restaurantId ||
      body.restaurant_id ||
      (await resolveScopedRestaurantId(req, url, auth));
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }
    const kind = String(body.kind || 'hero').trim().toLowerCase() === 'logo' ? 'logo' : 'hero';
    const contentType = String(body.contentType || body.content_type || 'image/jpeg')
      .split(';')[0]
      .trim()
      .toLowerCase();
    if (!contentType.startsWith('image/')) {
      sendJson(res, 400, { error: 'Expected an image file' });
      return true;
    }
    const raw = String(body.data || body.base64 || '').replace(/^data:image\/[a-zA-Z0-9.+-]+;base64,/, '');
    let buffer;
    try {
      buffer = Buffer.from(raw, 'base64');
    } catch {
      sendJson(res, 400, { error: 'Invalid image data' });
      return true;
    }
    if (!buffer.length || buffer.length > 2 * 1024 * 1024) {
      sendJson(res, 413, { error: 'Image too large. Use a smaller photo (max 2MB).' });
      return true;
    }
    const id = `${String(restaurantId).replace(/[^\w.-]/g, '_')}_${kind}`;
    const assets = await dataStore.readStoreAssets();
    assets[id] = {
      restaurantId,
      kind,
      contentType,
      data: buffer.toString('base64'),
      updatedAt: new Date().toISOString(),
    };
    await dataStore.writeStoreAssets(assets);
    sendJson(res, 200, {
      ok: true,
      id,
      url: `/api/store-assets/${id}`,
    });
    return true;
  }

  const storeAssetMatch = pathname.match(/^\/api\/store-assets\/([^/]+)$/);
  if (storeAssetMatch && (req.method === 'GET' || req.method === 'HEAD')) {
    const id = decodeURIComponent(storeAssetMatch[1]);
    const assets = await dataStore.readStoreAssets();
    const asset = assets[id];
    if (!asset || !asset.data) {
      sendJson(res, 404, { error: 'Image not found' });
      return true;
    }
    const buffer = Buffer.from(String(asset.data), 'base64');
    applyCorsHeaders(req, res);
    res.statusCode = 200;
    res.setHeader('Content-Type', asset.contentType || 'image/jpeg');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.setHeader('Access-Control-Allow-Origin', '*');
    if (req.method === 'HEAD') {
      res.end();
    } else {
      res.end(buffer);
    }
    return true;
  }

  if (pathname === '/api/settings' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId =
      readRestaurantIdParam(req, url) ||
      resolveRestaurantFromQuery(url, restaurants);
    const map = await dataStore.readSettingsMap();
    const stored = map.byRestaurant?.[restaurantId] || {};
    const payload = { ...defaultSettingsPayload(), ...stored };
    const restaurant = restaurants.find((entry) => String(entry.id) === String(restaurantId));
    sendJson(res, 200, {
      ...payload,
      ...normalizeWhatsappSettings(payload),
      tableManagementEnabled: isTableManagementEnabled(restaurant),
      kitchenManagementEnabled: isKitchenManagementEnabled(restaurant),
      deliveryManagementEnabled: isDeliveryManagementEnabled(restaurant),
      features: {
        tableManagement: isTableManagementEnabled(restaurant),
        kitchenManagement: isKitchenManagementEnabled(restaurant),
        deliveryManagement: isDeliveryManagementEnabled(restaurant),
      },
    });
    return true;
  }

  if (pathname === '/api/settings' && req.method === 'PUT') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const body = parseJson(await readBody(req));
    const restaurantId =
      body.restaurantId ||
      body.restaurant_id ||
      (await resolveScopedRestaurantId(req, url, auth));
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const map = await dataStore.readSettingsMap();
    const current = map.byRestaurant?.[restaurantId] || defaultSettingsPayload();
    const next = {
      ...current,
      ...body,
      ...normalizeWhatsappSettings({ ...current, ...body }),
      updatedAt: new Date().toISOString(),
    };
    next.dynamicMenuSortingEnabled =
      next.dynamicMenuSortingEnabled === true ||
      next.dynamic_menu_sorting_enabled === true ||
      next.enable_dynamic_menu === true ||
      next.enableDynamicMenu === true;
    next.enable_dynamic_menu = next.dynamicMenuSortingEnabled;
    next.paydayStartDay = clampPaydayStartDay(
      next.paydayStartDay ?? next.payday_start_day ?? 1,
    );
    delete next.dynamic_menu_sorting_enabled;
    delete next.payday_start_day;
    delete next.restaurantId;
    delete next.restaurant_id;
    delete next.tableManagementEnabled;
    delete next.tableManagement;
    delete next.kitchenManagementEnabled;
    delete next.kitchenManagement;
    delete next.deliveryManagementEnabled;
    delete next.deliveryManagement;
    delete next.features;
    map.byRestaurant = map.byRestaurant || {};
    map.byRestaurant[restaurantId] = next;
    await dataStore.writeSettingsMap(map);

    const restaurants = await dataStore.readRestaurants();
    const restaurantIndex = restaurants.findIndex(
      (entry) => String(entry.id) === String(restaurantId),
    );
    if (restaurantIndex >= 0) {
      const logo = String(next.logoUrl || next.logo_url || '').trim();
      const heroImage = String(
        next.heroImageUrl || next.hero_image_url || next.coverUrl || '',
      ).trim();
      const description = String(
        next.restaurantDescription || next.restaurant_description || '',
      ).trim();
      restaurants[restaurantIndex] = {
        ...restaurants[restaurantIndex],
        logoUrl: logo,
        logo_url: logo,
        heroImageUrl: heroImage,
        hero_image_url: heroImage,
        coverUrl: heroImage,
        description,
        description_ar: description,
        descriptionAr: description,
      };
      await dataStore.writeRestaurants(restaurants);
    }

    sendJson(res, 200, next);
    return true;
  }

  if (pathname === '/api/analytics/top-items' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId = resolveRestaurantFromQuery(url, restaurants);
    const days = Number(url.searchParams.get('days') || 90);
    const limit = Number(url.searchParams.get('limit') || 12);
    const orders = await dataStore.readOrders();
    let result = computeTopMenuItems(orders, [], restaurantId, { days, limit });
    if (!result.items?.length) {
      result = computeTopMenuItems(
        orders,
        filterByRestaurant(await dataStore.readItems(), restaurantId),
        restaurantId,
        { days, limit },
      );
    }
    sendJson(
      res,
      200,
      (result.items || []).map((entry) => entry.menuItemId),
    );
    return true;
  }

  if (pathname === '/api/analytics/daily-sales' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = resolveReportRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    sendJson(
      res,
      200,
      computeDailySalesAnalytics(await dataStore.readOrders(), restaurantId, {
        days: Number(url.searchParams.get('days') || 1),
      }),
    );
    return true;
  }

  if (pathname === '/api/analytics/pnl' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = resolveReportRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    try {
      const expenses =
        typeof dataStore.readExpenses === 'function'
          ? await dataStore.readExpenses()
          : [];
      sendJson(
        res,
        200,
        computeProfitAndLoss(await dataStore.readOrders(), expenses, restaurantId, {
          days: Number(url.searchParams.get('days') || 30),
        }),
      );
    } catch (error) {
      console.error('[analytics/pnl]', error?.message || error);
      sendJson(res, 500, { error: 'PNL_COMPUTE_FAILED', message: error?.message || 'pnl failed' });
    }
    return true;
  }

  if (pathname === '/api/analytics/food-cost' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = resolveReportRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    sendJson(
      res,
      200,
      computeFoodCostReport(
        await dataStore.readOrders(),
        filterByRestaurant(await dataStore.readItems(), restaurantId),
        restaurantId,
        { days: Number(url.searchParams.get('days') || 30) },
      ),
    );
    return true;
  }

  if (pathname === '/api/analytics/upsell' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = resolveReportRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    sendJson(
      res,
      200,
      computeUpsellAnalytics(
        await extraStore.upsellEvents.read(),
        await dataStore.readOrders(),
        restaurantId,
        { days: Number(url.searchParams.get('days') || 30) },
      ),
    );
    return true;
  }

  if (pathname === '/api/analytics/upsell-events' && req.method === 'POST') {
    const body = parseJson(await readBody(req));
    const restaurants = await dataStore.readRestaurants();
    const restaurantId =
      body.restaurantId ||
      body.restaurant_id ||
      resolveRestaurantFromQuery(url, restaurants);
    const incoming = Array.isArray(body.events) ? body.events : [];
    const events = await extraStore.upsellEvents.read();
    for (const event of incoming) {
      events.push(normalizeIncomingEvent({ ...event, restaurantId }, restaurantId));
    }
    await extraStore.upsellEvents.write(trimEvents(events));
    sendJson(res, 200, { ok: true, stored: incoming.length });
    return true;
  }

  if (pathname === '/api/loyalty/cashback' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId = resolveRestaurantFromQuery(url, restaurants);
    const orderTotal = Number(url.searchParams.get('orderTotal') || 0);
    const map = await dataStore.readSettingsMap();
    sendJson(
      res,
      200,
      previewEarnedCashback(orderTotal, map.byRestaurant?.[restaurantId] || {}),
    );
    return true;
  }

  if (pathname === '/api/talabat/import' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const body = parseJson(await readBody(req));
    const restaurantId =
      body.restaurantId ||
      body.restaurant_id ||
      (await resolveScopedRestaurantId(req, url, auth));
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const sourceUrl = String(body.url || body.menuUrl || '').trim();
    if (!sourceUrl) {
      sendJson(res, 400, { error: 'رابط Talabat مطلوب' });
      return true;
    }
    try {
      console.log(`[talabat/import] restaurant=${restaurantId} url=${sourceUrl}`);
      const scraped = await scrapeTalabatMenu(sourceUrl);
      let items = await dataStore.readItems();
      const others = items.filter(
        (item) => String(item.restaurant_id || item.restaurantId) !== String(restaurantId),
      );
      const existing = items.filter(
        (item) => String(item.restaurant_id || item.restaurantId) === String(restaurantId),
      );
      let added = 0;
      let updated = 0;
      const merged = [...existing];
      const talabatKeyOf = (entry) => {
        const raw = entry?.talabat_id ?? entry?.talabatId;
        if (raw == null || raw === '') return null;
        return String(raw);
      };
      const categoryFirstSeen = [];
      const categorySeen = new Set();
      let scrapeIndex = 0;
      for (const scrapedItem of scraped.items || []) {
        const scrapedKey = talabatKeyOf(scrapedItem);
        const scrapedName = String(scrapedItem.name || '').trim().toLowerCase();
        const categoryName = String(
          scrapedItem.categoryName || scrapedItem.category_name || '',
        ).trim();
        if (categoryName && !categorySeen.has(categoryName.toLowerCase())) {
          categorySeen.add(categoryName.toLowerCase());
          categoryFirstSeen.push(categoryName);
        }
        const matchIndex = merged.findIndex((item) => {
          const existingKey = talabatKeyOf(item);
          if (scrapedKey && existingKey) return scrapedKey === existingKey;
          if (scrapedKey || existingKey) return false;
          return String(item.name || '').trim().toLowerCase() === scrapedName;
        });
        const displayOrder =
          matchIndex === -1
            ? scrapeIndex
            : Number(
                merged[matchIndex].display_order ??
                  merged[matchIndex].displayOrder ??
                  scrapeIndex,
              );
        const normalized = normalizeIncomingItem(
          {
            ...scrapedItem,
            display_order: displayOrder,
            displayOrder,
          },
          restaurantId,
          {
            id:
              matchIndex === -1
                ? nextNumericItemId(items.concat(merged))
                : merged[matchIndex].id,
            ...(matchIndex === -1 ? {} : merged[matchIndex]),
          },
        );
        normalized.display_order = displayOrder;
        normalized.displayOrder = displayOrder;
        if (matchIndex === -1) {
          merged.push(normalized);
          added += 1;
        } else {
          merged[matchIndex] = {
            ...merged[matchIndex],
            ...normalized,
            id: merged[matchIndex].id,
            display_order: displayOrder,
            displayOrder,
          };
          updated += 1;
        }
        scrapeIndex += 1;
      }
      const migrated = migrateMenuItems(merged).items;
      let withImages = migrated;
      if (body.downloadImages !== false) {
        try {
          withImages = await persistMenuItemsImages(migrated);
        } catch (imageError) {
          console.warn(
            '[talabat/import] image persist skipped:',
            imageError?.message || imageError,
          );
          withImages = migrated;
        }
      }
      await dataStore.writeItems([...others, ...withImages]);
      try {
        const allCategories = await dataStore.readMenuCategories();
        const othersCats = allCategories.filter(
          (entry) =>
            String(entry.restaurant_id || entry.restaurantId) !== String(restaurantId),
        );
        const scopedCats = allCategories.filter(
          (entry) =>
            String(entry.restaurant_id || entry.restaurantId) === String(restaurantId),
        );
        const synced = syncCategoriesFromItemNames(
          scopedCats,
          restaurantId,
          categoryFirstSeen.length
            ? categoryFirstSeen
            : withImages.map((item) => item.category_name || item.categoryName),
        );
        await dataStore.writeMenuCategories([...othersCats, ...synced.categories]);
      } catch (catError) {
        console.warn('[talabat/import] category sync skipped:', catError?.message || catError);
      }
      console.log(
        `[talabat/import] ok restaurant=${restaurantId} added=${added} updated=${updated} total=${withImages.length}`,
      );
      sendJson(res, 200, {
        added,
        updated,
        skipped: 0,
        synced: withImages.length,
        total: withImages.length,
        menuUrl: scraped.menuUrl,
      });
    } catch (error) {
      console.error('[talabat/import] failed:', error?.message || error);
      sendJson(res, 400, { error: error.message || 'Talabat import failed' });
    }
    return true;
  }

  if (pathname === '/api/items/reorder' && req.method === 'PUT') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    try {
      const body = parseJson(await readBody(req));
      const restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        (await resolveScopedRestaurantId(req, url, auth));
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }
      const orderedIds = (body.orderedIds || body.ordered_ids || []).map(String);
      if (!orderedIds.length) {
        sendJson(res, 400, { error: 'orderedIds مطلوب' });
        return true;
      }
      const result = await dataStore.applyItemDisplayOrder(restaurantId, orderedIds);
      console.log(
        `[items/reorder] restaurant=${restaurantId} count=${result.count}`,
      );
      sendJson(res, 200, { ok: true, count: result.count });
    } catch (error) {
      console.error('[items/reorder] failed:', error?.message || error);
      sendJson(res, 400, { error: error.message || 'Reorder failed' });
    }
    return true;
  }

  if (pathname === '/api/delivery-zones' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId =
      readRestaurantIdParam(req, url) ||
      resolveRestaurantFromQuery(url, restaurants);
    const zones = filterByRestaurant(await extraStore.deliveryZones.read(), restaurantId);
    sendJson(res, 200, zones);
    return true;
  }

  if (pathname === '/api/delivery-zones' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const body = parseJson(await readBody(req));
    const restaurantId =
      body.restaurantId ||
      body.restaurant_id ||
      (await resolveScopedRestaurantId(req, url, auth));
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const zone = {
      id: body.id || `zone_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      restaurant_id: restaurantId,
      restaurantId,
      governorate: body.governorate || '',
      areaName: body.areaName || body.area_name || '',
      deliveryFee: Number(body.deliveryFee ?? body.delivery_fee ?? 0),
      minOrder: Math.max(0, Number(body.minOrder ?? body.min_order ?? body.minimumOrder ?? body.minimum_order ?? 0) || 0),
      min_order: Math.max(0, Number(body.minOrder ?? body.min_order ?? body.minimumOrder ?? body.minimum_order ?? 0) || 0),
      driverDeliveryFee: Number(body.driverDeliveryFee ?? body.driver_delivery_fee ?? body.deliveryFee ?? body.delivery_fee ?? 0),
      platformMargin: Number(body.platformMargin ?? body.platform_margin ?? 0),
      isActive: body.isActive !== false,
      defaultKitchenId: body.defaultKitchenId || body.default_kitchen_id || null,
      default_kitchen_id: body.defaultKitchenId || body.default_kitchen_id || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    const zones = await extraStore.deliveryZones.read();
    zones.push(zone);
    await extraStore.deliveryZones.write(zones);
    sendJson(res, 201, zone);
    return true;
  }

  if (pathname === '/api/delivery-zones/clone-from' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      authError(res, 403, 'Super admin only');
      return true;
    }
    const body = parseJson(await readBody(req));
    const sourceRestaurantId = String(
      body.sourceRestaurantId || body.source_restaurant_id || '',
    ).trim();
    if (!sourceRestaurantId) {
      sendJson(res, 400, { error: 'sourceRestaurantId is required' });
      return true;
    }
    const restaurants = await dataStore.readRestaurants();
    const requestedTargets = Array.isArray(body.targetRestaurantIds || body.target_restaurant_ids)
      ? (body.targetRestaurantIds || body.target_restaurant_ids).map((id) => String(id).trim()).filter(Boolean)
      : [];
    const targets = (requestedTargets.length
      ? restaurants.filter((r) => requestedTargets.includes(String(r.id)))
      : restaurants
    ).filter((r) => String(r.id) !== sourceRestaurantId);

    const allZones = await extraStore.deliveryZones.read();
    const sourceZones = allZones.filter(
      (zone) =>
        String(zone.restaurant_id || zone.restaurantId) === sourceRestaurantId &&
        zone.isActive !== false,
    );
    if (!sourceZones.length) {
      sendJson(res, 404, { error: 'No source delivery zones found' });
      return true;
    }

    const zoneKey = (zone) =>
      `${String(zone.governorate || '').trim()}|${String(zone.areaName || zone.area_name || '').trim()}`;

    const templateByKey = new Map();
    for (const zone of sourceZones) {
      const key = zoneKey(zone);
      if (!key.endsWith('|') && key !== '|') templateByKey.set(key, zone);
    }

    const now = new Date().toISOString();
    const nextZones = [...allZones];
    const summary = [];

    for (const restaurant of targets) {
      const restaurantId = String(restaurant.id);
      let added = 0;
      let updated = 0;
      for (const [key, source] of templateByKey.entries()) {
        const deliveryFee = Number(source.deliveryFee ?? source.delivery_fee ?? 0) || 0;
        const minOrder = Math.max(
          0,
          Number(source.minOrder ?? source.min_order ?? source.minimumOrder ?? 0) || 0,
        );
        const driverDeliveryFee = Number(
          source.driverDeliveryFee ?? source.driver_delivery_fee ?? deliveryFee,
        );
        const platformMargin = Number(source.platformMargin ?? source.platform_margin ?? 0) || 0;
        const existingIndex = nextZones.findIndex(
          (zone) =>
            String(zone.restaurant_id || zone.restaurantId) === restaurantId &&
            zoneKey(zone) === key,
        );
        if (existingIndex >= 0) {
          const existing = nextZones[existingIndex];
          nextZones[existingIndex] = {
            ...existing,
            governorate: source.governorate || existing.governorate,
            areaName: source.areaName || source.area_name || existing.areaName,
            area_name: source.areaName || source.area_name || existing.areaName,
            deliveryFee,
            delivery_fee: deliveryFee,
            minOrder,
            min_order: minOrder,
            driverDeliveryFee,
            driver_delivery_fee: driverDeliveryFee,
            platformMargin,
            platform_margin: platformMargin,
            isActive: true,
            restaurant_id: restaurantId,
            restaurantId,
            updatedAt: now,
          };
          updated += 1;
          continue;
        }
        nextZones.push({
          id: `zone_${Date.now().toString(36)}_${restaurantId.slice(-6)}_${Math.random()
            .toString(36)
            .slice(2, 8)}_${added}`,
          restaurant_id: restaurantId,
          restaurantId,
          governorate: source.governorate || '',
          areaName: source.areaName || source.area_name || '',
          area_name: source.areaName || source.area_name || '',
          deliveryFee,
          delivery_fee: deliveryFee,
          minOrder,
          min_order: minOrder,
          driverDeliveryFee,
          driver_delivery_fee: driverDeliveryFee,
          platformMargin,
          platform_margin: platformMargin,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        });
        added += 1;
      }
      summary.push({
        restaurantId,
        name: restaurant.name || restaurantId,
        added,
        updated,
        totalZones: nextZones.filter(
          (zone) => String(zone.restaurant_id || zone.restaurantId) === restaurantId,
        ).length,
      });
    }

    await extraStore.deliveryZones.write(nextZones);
    sendJson(res, 200, {
      ok: true,
      sourceRestaurantId,
      sourceZoneCount: templateByKey.size,
      targets: summary,
    });
    return true;
  }

  const zoneMatch = pathname.match(/^\/api\/delivery-zones\/([^/]+)$/);
  if (zoneMatch && (req.method === 'PUT' || req.method === 'DELETE')) {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const zoneId = decodeURIComponent(zoneMatch[1]);
    const zones = await extraStore.deliveryZones.read();
    const index = zones.findIndex((zone) => String(zone.id) === zoneId);
    if (index === -1) {
      sendJson(res, 404, { error: 'Delivery zone not found' });
      return true;
    }
    const restaurantId = zones[index].restaurant_id || zones[index].restaurantId;
    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    if (req.method === 'DELETE') {
      zones.splice(index, 1);
      await extraStore.deliveryZones.write(zones);
      sendJson(res, 200, { ok: true });
      return true;
    }
    const body = parseJson(await readBody(req));
    const nextKitchenId =
      body.defaultKitchenId !== undefined || body.default_kitchen_id !== undefined
        ? body.defaultKitchenId || body.default_kitchen_id || null
        : zones[index].defaultKitchenId || zones[index].default_kitchen_id || null;
    const nextMinOrder = Math.max(
      0,
      Number(
        body.minOrder ??
          body.min_order ??
          body.minimumOrder ??
          body.minimum_order ??
          zones[index].minOrder ??
          zones[index].min_order ??
          0,
      ) || 0,
    );
    zones[index] = {
      ...zones[index],
      ...body,
      restaurant_id: restaurantId,
      areaName: body.areaName || body.area_name || zones[index].areaName,
      deliveryFee: Number(body.deliveryFee ?? body.delivery_fee ?? zones[index].deliveryFee),
      minOrder: nextMinOrder,
      min_order: nextMinOrder,
      driverDeliveryFee: Number(
        body.driverDeliveryFee ??
          body.driver_delivery_fee ??
          zones[index].driverDeliveryFee ??
          zones[index].deliveryFee,
      ),
      platformMargin: Number(
        body.platformMargin ?? body.platform_margin ?? zones[index].platformMargin ?? 0,
      ),
      defaultKitchenId: nextKitchenId,
      default_kitchen_id: nextKitchenId,
      updatedAt: new Date().toISOString(),
    };
    await extraStore.deliveryZones.write(zones);
    sendJson(res, 200, zones[index]);
    return true;
  }

  if (pathname === '/api/offers/check-usage' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId =
      readRestaurantIdParam(req, url) ||
      resolveRestaurantFromQuery(url, restaurants);
    const offerId = String(url.searchParams.get('offer_id') || url.searchParams.get('offerId') || '').trim();
    const phone = url.searchParams.get('phone') || '';
    if (!offerId) {
      sendJson(res, 400, { error: 'offer_id is required' });
      return true;
    }
    const offers = filterByRestaurant(await extraStore.offers.read(), restaurantId)
      .map((offer) => normalizeOffer(offer, restaurantId));
    const offer = offers.find((entry) => String(entry.id) === offerId);
    if (!offer) {
      sendJson(res, 404, { error: 'Offer not found', allowed: false });
      return true;
    }
    const orders = await dataStore.readOrders();
    const result = evaluateOfferUsage({
      offer,
      orders,
      phone,
      restaurantId,
    });
    sendJson(res, result.allowed ? 200 : 409, {
      allowed: result.allowed,
      used: result.used,
      limit: result.limit,
      offerId,
      error: result.error,
      code: result.code,
    });
    return true;
  }

  if (pathname === '/api/offers' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId =
      readRestaurantIdParam(req, url) ||
      resolveRestaurantFromQuery(url, restaurants);
    const includeInactive = url.searchParams.get('includeInactive') === '1';
    const offers = filterByRestaurant(await extraStore.offers.read(), restaurantId)
      .map((offer) => normalizeOffer(offer, restaurantId))
      .filter((offer) => includeInactive || isOfferLive(offer));
    sendJson(res, 200, offers);
    return true;
  }

  if (pathname === '/api/admin/offers' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const offers = filterByRestaurant(await extraStore.offers.read(), restaurantId)
      .map((offer) => normalizeOffer(offer, restaurantId));
    sendJson(res, 200, offers);
    return true;
  }

  if (pathname === '/api/admin/offers' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const body = parseJson(await readBody(req));
    const action = String(body.action || (body.id ? 'update' : 'create')).toLowerCase();
    const restaurantId =
      body.restaurantId ||
      body.restaurant_id ||
      (await resolveScopedRestaurantId(req, url, auth));
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const offers = await extraStore.offers.read();

    if (action === 'delete') {
      const offerId = String(body.id || '');
      const index = offers.findIndex((offer) => String(offer.id) === offerId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Offer not found' });
        return true;
      }
      const existingRestaurant = offers[index].restaurant_id || offers[index].restaurantId;
      if (!assertRestaurantAccess(auth, existingRestaurant, authError, res)) return true;
      const removed = offers.splice(index, 1)[0];
      await extraStore.offers.write(offers);
      sendJson(res, 200, { ok: true, id: removed.id });
      return true;
    }

    if (action === 'update') {
      const offerId = String(body.id || '');
      const index = offers.findIndex((offer) => String(offer.id) === offerId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Offer not found' });
        return true;
      }
      const existingRestaurant = offers[index].restaurant_id || offers[index].restaurantId;
      if (!assertRestaurantAccess(auth, existingRestaurant, authError, res)) return true;
      const next = normalizeOffer({ ...offers[index], ...body, id: offerId }, existingRestaurant);
      offers[index] = next;
      await extraStore.offers.write(offers);
      sendJson(res, 200, next);
      return true;
    }

    const created = normalizeOffer({ ...body, id: body.id || undefined }, restaurantId);
    if (!created.title) {
      sendJson(res, 400, { error: 'Offer title is required' });
      return true;
    }
    offers.push(created);
    await extraStore.offers.write(offers);
    sendJson(res, 201, created);
    return true;
  }

  const adminOfferMatch = pathname.match(/^\/api\/admin\/offers\/([^/]+)$/);
  if (adminOfferMatch && (req.method === 'PUT' || req.method === 'DELETE')) {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const offerId = decodeURIComponent(adminOfferMatch[1]);
    const offers = await extraStore.offers.read();
    const index = offers.findIndex((offer) => String(offer.id) === offerId);
    if (index === -1) {
      sendJson(res, 404, { error: 'Offer not found' });
      return true;
    }
    const restaurantId = offers[index].restaurant_id || offers[index].restaurantId;
    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    if (req.method === 'DELETE') {
      offers.splice(index, 1);
      await extraStore.offers.write(offers);
      sendJson(res, 200, { ok: true });
      return true;
    }
    const body = parseJson(await readBody(req));
    offers[index] = normalizeOffer({ ...offers[index], ...body, id: offerId }, restaurantId);
    await extraStore.offers.write(offers);
    sendJson(res, 200, offers[index]);
    return true;
  }

  if (pathname === '/api/customers/identify' && req.method === 'POST') {
    try {
      const body = parseJson(await readBody(req));
      const restaurants = await dataStore.readRestaurants();
      const restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        resolveRestaurantFromQuery(url, restaurants);
      const phone = body.phone || '';
      const customers = migrateCustomersFromOrders(
        await extraStore.customers.read(),
        await dataStore.readOrders(),
      );
      const identified = identifyCustomerByPhone(customers, restaurantId, phone);
      await extraStore.customers.write(identified.customers);
      const settingsMap = await dataStore.readSettingsMap();
      const loyalty = normalizeLoyaltySettings(
        settingsMap.byRestaurant?.[restaurantId] || {},
      );
      const profile = customerProfileFromRecord(identified.customer);
      sendJson(res, 200, {
        ok: true,
        isNew: identified.isNew,
        isReturning: !identified.isNew && Number(profile.totalOrders || 0) > 0,
        profile,
        loyalty,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid phone' });
    }
    return true;
  }

  if (pathname === '/api/customers/lookup' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId = resolveRestaurantFromQuery(url, restaurants);
    const phone = url.searchParams.get('phone') || '';
    const customers = migrateCustomersFromOrders(
      await extraStore.customers.read(),
      await dataStore.readOrders(),
    );
    const customer = findCustomerByPhone(customers, restaurantId, phone);
    if (!customer) {
      sendJson(res, 404, { error: 'Customer not found' });
      return true;
    }
    sendJson(res, 200, { profile: customerProfileFromRecord(customer) });
    return true;
  }

  if (pathname === '/api/customers' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const customers = migrateCustomersFromOrders(
      await extraStore.customers.read(),
      await dataStore.readOrders(),
    );
    sendJson(
      res,
      200,
      enrichCustomersForRestaurant(customers, await dataStore.readOrders(), restaurantId),
    );
    return true;
  }

  const customerMatch = pathname.match(/^\/api\/customers\/([^/]+)$/);
  if (customerMatch && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const customerId = decodeURIComponent(customerMatch[1]);
    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const customers = await extraStore.customers.read();
    const customer = customers.find((entry) => String(entry.id) === customerId);
    if (!customer) {
      sendJson(res, 404, { error: 'Customer not found' });
      return true;
    }
    const orders = filterByRestaurant(await dataStore.readOrders(), restaurantId).filter(
      (order) => String(order.phone || '') === String(customer.phone || ''),
    );
    sendJson(res, 200, { customer, orders });
    return true;
  }

  if (pathname.startsWith('/og/') || (req.method === 'GET' && isSocialCrawler(req.headers['user-agent']))) {
    const parsed = parseRestaurantOgRequest(pathname);
    if (parsed?.slug) {
      const { slug, kind } = parsed;
      const restaurants = await dataStore.readRestaurants();
      const restaurant = restaurants.find(
        (entry) => String(entry.slug || '').toLowerCase() === slug.toLowerCase(),
      );
      if (restaurant) {
        const items = filterByRestaurant(await dataStore.readItems(), restaurant.id);
        const map = await dataStore.readSettingsMap();
        const settings = map.byRestaurant?.[restaurant.id] || {};
        const linkHub =
          settings.linkHub && typeof settings.linkHub === 'object'
            ? settings.linkHub
            : settings.link_hub && typeof settings.link_hub === 'object'
              ? settings.link_hub
              : {};
        const restaurantDescription = String(
          settings.restaurantDescription ||
            settings.restaurant_description ||
            restaurant.description ||
            restaurant.description_ar ||
            '',
        ).trim();
        const hubTagline = String(linkHub.tagline || linkHub.description || '').trim();
        const hubDisplayName = String(
          linkHub.displayName || linkHub.display_name || '',
        ).trim();
        const description =
          kind === 'links'
            ? hubTagline || restaurantDescription
            : restaurantDescription;
        const logoUrl = String(
          settings.logoUrl ||
            settings.logo_url ||
            restaurant.logoUrl ||
            restaurant.logo_url ||
            '',
        ).trim();
        const frontendOrigin = requestFrontendOrigin(req);
        const menuPath = kind === 'links' ? `/r/${slug}/links` : `/${slug}`;
        const ogOptions = {
          slug,
          kind,
          items,
          displayName: hubDisplayName || restaurant.name,
          description: description || undefined,
          ogDescription: description || undefined,
          frontendOrigin,
          siteOrigin: frontendOrigin,
          menuPath,
          ogUrl: `${frontendOrigin}${menuPath}`,
        };
        // Menu previews keep the generated OG card; link hub uses the restaurant logo.
        if (kind !== 'links') {
          ogOptions.ogImageUrl = `https://backend-henna-chi-76.vercel.app/api/og-image/${encodeURIComponent(slug)}`;
        }
        const ogData = buildRestaurantOgData(
          {
            ...restaurant,
            logoUrl,
            logo_url: logoUrl,
            description,
            description_ar: description,
            descriptionAr: description,
          },
          ogOptions,
        );
        res.setHeader('Cache-Control', 'public, max-age=60');
        sendHtml(res, 200, buildOgMenuHtml(ogData));
        return true;
      }
    }
  }

  return false;
}

module.exports = vercelHandler;
module.exports.handleRequest = handleRequest;
module.exports.vercelHandler = vercelHandler;

if (require.main === module) {
  const server = http.createServer(vercelHandler);
  server.listen(PORT, () => {
    console.log(`AlMenuPro API listening on http://localhost:${PORT}`);
  });
}
