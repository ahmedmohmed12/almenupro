'use strict';

const { roundMoneyKwd, roundQty, MOVE_REFERENCE, isDocClosed } = require('./constants');
const { scopeTenant } = require('./inventoryRepository');
const { explodeMenuItemToRequirements } = require('./recipeExplosion');
const { estimateMenuItemCost } = require('./recipeCostService');
const { mapSalesChannel } = require('./recipeEngine');

function parseRange(from, to) {
  const fromTs = from ? Date.parse(from) : 0;
  const toTs = to ? Date.parse(to) : Date.now();
  return { fromTs, toTs };
}

function inRange(iso, fromTs, toTs) {
  const t = Date.parse(iso || 0) || 0;
  return t >= fromTs && t <= toTs;
}

function filterByCategory(items, category) {
  if (!category || !String(category).trim()) return items;
  const cat = String(category).trim().toLowerCase();
  return items.filter((row) => String(row.category || '').toLowerCase() === cat);
}

function branchLevelsFor(item, branchId) {
  const rows = Array.isArray(item.branchLevels) ? item.branchLevels : [];
  const match = rows.find((r) => String(r.branchId) === String(branchId));
  if (match) {
    return {
      minLevel: roundQty(match.minLevel ?? item.minLevel ?? item.minStockAlert ?? 0),
      parLevel: roundQty(match.parLevel ?? 0),
      maxLevel: roundQty(match.maxLevel ?? 0),
    };
  }
  return {
    minLevel: roundQty(item.minLevel ?? item.minStockAlert ?? 0),
    parLevel: roundQty(item.parLevel ?? 0),
    maxLevel: roundQty(item.maxLevel ?? 0),
  };
}

function reportInventoryLevels(blob, tenantId, branchId, category) {
  let items = scopeTenant(blob.items, tenantId).filter(
    (row) => !branchId || String(row.branchId) === String(branchId),
  );
  items = filterByCategory(items, category);
  return items.map((item) => {
    const qty = roundQty(item.currentQty);
    const avg = roundMoneyKwd(item.avgCost);
    const levels = branchLevelsFor(item, branchId);
    const low =
      levels.minLevel > 0 && qty <= levels.minLevel ? 'LOW' : qty <= 0 ? 'OUT' : 'OK';
    return {
      itemId: item.id,
      sku: item.sku,
      name: item.name,
      category: item.category,
      itemType: item.itemType,
      currentQty: qty,
      recipeUom: item.recipeUom,
      avgCost: avg,
      totalValuation: roundMoneyKwd(qty * avg),
      ...levels,
      stockStatus: low,
    };
  });
}

function reportInventoryHistory(blob, tenantId, { itemId, from, to }) {
  const { fromTs, toTs } = parseRange(from, to);
  let moves = scopeTenant(blob.moves, tenantId);
  if (itemId) {
    moves = moves.filter((m) => String(m.itemId) === String(itemId));
  }
  moves = moves
    .filter((m) => inRange(m.createdAt, fromTs, toTs))
    .sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));

  let balance = 0;
  const item = itemId
    ? scopeTenant(blob.items, tenantId).find((row) => String(row.id) === String(itemId))
    : null;
  if (item) balance = roundQty(item.currentQty);

  const rows = [];
  for (let i = moves.length - 1; i >= 0; i--) {
    const m = moves[i];
    const qty = roundQty(m.qtyInRecipeUom);
    const isIn =
      m.toLocationKind &&
      ['BRANCH_STOCK', 'KITCHEN_PREP'].includes(m.toLocationKind) &&
      !['BRANCH_STOCK', 'KITCHEN_PREP'].includes(m.fromLocationKind || '');
    const delta = isIn ? qty : -qty;
    balance = roundQty(balance - delta);
  }

  for (const m of moves) {
    const qty = roundQty(m.qtyInRecipeUom);
    const isIn =
      m.toLocationKind &&
      ['BRANCH_STOCK', 'KITCHEN_PREP'].includes(m.toLocationKind) &&
      !['BRANCH_STOCK', 'KITCHEN_PREP'].includes(m.fromLocationKind || '');
    const delta = isIn ? qty : -qty;
    balance = roundQty(balance + delta);
    rows.push({
      date: m.createdAt,
      type: m.referenceType,
      referenceId: m.referenceId,
      inQty: isIn ? qty : 0,
      outQty: isIn ? 0 : qty,
      runningBalance: balance,
      unitCost: m.unitCostSnapshot,
      totalCost: m.totalCost,
      user: m.createdBy,
      moveId: m.id,
    });
  }
  return rows;
}

