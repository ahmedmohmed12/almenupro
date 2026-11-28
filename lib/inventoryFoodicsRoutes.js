'use strict';

const { mutateInventory, loadBlob, scopeTenant } = require('./inventory/inventoryRepository');
const { isDocDraft, DOC_STATUS } = require('./inventory/constants');
const {
  createTransferRecord,
  sendTransfer,
  receiveTransfer,
} = require('./inventory/transferService');
const {
  createProductionRecord,
  closeProduction,
} = require('./inventory/productionService');
const {
  createWasteDocument,
  closeWasteDocument,
} = require('./inventory/wasteTransactionService');
const {
  createCountSession,
  closeCountSession,
} = require('./inventory/inventoryCountService');
const {
  reportInventoryLevels,
  reportInventoryHistory,
  reportInventoryControl,
  reportInventoryVariance,
  reportMenuCostMargin,
  reportCogs,
  reportPurchasingWasteSummary,
} = require('./inventory/inventoryReports');
const { publicTransferStage, SCHEMA_DOCS } = require('./inventory/schemas');
const { approvePurchase } = require('./inventory/purchasingService');

function docIdParam(pathname, prefix) {
  const re = new RegExp(`^${prefix}/([^/]+)$`);
  const m = pathname.match(re);
  return m ? decodeURIComponent(m[1]) : null;
}

function actionIdParam(pathname, prefix, action) {
  const re = new RegExp(`^${prefix}/([^/]+)/${action}$`);
  const m = pathname.match(re);
  return m ? decodeURIComponent(m[1]) : null;
}

