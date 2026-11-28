'use strict';

const { computeAvco } = require('./avco');
const {
  LOCATION_KIND,
  MOVE_REFERENCE,
  PURCHASE_STATUS,
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

function toRecipeQty(purchaseQty, line) {
  const factor = Number(line.conversionToRecipeUom || line.conversionFactor || 1);
  return roundQty(purchaseQty * factor);
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
    if (purchase.status === PURCHASE_STATUS.APPROVED) {
      const err = new Error('تم اعتماد أمر الشراء مسبقاً');
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
      const recipeQty = toRecipeQty(Number(line.qtyPurchased) || 0, line);
      const unitPriceRecipe = roundMoneyKwd(
        (Number(line.unitCost) || 0) /
          (Number(line.conversionToRecipeUom || line.conversionFactor) || 1),
      );

      item.avgCost = computeAvco({
        currentQty: item.currentQty,
        currentAvgCost: item.avgCost,
        purchasedQty: recipeQty,
        purchaseUnitCost: unitPriceRecipe,
      });
      item.lastPurchasePrice = unitPriceRecipe;
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

    purchase.status = PURCHASE_STATUS.APPROVED;
    purchase.approvedAt = new Date().toISOString();
    purchase.approvedBy = approvedBy;

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

function createPurchaseRecord(body, tenantId, branchId) {
  const lines = (Array.isArray(body.lines) ? body.lines : []).map((line) => ({
    itemId: String(line.itemId),
    qtyPurchased: roundQty(line.qtyPurchased),
    unitCost: roundMoneyKwd(line.unitCost),
    purchaseUom: line.purchaseUom || line.purchase_uom || 'unit',
    conversionToRecipeUom: roundQty(line.conversionToRecipeUom || line.conversionFactor || 1),
  }));
  return attachTenant(
    {
      id: body.id || newId('pur'),
      branchId: String(branchId),
      vendorName: String(body.vendorName || body.vendor_name || '').trim(),
      invoiceRef: String(body.invoiceRef || body.invoice_ref || '').trim(),
      status: PURCHASE_STATUS.DRAFT,
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