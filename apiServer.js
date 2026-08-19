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
  isSuperAdmin,
  canAccessRestaurant,
  resolveRestaurantId,
  authError,
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
const { ALL_PERMISSION_KEYS } = require('./lib/posPermissions');
const { serveMenuImage, persistMenuItemsImages, proxyExternalImage } = require('./lib/menuImageStorage');
const { normalizeMenuItemsForApi, normalizeMenuItemForApi } = require('./lib/bilingualItemMigration');
const { migrateMenuItems } = require('./lib/bilingualMenu');
const { scrapeTalabatMenu } = require('./lib/talabatScraper');
const { computeTopMenuItems } = require('./lib/topItemsAnalytics');
const { computeDailySalesAnalytics } = require('./lib/platformSalesAnalytics');
const { computeFoodCostReport } = require('./lib/foodCostReportAnalytics');
const { computeUpsellAnalytics, normalizeIncomingEvent, trimEvents } = require('./lib/upsellAnalytics');
const { previewEarnedCashback, applyLoyaltyCashbackToOrder } = require('./lib/loyaltyCashback');
const {
  enrichCustomersForRestaurant,
  upsertCustomerFromSource,
  findCustomerByPhone,
  customerProfileFromRecord,
  migrateCustomersFromOrders,
} = require('./lib/customersStore');
const { normalizeWhatsappSettings } = require('./lib/whatsappPhone');
const {
  buildRestaurantOgData,
  buildOgMenuHtml,
  isSocialCrawler,
  parseMenuSlugFromPath,
} = require('./lib/ogMenuMeta');
const {
  applyShiftBindingOnAccept,
  applyShiftAdjustmentOnCancel,
} = require('./lib/shiftOrderBinding');

const PORT = Number(process.env.PORT || 3000);

function sendJson(res, statusCode, body) {
  applyCorsHeaders({ headers: {} }, res);
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(body));
}

