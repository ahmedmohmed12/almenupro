'use strict';

const {
  mutateInventory,
  loadBlob,
  scopeTenant,
  ensureLocations,
} = require('./inventory/inventoryRepository');
const {
  createInventoryItem,
  patchInventoryItem,
  publicInventoryItem,
  normalizeRecipe,
  normalizePackagingProfile,
} = require('./inventory/inventoryModels');
const { createPurchaseRecord, approvePurchase } = require('./inventory/purchasingService');
const { recordWaste, submitStocktake } = require('./inventory/wasteStocktakeService');
const { reverseMoveRecord } = require('./inventory/stockLedger');
const { MOVE_REFERENCE, isDocDraft } = require('./inventory/constants');
const { handleInventoryFoodicsRoutes } = require('./inventoryFoodicsRoutes');
const {
  inventoryEnabledForTenant,
  rejectIfInventoryDisabled,
} = require('./inventory/inventoryAccess');
const { estimateMenuItemCost } = require('./inventory/recipeCostService');
const { normalizePurchaseLine } = require('./inventory/uomConversion');

function itemsMap(blob, tenantId) {
  return new Map(
    scopeTenant(blob.items, tenantId).map((row) => [String(row.id), row]),
  );
}

async function runMutate(dataStore, tenantId, fn, res, sendJson) {
  try {
    return await mutateInventory(dataStore, tenantId, fn);
  } catch (error) {
    sendJson(res, error.code || 400, { error: error.message || 'فشل العملية' });
    return null;
  }
}