async function patchDraftDoc({
  dataStore,
  tenantId,
  collectionKey,
  docId,
  patch,
  res,
  sendJson,
}) {
  try {
    const result = await mutateInventory(dataStore, tenantId, async (blob) => {
      const rows = scopeTenant(blob[collectionKey], tenantId);
      const idx = rows.findIndex((r) => String(r.id) === String(docId));
      if (idx < 0) {
        const err = new Error('المستند غير موجود');
        err.code = 404;
        throw err;
      }
      if (!isDocDraft(rows[idx].status)) {
        const err = new Error('المستند مغلق ولا يمكن تعديله');
        err.code = 409;
        throw err;
      }
      rows[idx] = {
        ...rows[idx],
        ...patch,
        updatedAt: new Date().toISOString(),
      };
      blob[collectionKey] = [
        ...blob[collectionKey].filter(
          (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
        ),
        ...rows,
      ];
      return { blob, result: rows[idx] };
    });
    sendJson(res, 200, result);
    return true;
  } catch (error) {
    sendJson(res, error.code || 400, { error: error.message || 'فشل التحديث' });
    return true;
  }
}

async function handleInventoryFoodicsRoutes(req, res, url, ctx) {
  const {
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
  } = ctx;

  const pathname = url.pathname;
  const createdBy = auth.staffId || auth.role || 'admin';

  const from = url.searchParams.get('from') || url.searchParams.get('date_from');
  const to = url.searchParams.get('to') || url.searchParams.get('date_to');
  const reportBranch =
    url.searchParams.get('branch_id') ||
    url.searchParams.get('branchId') ||
    branchId;
  const itemId = url.searchParams.get('itemId') || url.searchParams.get('item_id');
  const category =
    url.searchParams.get('category') || url.searchParams.get('category_id') || '';

  function reportFilters(extra = {}) {
    return {
      branchId: reportBranch,
      from,
      to,
      category: category || undefined,
      ...extra,
    };
  }

  if (pathname === '/api/inventory/schemas' && req.method === 'GET') {
    sendJson(res, 200, { schemas: SCHEMA_DOCS });
    return true;
  }

  if (pathname === '/api/inventory/reports/levels' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, {
      rows: reportInventoryLevels(blob, tenantId, reportBranch, category),
      branchId: reportBranch,
      category: category || null,
    });
    return true;
  }

  if (pathname === '/api/inventory/reports/history' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, {
      rows: reportInventoryHistory(blob, tenantId, { itemId, from, to }),
      itemId: itemId || null,
    });
    return true;
  }

  const variancePaths = new Set([
    '/api/inventory/reports/control',
    '/api/inventory/reports/variance',
  ]);
  if (variancePaths.has(pathname) && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    const orders = readOrders ? await readOrders() : [];
    const rows = reportInventoryVariance(blob, tenantId, orders, reportFilters());
    sendJson(res, 200, { rows, report: 'variance' });
    return true;
  }

  const cogsPaths = new Set([
    '/api/inventory/reports/menu-cost',
    '/api/inventory/reports/cogs',
  ]);
  if (cogsPaths.has(pathname) && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    const orders = readOrders ? await readOrders() : [];
    const menuItems = readItems ? await readItems() : [];
    const rows = reportCogs(blob, tenantId, orders, menuItems, reportFilters());
    sendJson(res, 200, { rows, report: 'cogs' });
    return true;
  }

  if (pathname === '/api/inventory/reports/purchasing-waste' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, reportPurchasingWasteSummary(blob, tenantId, {
      from,
      to,
      branchId: reportBranch,
    }));
    return true;
  }

  function publicTransfer(row) {
    return {
      ...row,
      foodicsStage: publicTransferStage(row.stage),
    };
  }

  if (pathname === '/api/inventory/transfers' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, {
      transfers: scopeTenant(blob.transfers, tenantId).map(publicTransfer),
    });
    return true;
  }

  if (pathname === '/api/inventory/transfers' && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const record = createTransferRecord(body, tenantId);
    await mutateInventory(dataStore, tenantId, async (blob) => {
      blob.transfers = [...(blob.transfers || []), record];
      return blob;
    });
    sendJson(res, 201, record);
    return true;
  }

  const transferId = docIdParam(pathname, '/api/inventory/transfers');
  if (transferId && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    const record = scopeTenant(blob.transfers, tenantId).find(
      (t) => String(t.id) === transferId,
    );
    if (!record) {
      sendJson(res, 404, { error: 'التحويل غير موجود' });
      return true;
    }
    sendJson(res, 200, record);
    return true;
  }

  if (transferId && req.method === 'PATCH') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const patch = {
      notes: body.notes,
      fromBranchId: body.fromBranchId,
      toBranchId: body.toBranchId,
    };
    if (body.lines) {
      const { roundQty } = require('./inventory/constants');
      patch.lines = body.lines.map((line) => ({
        itemId: String(line.itemId),
        qtyInRecipeUom: roundQty(line.qtyInRecipeUom || line.qty || 0),
      }));
    }
    return patchDraftDoc({
      dataStore,
      tenantId,
      collectionKey: 'transfers',
      docId: transferId,
      patch,
      res,
      sendJson,
    });
  }

  const sendTransferId = actionIdParam(pathname, '/api/inventory/transfers', 'send');
  if (sendTransferId && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    try {
      const out = await sendTransfer(dataStore, {
        tenantId,
        transferId: sendTransferId,
        createdBy,
      });
      sendJson(res, 200, out);
    } catch (error) {
      sendJson(res, error.code || 400, { error: error.message || 'فشل الإرسال' });
    }
    return true;
  }

  const recvTransferId = actionIdParam(pathname, '/api/inventory/transfers', 'receive');
  if (recvTransferId && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    try {
      const out = await receiveTransfer(dataStore, {
        tenantId,
        transferId: recvTransferId,
        createdBy,
      });
      sendJson(res, 200, out);
    } catch (error) {
      sendJson(res, error.code || 400, { error: error.message || 'فشل الاستلام' });
    }
    return true;
  }

  if (pathname === '/api/inventory/productions' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, { productions: scopeTenant(blob.productions, tenantId) });
    return true;
  }

  if (pathname === '/api/inventory/productions' && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const record = createProductionRecord(body, tenantId, branchId);
    await mutateInventory(dataStore, tenantId, async (blob) => {
      blob.productions = [...(blob.productions || []), record];
      return blob;
    });
    sendJson(res, 201, record);
    return true;
  }

  const productionId = docIdParam(pathname, '/api/inventory/productions');
  if (productionId && req.method === 'PATCH') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const { normalizeProductionLines } = require('./inventory/productionService');
    const patch = {};
    if (body.lines) {
      patch.lines = normalizeProductionLines({ lines: body.lines });
      if (patch.lines.length === 1) {
        patch.prepItemId = patch.lines[0].prepItemId;
        patch.outputQtyInRecipeUom = patch.lines[0].outputQtyInRecipeUom;
      } else {
        patch.prepItemId = null;
        patch.outputQtyInRecipeUom = null;
      }
    } else if (body.prepItemId) {
      const single = normalizeProductionLines(body);
      patch.lines = single;
      patch.prepItemId = single[0].prepItemId;
      patch.outputQtyInRecipeUom = single[0].outputQtyInRecipeUom;
    } else if (body.outputQtyInRecipeUom != null || body.outputQty != null) {
      const blob = await loadBlob(dataStore);
      const existing = scopeTenant(blob.productions, tenantId).find(
        (p) => String(p.id) === String(productionId),
      );
      if (existing?.prepItemId || existing?.lines?.[0]?.prepItemId) {
        const prepId = existing.prepItemId || existing.lines[0].prepItemId;
        const single = normalizeProductionLines({
          prepItemId: prepId,
          outputQtyInRecipeUom: body.outputQtyInRecipeUom ?? body.outputQty ?? body.qty,
        });
        patch.lines = single;
        patch.prepItemId = single[0].prepItemId;
        patch.outputQtyInRecipeUom = single[0].outputQtyInRecipeUom;
      }
    }
    if (body.notes != null) patch.notes = String(body.notes).trim();
    return patchDraftDoc({
      dataStore,
      tenantId,
      collectionKey: 'productions',
      docId: productionId,
      patch,
      res,
      sendJson,
    });
  }

  const closeProductionId = actionIdParam(pathname, '/api/inventory/productions', 'close');
  if (closeProductionId && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    try {
      const out = await closeProduction(dataStore, {
        tenantId,
        branchId,
        productionId: closeProductionId,
        createdBy,
      });
      sendJson(res, 200, out);
    } catch (error) {
      sendJson(res, error.code || 400, { error: error.message || 'فشل إغلاق الإنتاج' });
    }
    return true;
  }

  if (pathname === '/api/inventory/waste-documents' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, { documents: scopeTenant(blob.wasteDocuments, tenantId) });
    return true;
  }

  if (pathname === '/api/inventory/waste-documents' && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const record = createWasteDocument(body, tenantId, branchId);
    await mutateInventory(dataStore, tenantId, async (blob) => {
      blob.wasteDocuments = [...(blob.wasteDocuments || []), record];
      return blob;
    });
    sendJson(res, 201, record);
    return true;
  }

  const wasteDocId = docIdParam(pathname, '/api/inventory/waste-documents');
  if (wasteDocId && req.method === 'PATCH') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const patch = {};
    if (body.lines) patch.lines = createWasteDocument({ lines: body.lines }, tenantId, branchId).lines;
    return patchDraftDoc({
      dataStore,
      tenantId,
      collectionKey: 'wasteDocuments',
      docId: wasteDocId,
      patch,
      res,
      sendJson,
    });
  }

  const closeWasteId = actionIdParam(pathname, '/api/inventory/waste-documents', 'close');
  if (closeWasteId && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    try {
      const out = await closeWasteDocument(dataStore, {
        tenantId,
        branchId,
        wasteId: closeWasteId,
        createdBy,
      });
      sendJson(res, 200, out);
    } catch (error) {
      sendJson(res, error.code || 400, { error: error.message || 'فشل إغلاق الهالك' });
    }
    return true;
  }

  if (pathname === '/api/inventory/counts' && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    sendJson(res, 200, { counts: scopeTenant(blob.inventoryCounts, tenantId) });
    return true;
  }

  if (pathname === '/api/inventory/counts' && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const record = createCountSession(body, tenantId, branchId);
    await mutateInventory(dataStore, tenantId, async (blob) => {
      blob.inventoryCounts = [...(blob.inventoryCounts || []), record];
      return blob;
    });
    sendJson(res, 201, record);
    return true;
  }

  const countId = docIdParam(pathname, '/api/inventory/counts');
  if (countId && req.method === 'GET') {
    const blob = await loadBlob(dataStore);
    const record = scopeTenant(blob.inventoryCounts, tenantId).find(
      (c) => String(c.id) === countId,
    );
    if (!record) {
      sendJson(res, 404, { error: 'جلسة الجرد غير موجودة' });
      return true;
    }
    let payload = record;
    if (record.blindCount && isDocDraft(record.status)) {
      const items = scopeTenant(blob.items, tenantId);
      const byId = new Map(items.map((row) => [String(row.id), row]));
      payload = {
        ...record,
        lines: (record.lines || []).map((line) => ({
          itemId: line.itemId,
          countedQty: line.countedQty,
          sku: byId.get(String(line.itemId))?.sku,
          name: byId.get(String(line.itemId))?.name,
        })),
      };
    }
    sendJson(res, 200, payload);
    return true;
  }

  if (countId && req.method === 'PATCH') {
    if (rejectCashier?.(auth, res)) return true;
    const body = parseJson(await readBody(req));
    const patch = {};
    if (body.categoryFilter != null) patch.categoryFilter = String(body.categoryFilter).trim();
    if (body.blindCount != null) patch.blindCount = body.blindCount === true;
    if (body.lines) {
      patch.lines = createCountSession({ lines: body.lines }, tenantId, branchId).lines;
    }
    return patchDraftDoc({
      dataStore,
      tenantId,
      collectionKey: 'inventoryCounts',
      docId: countId,
      patch,
      res,
      sendJson,
    });
  }

  const closeCountId = actionIdParam(pathname, '/api/inventory/counts', 'close');
  if (closeCountId && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    try {
      const out = await closeCountSession(dataStore, {
        tenantId,
        branchId,
        countId: closeCountId,
        createdBy,
      });
      sendJson(res, 200, out);
    } catch (error) {
      sendJson(res, error.code || 400, { error: error.message || 'فشل إغلاق الجرد' });
    }
    return true;
  }

  const closePurchaseId = actionIdParam(pathname, '/api/inventory/purchases', 'close');
  if (closePurchaseId && req.method === 'POST') {
    if (rejectCashier?.(auth, res)) return true;
    try {
      const out = await approvePurchase(dataStore, {
        tenantId,
        branchId,
        purchaseId: closePurchaseId,
        approvedBy: createdBy,
        readMenuItems: readItems,
      });
      sendJson(res, 200, { ...out, status: DOC_STATUS.CLOSED });
    } catch (error) {
      sendJson(res, error.code || 400, { error: error.message || 'فشل إغلاق المشتريات' });
    }
    return true;
  }

  return false;
}

module.exports = {
  handleInventoryFoodicsRoutes,
  patchDraftDoc,
};