function sumMovesByType(moves, types, direction) {
  return moves
    .filter((m) => types.includes(m.referenceType))
    .reduce((sum, m) => {
      const qty = roundQty(m.qtyInRecipeUom);
      const isOut =
        m.fromLocationKind &&
        ['BRANCH_STOCK', 'KITCHEN_PREP'].includes(m.fromLocationKind);
      if (direction === 'OUT' && isOut) return sum + qty;
      const isIn =
        m.toLocationKind &&
        ['BRANCH_STOCK', 'KITCHEN_PREP'].includes(m.toLocationKind);
      if (direction === 'IN' && isIn) return sum + qty;
      return sum;
    }, 0);
}

function theoreticalConsumptionFromOrders(orders, blob, tenantId, fromTs, toTs, branchId) {
  const map = new Map();
  for (const order of orders || []) {
    const rid = String(order.restaurant_id || order.restaurantId || '');
    if (rid !== String(tenantId)) continue;
    if (branchId) {
      const bid = String(order.branchId || order.branch_id || rid);
      if (bid !== String(branchId)) continue;
    }
    if (!inRange(order.createdAt || order.created_at, fromTs, toTs)) continue;
    if (!['delivered', 'completed', 'paid'].includes(String(order.status || '').toLowerCase())) {
      continue;
    }
    for (const line of order.items || []) {
      const menuItemId =
        line.menuItemId || line.menu_item_id || line.id || line.itemId;
      if (!menuItemId) continue;
      const qty = roundQty(line.quantity ?? line.qty ?? 1);
      const channel = mapSalesChannel(order);
      const needs = explodeMenuItemToRequirements({
        menuItemId,
        qty,
        channel,
        recipes: blob.recipes,
        items: blob.items,
        tenantId,
      });
      for (const need of needs) {
        map.set(need.itemId, roundQty((map.get(need.itemId) || 0) + need.qtyInRecipeUom));
      }
    }
  }
  return map;
}

function reportInventoryControl(blob, tenantId, orders, { branchId, from, to, category }) {
  const { fromTs, toTs } = parseRange(from, to);
  let items = scopeTenant(blob.items, tenantId);
  items = filterByCategory(items, category);
  let moves = scopeTenant(blob.moves, tenantId).filter((m) =>
    inRange(m.createdAt, fromTs, toTs),
  );
  if (branchId) {
    moves = moves.filter((m) => String(m.branchId) === String(branchId));
  }

  const theoretical = theoreticalConsumptionFromOrders(
    orders,
    blob,
    tenantId,
    fromTs,
    toTs,
    branchId,
  );

  return items.map((item) => {
    const itemMoves = moves.filter((m) => String(m.itemId) === String(item.id));
    const purchases = sumMovesByType(itemMoves, [MOVE_REFERENCE.PURCHASE], 'IN');
    const waste = sumMovesByType(itemMoves, [MOVE_REFERENCE.WASTE], 'OUT');
    const transferIn = itemMoves
      .filter((m) => m.referenceType === MOVE_REFERENCE.TRANSFER && m.notes?.includes('receive'))
      .reduce((s, m) => s + roundQty(m.qtyInRecipeUom), 0);
    const transferOut = itemMoves
      .filter((m) => m.referenceType === MOVE_REFERENCE.TRANSFER && m.notes?.includes('transfer_send'))
      .reduce((s, m) => s + roundQty(m.qtyInRecipeUom), 0);

    const opening = roundQty(item.currentQty);
    const closing = opening;
    const actualConsumption = roundQty(
      opening + purchases + transferIn - transferOut - waste - closing,
    );
    const theoreticalQty = roundQty(theoretical.get(String(item.id)) || 0);
    const varianceQty = roundQty(actualConsumption - theoreticalQty);
    const avg = Number(item.avgCost) || 0;
    return {
      itemId: item.id,
      name: item.name,
      openingStock: opening,
      purchases,
      transferIn,
      transferOut,
      recordedWaste: waste,
      closingCount: closing,
      actualConsumption,
      theoreticalConsumption: theoreticalQty,
      varianceQty,
      varianceCost: roundMoneyKwd(varianceQty * avg),
    };
  });
}

