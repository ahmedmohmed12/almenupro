'use strict';

const { computeAvco } = require('./avco');
const {
  LOCATION_KIND,
  MOVE_REFERENCE,
  PURCHASE_STATUS,
  DOC_STATUS,
  isDocClosed,
  roundQty,
  roundMoneyKwd,
  newId,
} = require('./constants');
const {
  mutateInventory,
  ensureLocationsInBlob,
  findLocation,
  scopeTenant,
  attachTenant,
} = require('./inventoryRepository');
const { createStockMoveRecord, postMoveOnBranchStock } = require('./stockLedger');
const { evaluateMarginAlerts } = require('./marginGuard');
const { normalizePurchaseLine } = require('./uomConversion');

function toRecipeQty(purchaseQty, line, item) {
  if (line.qtyInRecipeUom != null) return roundQty(line.qtyInRecipeUom);
  const normalized = normalizePurchaseLine(
    { qtyInPurchaseUom: purchaseQty, ...line },
    item,
  );
  return normalized.qtyInRecipeUom;
}

async function approvePurchase(dataStore, { tenantId, branchId, purchaseId, approvedBy, readMenuItems }) {
  return mutateInventory(dataStore, tenantId, async (blob) => {
    const purchases = scopeTenant(blob.purchases, tenantId);
    const idx = purchases.findIndex((p) => String(p.id) === String(purchaseId));
    if (idx < 0) {
      const err = new Error('أمر الشراء غير موجود');
      err.code = 404;
      throw err;
    }
    const purchase = { ...purchases[idx] };
    if (isDocClosed(purchase.status)) {
      const err = new Error('تم إغلاق أمر الشراء مسبقاً');
      err.code = 409;
      throw err;
    }

    const locations = ensureLocationsInBlob(blob, tenantId, branchId);
    const vendor = findLocation(locations, { kind: LOCATION_KIND.VENDOR });
    const stock = findLocation(locations, {
      kind: LOCATION_KIND.BRANCH_STOCK,
      branchId,
    });
    if (!vendor || !stock) {
      const err = new Error('مواقع المخزون غير مهيأة');
      err.code = 500;
      throw err;
    }

    const items = scopeTenant(blob.items, tenantId);
    const moves = [];

    for (const line of purchase.lines || []) {
      const itemIdx = items.findIndex((row) => String(row.id) === String(line.itemId));
      if (itemIdx < 0) continue;
      const item = { ...items[itemIdx] };
      const recipeQty = toRecipeQty(Number(line.qtyInPurchaseUom ?? line.qtyPurchased) || 0, line, item);
      const unitPriceRecipe = roundMoneyKwd(
        line.unitCostInRecipeUom ??
          normalizePurchaseLine(line, item).unitCostInRecipeUom,
      );

      item.avgCost = computeAvco({
        currentQty: item.currentQty,
        currentAvgCost: item.avgCost,
        purchasedQty: recipeQty,
        purchaseUnitCost: unitPriceRecipe,
      });
      item.lastPurchasePrice = unitPriceRecipe;
      item.lastPurchasePriceUom = 'recipe';
      item.lastPurchaseUnitCostPurchaseUom = roundMoneyKwd(
        line.unitCostInPurchaseUom ?? line.unitCost ?? 0,
      );
      item.currentQty = roundQty((Number(item.currentQty) || 0) + recipeQty);
      item.updatedAt = new Date().toISOString();

      const move = createStockMoveRecord({
        tenantId,
        branchId,
        fromLocation: vendor,
        toLocation: stock,
        itemId: item.id,
        qtyInRecipeUom: recipeQty,
        unitCostSnapshot: unitPriceRecipe,
        referenceType: MOVE_REFERENCE.PURCHASE,
        referenceId: purchase.id,
        createdBy: approvedBy,
      });
      moves.push(move);
      items[itemIdx] = item;
    }

    purchase.status = DOC_STATUS.CLOSED;
    purchase.approvedAt = new Date().toISOString();
    purchase.closedAt = purchase.approvedAt;
    purchase.approvedBy = approvedBy;
    purchase.closedBy = approvedBy;

    const otherPurchases = blob.purchases.filter(
      (p) => String(p.tenantId || p.restaurantId) !== String(tenantId),
    );
    const tenantPurchases = purchases.map((p, i) => (i === idx ? purchase : p));

    blob.items = [
      ...blob.items.filter(
        (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
      ),
      ...items,
    ];
    blob.moves = [...blob.moves, ...moves];
    blob.purchases = [...otherPurchases, ...tenantPurchases];

    let marginAlerts = [];
    if (typeof readMenuItems === 'function') {
      const menuItems = await readMenuItems();
      marginAlerts = evaluateMarginAlerts({
        recipes: blob.recipes,
        items: blob.items,
        menuItems,
        tenantId,
      });
    }
    blob.jobs = [
      ...(blob.jobs || []),
      attachTenant(
        {
          id: newId('job'),
          type: 'MARGIN_GUARD',
          status: 'DONE',
          purchaseId: purchase.id,
          alerts: marginAlerts,
          createdAt: new Date().toISOString(),
        },
        tenantId,
      ),
    ];

    return {
      blob,
      result: { purchase, moves, marginAlerts },
    };
  }).then((out) => out.result || out);
}

function createPurchaseRecord(body, tenantId, branchId, itemsById = new Map()) {
  const lines = (Array.isArray(body.lines) ? body.lines : []).map((line) => {
    const item = itemsById.get(String(line.itemId));
    if (!item) {
      return normalizePurchaseLine(line, {
        id: line.itemId,
        purchaseToStorageFactor: 1,
        storageToRecipeFactor: line.conversionToRecipeUom || 1,
      });
    }
    return normalizePurchaseLine(line, item);
  });
  const subtotal = roundMoneyKwd(
    lines.reduce(
      (s, line) =>
        s + (Number(line.unitCostInPurchaseUom) || 0) * (Number(line.qtyInPurchaseUom) || 0),
      0,
    ),
  );
  const taxAmount = roundMoneyKwd(body.taxAmount ?? body.tax_amount ?? 0);
  return attachTenant(
    {
      id: body.id || newId('pur'),
      branchId: String(branchId),
      vendorName: String(body.vendorName || body.vendor_name || '').trim(),
      supplierId: String(body.supplierId || body.supplier_id || '').trim(),
      invoiceRef: String(body.invoiceRef || body.invoice_ref || '').trim(),
      status: DOC_STATUS.DRAFT,
      subtotal,
      taxAmount,
      totalWithTax: roundMoneyKwd(subtotal + taxAmount),
      lines,
      createdAt: new Date().toISOString(),
    },
    tenantId,
  );
}

module.exports = {
  approvePurchase,
  createPurchaseRecord,
  toRecipeQty,
};