function sendHtml(res, statusCode, html) {
  applyCorsHeaders({ headers: {} }, res);
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

function requestUrl(req) {
  const host = req.headers.host || 'localhost';
  const proto = req.headers['x-forwarded-proto'] || 'http';
  return new URL(req.url || '/', `${proto}://${host}`);
}

function publicRestaurant(entry) {
  if (!entry || typeof entry !== 'object') return entry;
  const { adminPassword, ...rest } = entry;
  return rest;
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

function normalizeIncomingItem(body, restaurantId, existing = {}) {
  const isAvailable = body.isAvailable ?? body.is_available ?? existing.is_available ?? true;
  return normalizeMenuItemForApi({
    ...existing,
    ...body,
    restaurant_id: restaurantId,
    name: body.name ?? existing.name,
    name_ar: body.name_ar ?? body.nameAr ?? body.name ?? existing.name_ar,
    name_en: body.name_en ?? body.nameEn ?? existing.name_en ?? '',
    description: body.description ?? existing.description ?? '',
    description_ar:
      body.description_ar ?? body.descriptionAr ?? body.description ?? existing.description_ar ?? '',
    description_en: body.description_en ?? body.descriptionEn ?? existing.description_en ?? '',
    price: Number(body.price ?? existing.price ?? 0),
    category_name: body.categoryName ?? body.category_name ?? existing.category_name ?? 'عام',
    image_url: body.imageUrl ?? body.image_url ?? existing.image_url ?? '',
    is_available: isAvailable === false || isAvailable === 0 ? 0 : 1,
    source: body.source ?? existing.source ?? 'Manual',
    options: body.options ?? existing.options ?? [],
    linkedItemIds: body.linkedItemIds ?? body.linked_item_ids ?? existing.linkedItemIds ?? [],
  });
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
 * Vercel/Node entry: guarantee OPTIONS → 200 even if later logic throws.
 */
async function vercelHandler(req, res) {
  try {
    if (String(req.method || '').toUpperCase() === 'OPTIONS') {
      applyCorsHeaders(req, res);
      res.statusCode = 200;
      res.setHeader('Content-Length', '0');
      res.end();
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
      sendJson(res, 200, { token, role: 'super_admin' });
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
      subscriptionPlan: body.subscriptionPlan ?? body.subscription_plan ?? current.subscriptionPlan,
      subscriptionStatus:
        body.subscriptionStatus ?? body.subscription_status ?? current.subscriptionStatus,
      subscriptionExpiresAt:
        body.subscriptionExpiresAt ?? body.subscription_expires_at ?? current.subscriptionExpiresAt,
      subscriptionNotes:
        body.subscriptionNotes ?? body.subscription_notes ?? current.subscriptionNotes ?? '',
      adminPassword: body.adminPassword || current.adminPassword,
      updatedAt: new Date().toISOString(),
    };
    restaurants[index] = next;
    await dataStore.writeRestaurants(restaurants);
    sendJson(res, 200, publicRestaurant(next));
    return true;
  }

  if (pathname === '/api/items' && req.method === 'GET') {
    const restaurantId =
      url.searchParams.get('restaurant_id') ||
      url.searchParams.get('restaurantId') ||
      resolveRestaurantFromQuery(url, await dataStore.readRestaurants());
    const lite =
      url.searchParams.get('full') !== '1' &&
      url.searchParams.get('full') !== 'true';
    const limit = Math.min(
      Math.max(Number(url.searchParams.get('limit')) || 40, 1),
      100,
    );
    const offset = Math.max(Number(url.searchParams.get('offset')) || 0, 0);
    const page = await dataStore.readItemsPage({
      restaurantId,
      offset,
      limit,
      lite,
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
    const items = await dataStore.readItems();
    const created = normalizeIncomingItem(
      { ...body, id: nextNumericItemId(items) },
      restaurantId,
    );
    items.push(created);
    await dataStore.writeItems(items);
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
    const existingDoc = await dataStore.findItemDoc(itemId);
    if (existingDoc) {
      if (!assertRestaurantAccess(
        auth,
        existingDoc.restaurant_id || existingDoc.restaurantId,
        authError,
        res,
      )) {
        return true;
      }
      const fromCollection = await dataStore.patchItemAvailability(itemId, isAvailable);
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
    const items = await dataStore.readItems();
    const index = items.findIndex((item) => itemMatchesId(item, itemId));
    if (index === -1) {
      sendJson(res, 404, { error: 'Item not found' });
      return true;
    }
    const restaurantId = items[index].restaurant_id || items[index].restaurantId;
    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    if (req.method === 'DELETE') {
      items.splice(index, 1);
      await dataStore.writeItems(items);
      await dataStore.deleteItemDoc(itemId);
      sendJson(res, 200, { ok: true });
      return true;
    }
    const body = parseJson(await readBody(req));
    items[index] = normalizeIncomingItem(body, restaurantId, items[index]);
    await dataStore.writeItems(items);
    sendJson(res, 200, items[index]);
    return true;
  }

  if (pathname === '/api/orders' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    const orders = filterByRestaurant(await dataStore.readOrders(), restaurantId);
    sendJson(res, 200, orders);
    return true;
  }

  if (pathname === '/api/orders' && req.method === 'POST') {
    const body = parseJson(await readBody(req));
    const restaurants = await dataStore.readRestaurants();
    const restaurantId =
      body.restaurantId ||
      body.restaurant_id ||
      resolveRestaurantFromQuery(url, restaurants);
    const orders = await dataStore.readOrders();
    const created = {
      ...body,
      id: body.id || `ord_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      restaurant_id: restaurantId,
      restaurantId,
      status: body.status || 'pending',
      createdAt: body.createdAt || new Date().toISOString(),
    };
    orders.unshift(created);
    await dataStore.writeOrders(orders);
    if (created.phone) {
      const customers = await extraStore.customers.read();
      await extraStore.customers.write(
        upsertCustomerFromSource(customers, created, restaurantId),
      );
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
    const body = parseJson(await readBody(req));
    const previousStatus = orders[index].status;
    let next = {
      ...orders[index],
      status: body.status || orders[index].status,
      shiftId: body.shiftId || body.shift_id || orders[index].shiftId,
      cashierId: body.cashierId || body.cashier_id || orders[index].cashierId,
      updatedAt: new Date().toISOString(),
    };
    const shifts = await extraStore.shiftSessions.read();
    const bound = applyShiftBindingOnAccept({
      order: next,
      previousStatus,
      nextStatus: body.status,
      shifts,
      restaurantId,
      auth,
      body,
    });
    next = bound.order || next;
    const cancelled = applyShiftAdjustmentOnCancel({
      order: next,
      previousStatus,
      shifts: bound.shifts || shifts,
    });
    next = cancelled.order || next;
    if (cancelled.shifts) {
      await extraStore.shiftSessions.write(cancelled.shifts);
    }
    if (String(next.status || '').toLowerCase() === 'delivered') {
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
    await dataStore.writeOrders(orders);
    sendJson(res, 200, next);
    return true;
  }

  if (pathname === '/api/settings' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId = resolveRestaurantFromQuery(url, restaurants);
    const map = await dataStore.readSettingsMap();
    const payload = map.byRestaurant?.[restaurantId] || defaultSettingsPayload();
    sendJson(res, 200, { ...payload, ...normalizeWhatsappSettings(payload) });
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
    delete next.restaurantId;
    delete next.restaurant_id;
    map.byRestaurant = map.byRestaurant || {};
    map.byRestaurant[restaurantId] = next;
    await dataStore.writeSettingsMap(map);
    sendJson(res, 200, next);
    return true;
  }

  if (pathname === '/api/analytics/top-items' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId = resolveRestaurantFromQuery(url, restaurants);
    const days = Number(url.searchParams.get('days') || 90);
    const limit = Number(url.searchParams.get('limit') || 12);
    const result = computeTopMenuItems(
      await dataStore.readOrders(),
      filterByRestaurant(await dataStore.readItems(), restaurantId),
      restaurantId,
      { days, limit },
    );
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
      body.restaurantId || (await resolveScopedRestaurantId(req, url, auth));
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    try {
      const scraped = await scrapeTalabatMenu(body.url);
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
      for (const scrapedItem of scraped.items || []) {
        const matchIndex = merged.findIndex(
          (item) =>
            String(item.talabat_id) === String(scrapedItem.talabat_id) ||
            String(item.name) === String(scrapedItem.name),
        );
        const normalized = normalizeIncomingItem(scrapedItem, restaurantId, {
          id: matchIndex === -1 ? nextNumericItemId(items.concat(merged)) : merged[matchIndex].id,
        });
        if (matchIndex === -1) {
          merged.push(normalized);
          added += 1;
        } else {
          merged[matchIndex] = { ...merged[matchIndex], ...normalized };
          updated += 1;
        }
      }
      const migrated = migrateMenuItems(merged).items;
      const withImages = body.downloadImages === false
        ? migrated
        : await persistMenuItemsImages(migrated);
      await dataStore.writeItems([...others, ...withImages]);
      sendJson(res, 200, {
        added,
        updated,
        skipped: 0,
        synced: withImages.length,
        total: withImages.length,
        menuUrl: scraped.menuUrl,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Talabat import failed' });
    }
    return true;
  }

  if (pathname === '/api/delivery-zones' && req.method === 'GET') {
    const restaurants = await dataStore.readRestaurants();
    const restaurantId = resolveRestaurantFromQuery(url, restaurants);
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
      isActive: body.isActive !== false,
      defaultKitchenId: body.defaultKitchenId || body.default_kitchen_id || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    const zones = await extraStore.deliveryZones.read();
    zones.push(zone);
    await extraStore.deliveryZones.write(zones);
    sendJson(res, 201, zone);
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
    zones[index] = {
      ...zones[index],
      ...body,
      restaurant_id: restaurantId,
      areaName: body.areaName || body.area_name || zones[index].areaName,
      deliveryFee: Number(body.deliveryFee ?? body.delivery_fee ?? zones[index].deliveryFee),
      updatedAt: new Date().toISOString(),
    };
    await extraStore.deliveryZones.write(zones);
    sendJson(res, 200, zones[index]);
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
    const slug = pathname.startsWith('/og/')
      ? decodeURIComponent(pathname.slice(4)).replace(/\/+$/, '')
      : parseMenuSlugFromPath(pathname);
    if (slug) {
      const restaurants = await dataStore.readRestaurants();
      const restaurant = restaurants.find(
        (entry) => String(entry.slug || '').toLowerCase() === slug.toLowerCase(),
      );
      if (restaurant) {
        const items = filterByRestaurant(await dataStore.readItems(), restaurant.id);
        const ogData = buildRestaurantOgData(restaurant, { slug, items });
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