function reportMenuCostMargin(blob, tenantId, orders, menuItems, { from, to, category }) {
  const { fromTs, toTs } = parseRange(from, to);
  const byMenu = new Map();

  for (const order of orders || []) {
    const rid = String(order.restaurant_id || order.restaurantId || '');
    if (rid !== String(tenantId)) continue;
    if (!inRange(order.createdAt || order.created_at, fromTs, toTs)) continue;
    if (!['delivered', 'completed', 'paid'].includes(String(order.status || '').toLowerCase())) {
      continue;
    }
    for (const line of order.items || []) {
      const menuItemId =
        line.menuItemId || line.menu_item_id || line.id || line.itemId;
      if (!menuItemId) continue;
      const qty = roundQty(line.quantity ?? line.qty ?? 1);
      const lineTotal =
        Number(line.totalPrice ?? line.lineTotal) ||
        (Number(line.price) || 0) * qty;
      const entry = byMenu.get(String(menuItemId)) || { soldQty: 0, netSales: 0 };
      entry.soldQty += qty;
      entry.netSales += lineTotal;
      byMenu.set(String(menuItemId), entry);
    }
  }

  const catFilter = category ? String(category).trim().toLowerCase() : '';
  const rows = [];
  for (const [menuItemId, agg] of byMenu.entries()) {
    const menuItem = menuItems.find((m) => String(m.id) === menuItemId);
    if (catFilter) {
      const menuCat = String(menuItem?.category || menuItem?.categoryName || '').toLowerCase();
      if (menuCat !== catFilter) continue;
    }
    const estimate = estimateMenuItemCost({
      menuItemId,
      channel: 'TAKEAWAY',
      recipes: blob.recipes,
      packagingProfiles: blob.packagingProfiles,
      items: blob.items,
      tenantId,
      menuItem,
    });
    const unitCost = estimate.totalCost;
    const cogs = roundMoneyKwd(unitCost * agg.soldQty);
    const profit = roundMoneyKwd(agg.netSales - cogs);
    const foodCostPct =
      agg.netSales > 0 ? roundMoneyKwd(cogs / agg.netSales) : 0;
    rows.push({
      menuItemId,
      name: menuItem?.name || menuItem?.name_ar || menuItemId,
      soldQty: roundQty(agg.soldQty),
      netSales: roundMoneyKwd(agg.netSales),
      unitCost,
      totalCogs: cogs,
      profit,
      foodCostPct,
      sellingPrice: Number(menuItem?.price) || 0,
    });
  }
  return rows.sort((a, b) => b.netSales - a.netSales);
}

function reportPurchasingWasteSummary(blob, tenantId, { from, to, branchId }) {
  const { fromTs, toTs } = parseRange(from, to);
  const purchases = scopeTenant(blob.purchases, tenantId).filter(
    (p) => isDocClosed(p.status) && inRange(p.approvedAt || p.closedAt || p.createdAt, fromTs, toTs),
  );
  const wasteDocs = scopeTenant(blob.wasteDocuments, tenantId).filter(
    (w) => isDocClosed(w.status) && inRange(w.closedAt || w.createdAt, fromTs, toTs),
  );

  const bySupplier = new Map();
  for (const p of purchases) {
    if (branchId && String(p.branchId) !== String(branchId)) continue;
    const key = p.vendorName || 'unknown';
    const total = (p.lines || []).reduce(
      (s, line) =>
        s +
        (Number(line.unitCostInPurchaseUom ?? line.unitCost) || 0) *
          (Number(line.qtyInPurchaseUom ?? line.qtyPurchased) || 0),
      0,
    );
    bySupplier.set(key, roundMoneyKwd((bySupplier.get(key) || 0) + total));
  }

  const byReason = new Map();
  for (const doc of wasteDocs) {
    if (branchId && String(doc.branchId) !== String(branchId)) continue;
    for (const line of doc.lines || []) {
      const reason = line.wasteReason || 'OTHER';
      byReason.set(reason, roundQty((byReason.get(reason) || 0) + (line.qty || 0)));
    }
  }

  return {
    purchasesBySupplier: [...bySupplier.entries()].map(([supplier, total]) => ({
      supplier,
      total,
    })),
    wasteByReason: [...byReason.entries()].map(([reason, qty]) => ({ reason, qty })),
    closedPurchaseCount: purchases.length,
    closedWasteDocCount: wasteDocs.length,
  };
}

const reportInventoryVariance = reportInventoryControl;
const reportCogs = reportMenuCostMargin;

module.exports = {
  filterByCategory,
  reportInventoryLevels,
  reportInventoryHistory,
  reportInventoryControl,
  reportInventoryVariance,
  reportMenuCostMargin,
  reportCogs,
  reportPurchasingWasteSummary,
};