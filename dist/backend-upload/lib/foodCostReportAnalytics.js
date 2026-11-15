const {
  parseCostPrice,
  parseSellingPrice,
  computeFoodCostPercent,
  computeProfitMarginPercent,
} = require('./foodCostAnalytics');
const { isCancelledStatus, parseMenuItemId } = require('./topItemsAnalytics');
const { resolvePlatformKey, humanizePlatformKey } = require('./platformChannelUtils');

const MATRIX_LABELS = {
  star: 'نجوم',
  plowhorse: 'خيل عمل',
  puzzle: 'ألغاز',
  dog: 'كلاب',
};

function safePercent(numerator, denominator) {
  const num = Number(numerator) || 0;
  const den = Number(denominator) || 0;
  if (den <= 0) return 0;
  return Number(((num / den) * 100).toFixed(2));
}

function round3(value) {
  return Number((Number(value) || 0).toFixed(3));
}

function getOrderRestaurantId(order) {
  return order.restaurant_id || order.restaurantId || '';
}

function getOrderCreatedAt(order) {
  const raw = order.createdAt || order.created_at;
  const date = raw ? new Date(raw) : null;
  return date && !Number.isNaN(date.getTime()) ? date.getTime() : 0;
}

function emptyChannelRow(channel) {
  return {
    channel,
    labelAr: humanizePlatformKey(channel),
    quantitySold: 0,
    totalRevenue: 0,
    totalFoodCost: 0,
    grossProfit: 0,
    foodCostPercent: 0,
    grossProfitMarginPercent: 0,
  };
}

function getOrCreateChannelRow(channelTotals, channelKey) {
  const channel = resolvePlatformKey(channelKey);
  if (!channelTotals.has(channel)) {
    channelTotals.set(channel, emptyChannelRow(channel));
  }
  return channelTotals.get(channel);
}

function ensureItemChannelRow(row, channelKey) {
  const channel = resolvePlatformKey(channelKey);
  if (!row.channels[channel]) {
    row.channels[channel] = {
      quantitySold: 0,
      totalRevenue: 0,
      totalFoodCost: 0,
    };
  }
  return row.channels[channel];
}

function parseDateRange(options = {}) {
  const now = new Date();
  const endRaw = options.endDate || options.end_date;
  const startRaw = options.startDate || options.start_date;

  let end = endRaw ? new Date(endRaw) : now;
  if (Number.isNaN(end.getTime())) end = now;

  let start;
  if (startRaw) {
    start = new Date(startRaw);
    if (Number.isNaN(start.getTime())) {
      start = new Date(end.getTime() - 30 * 24 * 60 * 60 * 1000);
    }
  } else {
    const days = Math.max(1, Number(options.days) || 30);
    start = new Date(end.getTime() - days * 24 * 60 * 60 * 1000);
  }

  start.setHours(0, 0, 0, 0);
  end.setHours(23, 59, 59, 999);

  return {
    startMs: start.getTime(),
    endMs: end.getTime(),
    startDate: start.toISOString(),
    endDate: end.toISOString(),
  };
}

function classifyMenuEngineering(profitMarginPercent, quantitySold, thresholds) {
  const highProfit =
    profitMarginPercent != null &&
    profitMarginPercent >= thresholds.profitMarginMedian;
  const highPopularity = quantitySold >= thresholds.popularityMedian;

  if (highProfit && highPopularity) return 'star';
  if (!highProfit && highPopularity) return 'plowhorse';
  if (highProfit && !highPopularity) return 'puzzle';
  return 'dog';
}

function computeMedian(values) {
  const sorted = values.filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
  if (sorted.length === 0) return 0;
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
  return sorted[mid];
}

function serializeItemChannels(channels) {
  return Object.fromEntries(
    Object.entries(channels || {}).map(([channel, ch]) => [
      channel,
      {
        quantitySold: ch.quantitySold,
        totalRevenue: round3(ch.totalRevenue),
        totalFoodCost: round3(ch.totalFoodCost),
        grossProfit: round3(ch.totalRevenue - ch.totalFoodCost),
      },
    ]),
  );
}