async function handleInventoryRoutes(req, res, url, deps) {
  const {
    readBody,
    sendJson,
    authError,
    requireAuth,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    parseJson,
    dataStore,
    rejectCashier,
    readItems,
    readRestaurants,
    readOrders,
  } = deps;

  if (!url.pathname.startsWith('/api/inventory')) return false;

  const auth = requireAuth(req, res);
  if (!auth) return true;

  const tenantId = await resolveScopedRestaurantId(req, url, auth);
  if (!tenantId || !assertRestaurantAccess(auth, tenantId, authError, res)) {
    return true;
  }

  const branchId =
    url.searchParams.get('branch_id') ||
    url.searchParams.get('branchId') ||
    tenantId;

  const pathname = url.pathname;
  const readRest = readRestaurants || (() => dataStore.readRestaurants());

  if (pathname === '/api/inventory/status' && req.method === 'GET') {
    const inventoryEnabled = await inventoryEnabledForTenant(readRest, tenantId);
    sendJson(res, 200, { tenantId, branchId, inventoryEnabled });
    return true;
  }

  if (await rejectIfInventoryDisabled(res, sendJson, readRest, tenantId)) {
    return true;
  }

  if (pathname === '/api/inventory/locations' && req.method === 'GET') {
    const locations = await ensureLocations(dataStore, tenantId, branchId);
    sendJson(res, 200, { locations, tenantId, branchId });
    return true;
  }

  if (pathname === '/api/inventory/items' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    let items = scopeTenant(blob.items, tenantId);
    const lowStock = url.searchParams.get('lowStock') === '1';
    if (lowStock) {
      items = items.filter(
        (row) =>
          row.minStockAlert > 0 && (Number(row.currentQty) || 0) <= row.minStockAlert,
      );
    }
    sendJson(res, 200, {
      items: items.map(publicInventoryItem),
    });
    return true;
  }

  if (pathname === '/api/inventory/items' && req.method === 'POST') {
    if (rejectCashier?.(auth, res, 'الكاشير لا يمكنه إدارة المخزون')) return true;
    const body = parseJson(await readBody(req));
    const record = createInventoryItem(body, tenantId, branchId);
    await mutateInventory(dataStore, tenantId, async (blob) => {
      blob.items = [...blob.items, record];
      return blob;
    });
    sendJson(res, 201, publicInventoryItem(record));
    return true;
  }

  const itemMatch = pathname.match(/^\/api\/inventory\/items\/([^/]+)$/);
  if (itemMatch && req.method === 'GET') {
    const itemId = decodeURIComponent(itemMatch[1]);
    const blob = await loadBlob(dataStore);
    const item = scopeTenant(blob.items, tenantId).find(
      (row) => String(row.id) === itemId,
    );
    if (!item) {
      sendJson(res, 404, { error: 'الصنف غير موجود' });
      return true;
    }
    sendJson(res, 200, publicInventoryItem(item));
    return true;
  }

  if (itemMatch && req.method === 'PATCH') {
    if (rejectCashier?.(auth, res, 'الكاشير لا يمكنه إدارة المخزون')) return true;
    const itemId = decodeURIComponent(itemMatch[1]);
    const body = parseJson(await readBody(req));
    const updated = await runMutate(
      dataStore,
      tenantId,
      async (blob) => {
        const items = scopeTenant(blob.items, tenantId);
        const idx = items.findIndex((row) => String(row.id) === itemId);
        if (idx < 0) {
          const err = new Error('الصنف غير موجود');
          err.code = 404;
          throw err;
        }
        items[idx] = patchInventoryItem(items[idx], body);
        blob.items = [
          ...blob.items.filter(
            (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
          ),
          ...items,
        ];
        return { blob, result: items[idx] };
      },
      res,
      sendJson,
    );
    if (updated) sendJson(res, 200, publicInventoryItem(updated));
    return true;
  }

  if (pathname === '/api/inventory/moves' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    let moves = scopeTenant(blob.moves, tenantId);
    const itemId = url.searchParams.get('itemId');
    const refType = url.searchParams.get('referenceType');
    if (itemId) {
      moves = moves.filter((m) => String(m.itemId) === String(itemId));
    }
    if (refType) {
      moves = moves.filter((m) => m.referenceType === refType);
    }
    moves.sort(
      (a, b) => Date.parse(b.createdAt || 0) - Date.parse(a.createdAt || 0),
    );
    sendJson(res, 200, { moves: moves.slice(0, 500) });
    return true;
  }

  const reverseMatch = pathname.match(/^\/api\/inventory\/moves\/([^/]+)\/reverse$/);
  if (reverseMatch && req.method === 'POST') {
    if (rejectCashier?.(auth, res, 'غير مسموح للكاشير')) return true;
    const moveId = decodeURIComponent(reverseMatch[1]);
    const body = parseJson(await readBody(req));
    const result = await runMutate(
      dataStore,
      tenantId,
      async (blob) => {
        const move = scopeTenant(blob.moves, tenantId).find(
          (m) => String(m.id) === moveId,
        );
        if (!move) {
          const err = new Error('الحركة غير موجودة');
          err.code = 404;
          throw err;
        }
        const reversal = reverseMoveRecord(move, {
          createdBy: auth.staffId || auth.role,
          reason: body.reason || '',
        });
        const { postMoveOnBranchStock } = require('./inventory/stockLedger');
        blob.moves = [...blob.moves, reversal];
        blob.items = postMoveOnBranchStock({ items: blob.items, move: reversal });
        return { blob, result: reversal };
      },
      res,
      sendJson,
    );
    if (result) sendJson(res, 201, result);
    return true;
  }

  if (pathname === '/api/inventory/purchases' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, { purchases: scopeTenant(blob.purchases, tenantId) });
    return true;
  }

  if (pathname === '/api/inventory/purchases' && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const blob = await loadBlob(dataStore);
    const record = createPurchaseRecord(
      body,
      tenantId,
      branchId,
      itemsMap(blob, tenantId),
    );
    await mutateInventory(dataStore, tenantId, async (b) => {
      b.purchases = [...b.purchases, record];
      return b;
    });
    sendJson(res, 201, record);
    return true;
  }

  const purchaseMatch = pathname.match(/^\/api\/inventory\/purchases\/([^/]+)$/);
  if (purchaseMatch && req.method === 'GET') {
    const purchaseId = decodeURIComponent(purchaseMatch[1]);
    const blob = await loadBlob(dataStore);
    const purchase = scopeTenant(blob.purchases, tenantId).find(
      (p) => String(p.id) === purchaseId,
    );
    if (!purchase) {
      sendJson(res, 404, { error: 'أمر الشراء غير موجود' });
      return true;
    }
    sendJson(res, 200, purchase);
    return true;
  }

  if (purchaseMatch && req.method === 'PATCH') {
    if (rejectCashier?.(auth, res)) return true;
    const purchaseId = decodeURIComponent(purchaseMatch[1]);
    const body = parseJson(await readBody(req));
    const updated = await runMutate(
      dataStore,
      tenantId,
      async (blob) => {
        const purchases = scopeTenant(blob.purchases, tenantId);
        const idx = purchases.findIndex((p) => String(p.id) === purchaseId);
        if (idx < 0) {
          const err = new Error('أمر الشراء غير موجود');
          err.code = 404;
          throw err;
        }
        if (!isDocDraft(purchases[idx].status)) {
          const err = new Error('لا يمكن تعديل شراء مغلق');
          err.code = 409;
          throw err;
        }
        const byId = itemsMap(blob, tenantId);
        const nextLines = body.lines
          ? body.lines.map((line) => normalizePurchaseLine(line, byId.get(String(line.itemId))))
          : purchases[idx].lines;
        purchases[idx] = {
          ...purchases[idx],
          vendorName: body.vendorName ?? purchases[idx].vendorName,
          invoiceRef: body.invoiceRef ?? purchases[idx].invoiceRef,
          lines: nextLines,
          updatedAt: new Date().toISOString(),
        };
        blob.purchases = [
          ...blob.purchases.filter(
            (p) => String(p.tenantId || p.restaurantId) !== String(tenantId),
          ),
          ...purchases,
        ];
        return { blob, result: purchases[idx] };
      },
      res,
      sendJson,
    );
    if (updated) sendJson(res, 200, updated);
    return true;
  }

  const approveMatch = pathname.match(/^\/api\/inventory\/purchases\/([^/]+)\/approve$/);
  if (approveMatch && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    const purchaseId = decodeURIComponent(approveMatch[1]);
    try {
      const out = await approvePurchase(dataStore, {
        tenantId,
        branchId,
        purchaseId,
        approvedBy: auth.staffId || auth.role,
        readMenuItems: readItems,
      });
      sendJson(res, 200, out);
    } catch (error) {
      sendJson(res, error.code || 400, { error: error.message || 'فشل اعتماد الشراء' });
    }
    return true;
  }

  if (pathname === '/api/inventory/recipes' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, { recipes: scopeTenant(blob.recipes, tenantId) });
    return true;
  }

  if (
    (pathname === '/api/inventory/recipes' && req.method === 'PUT') ||
    (pathname === '/api/inventory/recipes' && req.method === 'POST')
  ) {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const record = normalizeRecipe(body, tenantId, branchId);
    await mutateInventory(dataStore, tenantId, async (blob) => {
      const recipes = scopeTenant(blob.recipes, tenantId).filter(
        (row) =>
          String(row.menuItemId || '') !== String(record.menuItemId || '') ||
          String(row.modifierId || '') !== String(record.modifierId || ''),
      );
      blob.recipes = [
        ...blob.recipes.filter(
          (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
        ),
        ...recipes,
        record,
      ];
      return blob;
    });
    sendJson(res, 200, record);
    return true;
  }

  const recipeMenuMatch = pathname.match(/^\/api\/inventory\/recipes\/menu\/([^/]+)$/);
  if (recipeMenuMatch && req.method === 'GET') {
    const menuItemId = decodeURIComponent(recipeMenuMatch[1]);
    const blob = await loadBlob(dataStore);
    const recipe = scopeTenant(blob.recipes, tenantId).find(
      (row) => String(row.menuItemId) === menuItemId,
    );
    if (!recipe) {
      sendJson(res, 404, { error: 'لا توجد وصفة لهذا الصنف' });
      return true;
    }
    sendJson(res, 200, recipe);
    return true;
  }

  if (pathname === '/api/inventory/recipes/estimate-cost' && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const menuItemId = body.menuItemId || body.menu_item_id;
    const blob = await loadBlob(dataStore);
    const menuItems = await readItems();
    const menuItem = menuItems.find((row) => String(row.id) === String(menuItemId));
  const estimate = estimateMenuItemCost({
      menuItemId,
      channel: body.channel || body.salesChannel,
      recipes: blob.recipes,
      packagingProfiles: blob.packagingProfiles,
      items: blob.items,
      tenantId,
      menuItem,
    });
    sendJson(res, 200, estimate);
    return true;
  }

  if (pathname === '/api/inventory/packaging-profiles' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, {
      profiles: scopeTenant(blob.packagingProfiles, tenantId),
    });
    return true;
  }

  if (pathname === '/api/inventory/packaging-profiles' && req.method === 'PUT') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const record = normalizePackagingProfile(body, tenantId);
    await mutateInventory(dataStore, tenantId, async (blob) => {
      const profiles = scopeTenant(blob.packagingProfiles, tenantId).filter(
        (row) => row.channel !== record.channel,
      );
      blob.packagingProfiles = [
        ...blob.packagingProfiles.filter(
          (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
        ),
        ...profiles,
        record,
      ];
      return blob;
    });
    sendJson(res, 200, record);
    return true;
  }

  if (pathname === '/api/inventory/waste' && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const move = await recordWaste(dataStore, {
      tenantId,
      branchId,
      itemId: body.itemId,
      qtyInRecipeUom: body.qtyInRecipeUom,
      reasonCode: body.reasonCode || body.reason,
      createdBy: auth.staffId || auth.role,
    });
    sendJson(res, 201, move);
    return true;
  }

  if (pathname === '/api/inventory/stocktake' && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const result = await submitStocktake(dataStore, {
      tenantId,
      branchId,
      lines: body.lines,
      createdBy: auth.staffId || auth.role,
      stocktakeId: body.stocktakeId,
    });
    sendJson(res, 200, result);
    return true;
  }

  if (pathname === '/api/inventory/jobs' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    let jobs = scopeTenant(blob.jobs, tenantId);
    const orderId = url.searchParams.get('orderId');
    if (orderId) {
      jobs = jobs.filter((j) => String(j.orderId) === String(orderId));
    }
    sendJson(res, 200, { jobs: jobs.slice(0, 100) });
    return true;
  }

  if (pathname === '/api/inventory/summary' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    const items = scopeTenant(blob.items, tenantId);
    const moves = scopeTenant(blob.moves, tenantId);
    const stockValue = items.reduce(
      (sum, row) => sum + (Number(row.currentQty) || 0) * (Number(row.avgCost) || 0),
      0,
    );
    sendJson(res, 200, {
      itemCount: items.length,
      moveCount: moves.length,
      stockValue,
      references: Object.values(MOVE_REFERENCE),
    });
    return true;
  }

  if (
    await handleInventoryFoodicsRoutes(req, res, url, {
      sendJson,
      parseJson,
      readBody,
      dataStore,
      tenantId,
      branchId,
      auth,
      rejectCashier,
      readItems,
      readOrders,
    })
  ) {
    return true;
  }

  return false;
}

module.exports = {
  handleInventoryRoutes,
};