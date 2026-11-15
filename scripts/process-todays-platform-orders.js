'use strict';

const dataStore = require('../lib/dataStore');
const {
  normalizePlatform,
  resolveExternalOrderItems,
} = require('../lib/platformItemMappings');
const { isKuwaitToday, kuwaitDateKey } = require('../lib/kuwaitBusinessDay');

const SUPPORTED_PLATFORMS = new Set(['talabat', 'jahez', 'keeta']);

function orderPlatform(order) {
  return normalizePlatform(
    order.orderSource || order.order_source || order.platform || order.source,
  );
}

function orderRestaurantId(order) {
  return String(order.restaurantId || order.restaurant_id || '').trim();
}

function orderCreatedAt(order) {
  return order.createdAt || order.created_at || order.orderDate || order.date;
}

function amount(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function isCancelled(order) {
  const status = String(
    order.externalStatus ||
      order.external_status ||
      order.status ||
      '',
  ).toLowerCase();
  return /cancel|refund|reject|void|ملغ|مرفوض|مسترد/.test(status);
}

function lineQuantity(line) {
  return Math.max(1, Number(line.quantity || line.qty) || 1);
}

function lineRevenue(line) {
  const explicit = amount(
    line.lineTotal || line.line_total || line.totalPrice || line.total_price,
  );
  if (explicit > 0) return explicit;
  return amount(line.unitPrice || line.unit_price || line.price) * lineQuantity(line);
}

function mappingStats(items) {
  let mapped = 0;
  let unmapped = 0;
  for (const line of items || []) {
    if (line.isUnmapped || line.is_unmapped) unmapped += 1;
    else mapped += 1;
    const options = line.selectedOptions || line.options || [];
    for (const option of options) {
      if (option.isUnmapped || option.is_unmapped) unmapped += 1;
      else mapped += 1;
    }
  }
  return { mapped, unmapped };
}

async function main() {
  await dataStore.initDataStore();
  const orders = await dataStore.readOrders();
  const today = orders.filter((order) => {
    const platform = orderPlatform(order);
    return (
      SUPPORTED_PLATFORMS.has(platform) &&
      isKuwaitToday(orderCreatedAt(order))
    );
  });

  const platformTotals = new Map();
  const itemTotals = new Map();
  let totalRevenue = 0;
  let mapped = 0;
  let unmapped = 0;
  let updated = 0;

  for (const order of today) {
    const platform = orderPlatform(order);
    const restaurantId = orderRestaurantId(order);
    if (!restaurantId) {
      console.warn(`[PlatformSales] skipped order ${order.id}: missing restaurant`);
      continue;
    }

    const resolved = await resolveExternalOrderItems(
      { ...order, platform, items: order.items || [] },
      restaurantId,
    );
    const nextOrder = {
      ...order,
      items: resolved.items,
      platformMappingProcessedAt: new Date().toISOString(),
      platform_mapping_processed_at: new Date().toISOString(),
    };
    await dataStore.patchOrderById(order.id, nextOrder);
    updated += 1;

    const stats = mappingStats(resolved.items);
    mapped += stats.mapped;
    unmapped += stats.unmapped;

    if (isCancelled(nextOrder)) continue;
    const revenue = amount(
      nextOrder.totalPrice || nextOrder.total_price || nextOrder.total,
    );
    totalRevenue += revenue;
    const currentPlatform = platformTotals.get(platform) || {
      orders: 0,
      revenue: 0,
    };
    currentPlatform.orders += 1;
    currentPlatform.revenue += revenue;
    platformTotals.set(platform, currentPlatform);

    for (const line of resolved.items || []) {
      const canonicalId = String(
        line.menuItemId || line.menu_item_id || line.platformItemId || line.name,
      );
      const currentItem = itemTotals.get(canonicalId) || {
        name: line.name || line.title || canonicalId,
        quantity: 0,
        revenue: 0,
        isUnmapped: Boolean(line.isUnmapped || line.is_unmapped),
      };
      currentItem.quantity += lineQuantity(line);
      currentItem.revenue += lineRevenue(line);
      itemTotals.set(canonicalId, currentItem);
    }
  }

  const summary = {
    businessDate: kuwaitDateKey(),
    ordersProcessed: today.length,
    ordersUpdated: updated,
    totalRevenue: Number(totalRevenue.toFixed(3)),
    mappedEntities: mapped,
    unmappedEntities: unmapped,
    platformBreakdown: Object.fromEntries(
      [...platformTotals.entries()].map(([platform, value]) => [
        platform,
        {
          orders: value.orders,
          revenue: Number(value.revenue.toFixed(3)),
        },
      ]),
    ),
    itemTotals: [...itemTotals.entries()]
      .map(([posItemId, value]) => ({
        posItemId,
        ...value,
        revenue: Number(value.revenue.toFixed(3)),
      }))
      .sort((a, b) => b.quantity - a.quantity),
  };

  console.log('[PlatformSales] Full daily processing completed');
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error('[PlatformSales] Processing failed:', error);
  process.exitCode = 1;
});