/**
 * Food Cost & Menu Engineering report.
 */
function computeFoodCostReport(orders, menuItems, restaurantId, options = {}) {
  const range = parseDateRange(options);
  const scopedItems = (menuItems || []).filter(
    (item) =>
      String(item.restaurant_id || item.restaurantId || restaurantId) ===
      String(restaurantId),
  );

  const itemById = new Map(
    scopedItems.map((item) => [Number(item.id), item]),
  );

  const aggregates = new Map();
  const channelTotals = new Map();

  for (const item of scopedItems) {
    const id = Number(item.id);
    if (!Number.isFinite(id) || id <= 0) continue;
    const sellingPrice = parseSellingPrice(item) || 0;
    const costPrice = parseCostPrice(item);

    aggregates.set(id, {
      menuItemId: id,
      sku: String(id),
      name: item.name || item.name_ar || item.nameAr || '',
      categoryName: item.category_name || item.categoryName || '',
      sellingPrice,
      costPrice,
      quantitySold: 0,
      totalRevenue: 0,
      totalFoodCost: 0,
      grossProfit: 0,
      foodCostPercent: costPrice != null ? computeFoodCostPercent(sellingPrice, costPrice) : null,
      grossProfitMarginPercent:
        costPrice != null ? computeProfitMarginPercent(sellingPrice, costPrice) : null,
      channels: {},
    });
  }

  for (const order of orders || []) {
    if (getOrderRestaurantId(order) !== restaurantId) continue;
    if (isCancelledStatus(order.status)) continue;

    const createdAt = getOrderCreatedAt(order);
    if (createdAt < range.startMs || createdAt > range.endMs) continue;

    const channel = resolvePlatformKey(order.orderSource || order.order_source);
    const channelRow = getOrCreateChannelRow(channelTotals, channel);

    for (const line of order.items || []) {
      const menuItemId = parseMenuItemId(
        line.menuItemId ?? line.menu_item_id ?? line.id,
      );
      if (!menuItemId) continue;

      const quantity = Math.max(1, Number(line.quantity) || 1);
      const unitPrice =
        Number(line.unitPrice ?? line.unit_price ?? line.price) ||
        parseSellingPrice(itemById.get(menuItemId)) ||
        0;

      let row = aggregates.get(menuItemId);
      if (!row) {
        const menuItem = itemById.get(menuItemId);
        const sellingPrice =
          unitPrice || (menuItem ? parseSellingPrice(menuItem) : 0) || 0;
        const costPrice = menuItem ? parseCostPrice(menuItem) : null;
        row = {
          menuItemId,
          sku: String(menuItemId),
          name: line.name || menuItem?.name || menuItem?.name_ar || '',
          categoryName: menuItem?.category_name || menuItem?.categoryName || '',
          sellingPrice,
          costPrice,
          quantitySold: 0,
          totalRevenue: 0,
          totalFoodCost: 0,
          grossProfit: 0,
          foodCostPercent:
            costPrice != null ? computeFoodCostPercent(sellingPrice, costPrice) : null,
          grossProfitMarginPercent:
            costPrice != null
              ? computeProfitMarginPercent(sellingPrice, costPrice)
              : null,
          channels: {},
        };
        aggregates.set(menuItemId, row);
      }

      const effectiveSellingPrice = unitPrice > 0 ? unitPrice : row.sellingPrice;
      const lineRevenue = effectiveSellingPrice * quantity;
      const unitCost = row.costPrice != null ? row.costPrice : 0;
      const lineFoodCost = row.costPrice != null ? unitCost * quantity : 0;
      const lineProfit = lineRevenue - lineFoodCost;

      row.quantitySold += quantity;
      row.totalRevenue += lineRevenue;
      row.totalFoodCost += lineFoodCost;
      row.grossProfit += lineProfit;

      const itemChannel = ensureItemChannelRow(row, channel);
      itemChannel.quantitySold += quantity;
      itemChannel.totalRevenue += lineRevenue;
      itemChannel.totalFoodCost += lineFoodCost;

      channelRow.quantitySold += quantity;
      channelRow.totalRevenue += lineRevenue;
      channelRow.totalFoodCost += lineFoodCost;
    }
  }

  const soldItems = [...aggregates.values()].filter((row) => row.quantitySold > 0);
  const profitMargins = soldItems
    .map((row) => row.grossProfitMarginPercent)
    .filter((v) => v != null);
  const popularityValues = soldItems.map((row) => row.quantitySold);

  const thresholds = {
    popularityMedian: computeMedian(popularityValues),
    profitMarginMedian: computeMedian(profitMargins),
  };

  let summaryRevenue = 0;
  let summaryFoodCost = 0;

  const items = [...aggregates.values()]
    .map((row) => {
      const categoryKey = classifyMenuEngineering(
        row.grossProfitMarginPercent,
        row.quantitySold,
        thresholds,
      );

      summaryRevenue += row.totalRevenue;
      summaryFoodCost += row.totalFoodCost;

      return {
        menuItemId: row.menuItemId,
        sku: row.sku,
        name: row.name,
        categoryName: row.categoryName,
        sellingPrice: round3(row.sellingPrice),
        costPrice: row.costPrice != null ? round3(row.costPrice) : null,
        quantitySold: row.quantitySold,
        totalRevenue: round3(row.totalRevenue),
        totalFoodCost: round3(row.totalFoodCost),
        grossProfit: round3(row.grossProfit),
        netProfit: round3(row.grossProfit),
        foodCostPercent:
          row.totalRevenue > 0 && row.costPrice != null
            ? safePercent(row.totalFoodCost, row.totalRevenue)
            : row.foodCostPercent,
        grossProfitMarginPercent:
          row.totalRevenue > 0 && row.costPrice != null
            ? safePercent(row.grossProfit, row.totalRevenue)
            : row.grossProfitMarginPercent,
        menuEngineeringCategory: categoryKey,
        menuEngineeringLabelAr: MATRIX_LABELS[categoryKey] || categoryKey,
        channels: serializeItemChannels(row.channels),
      };
    })
    .sort((a, b) => b.totalRevenue - a.totalRevenue);

  const grossProfit = summaryRevenue - summaryFoodCost;
  const channels = [...channelTotals.values()]
    .map((row) => {
      const revenue = row.totalRevenue;
      const foodCost = row.totalFoodCost;
      const profit = revenue - foodCost;
      return {
        channel: row.channel,
        labelAr: row.labelAr,
        quantitySold: row.quantitySold,
        totalRevenue: round3(revenue),
        totalFoodCost: round3(foodCost),
        grossProfit: round3(profit),
        foodCostPercent: safePercent(foodCost, revenue),
        grossProfitMarginPercent: safePercent(profit, revenue),
      };
    })
    .sort((a, b) => b.totalRevenue - a.totalRevenue);

  const matrix = { star: [], plowhorse: [], puzzle: [], dog: [] };
  for (const item of items) {
    const key = item.menuEngineeringCategory;
    if (matrix[key]) matrix[key].push(item.menuItemId);
  }

  return {
    restaurantId,
    startDate: range.startDate,
    endDate: range.endDate,
    summary: {
      totalRevenue: round3(summaryRevenue),
      totalFoodCost: round3(summaryFoodCost),
      grossProfit: round3(grossProfit),
      grossProfitMarginPercent: safePercent(grossProfit, summaryRevenue),
      overallFoodCostPercent: safePercent(summaryFoodCost, summaryRevenue),
      itemsTracked: items.length,
      itemsSold: soldItems.length,
      quantitySold: soldItems.reduce((sum, row) => sum + row.quantitySold, 0),
    },
    channels,
    thresholds,
    matrix: Object.fromEntries(
      Object.entries(matrix).map(([key, ids]) => [
        key,
        {
          labelAr: MATRIX_LABELS[key],
          count: ids.length,
          menuItemIds: ids,
        },
      ]),
    ),
    items,
    source: soldItems.length > 0 ? 'live' : 'empty',
  };
}

module.exports = {
  computeFoodCostReport,
  resolvePlatformKey,
  MATRIX_LABELS,
};
