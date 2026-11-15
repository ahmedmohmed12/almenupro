'use strict';

const { getItemProfitMetrics } = require('./foodCostAnalytics');

const COMBO_FAMILY_PATTERN =
  /combo|كومبو|عائلت|عائلي|family|تشارك|sharing|وجبه?\s*عائلي|meal\s*deal/i;

const QUADRANT_RANK = {
  star: { star: 0, puzzle: 1, plowhorse: 2, dog: 3 },
  plowhorse: { plowhorse: 0, star: 1, puzzle: 2, dog: 3 },
  budget: { dog: 0, plowhorse: 1, puzzle: 2, star: 3 },
};

function clampPaydayStartDay(value) {
  const day = Number(value);
  if (!Number.isFinite(day)) return 1;
  return Math.min(31, Math.max(1, Math.round(day)));
}

function isDynamicMenuSortingEnabled(settings = {}) {
  return (
    settings.dynamicMenuSortingEnabled === true ||
    settings.dynamic_menu_sorting_enabled === true ||
    settings.enable_dynamic_menu === true ||
    settings.enableDynamicMenu === true
  );
}

function paydayStartDayFromSettings(settings = {}) {
  return clampPaydayStartDay(
    settings.paydayStartDay ?? settings.payday_start_day ?? 1,
  );
}

function kuwaitYmd(date = new Date()) {
  const formatted = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Kuwait',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
  const [year, month, day] = formatted.split('-').map(Number);
  return { year, monthIndex: month - 1, day };
}

function daysInMonth(year, monthIndex) {
  return new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
}

function paydayOn(year, monthIndex, paydayStartDay) {
  return Math.min(clampPaydayStartDay(paydayStartDay), daysInMonth(year, monthIndex));
}

function ymdUtc(year, monthIndex, day) {
  return Date.UTC(year, monthIndex, day);
}

/**
 * 1-based day inside the payday cycle, and the 10/10/rest phase.
 * Phase: star (days 1-10), plowhorse (11-20), budget (21+ until next payday).
 */
function paydayCycleInfo(now = new Date(), paydayStartDay = 1) {
  const startDay = clampPaydayStartDay(paydayStartDay);
  const { year, monthIndex, day } = kuwaitYmd(now);
  const thisPayday = paydayOn(year, monthIndex, startDay);
  const todayUtc = ymdUtc(year, monthIndex, day);
  const thisPaydayUtc = ymdUtc(year, monthIndex, thisPayday);

  let cycleStartUtc;
  let nextPaydayUtc;
  if (todayUtc >= thisPaydayUtc) {
    cycleStartUtc = thisPaydayUtc;
    const nextMonth = monthIndex === 11 ? 0 : monthIndex + 1;
    const nextYear = monthIndex === 11 ? year + 1 : year;
    nextPaydayUtc = ymdUtc(nextYear, nextMonth, paydayOn(nextYear, nextMonth, startDay));
  } else {
    const prevMonth = monthIndex === 0 ? 11 : monthIndex - 1;
    const prevYear = monthIndex === 0 ? year - 1 : year;
    cycleStartUtc = ymdUtc(prevYear, prevMonth, paydayOn(prevYear, prevMonth, startDay));
    nextPaydayUtc = thisPaydayUtc;
  }

  const dayMs = 24 * 60 * 60 * 1000;
  const cycleDay = Math.floor((todayUtc - cycleStartUtc) / dayMs) + 1;
  const cycleLength = Math.max(1, Math.round((nextPaydayUtc - cycleStartUtc) / dayMs));
  let phase = 'budget';
  if (cycleDay <= 10) phase = 'star';
  else if (cycleDay <= 20) phase = 'plowhorse';

  return {
    paydayStartDay: startDay,
    cycleDay,
    cycleLength,
    phase,
  };
}

function displayOrderOf(item) {
  const value = Number(item?.display_order ?? item?.displayOrder ?? 0);
  return Number.isFinite(value) ? value : 0;
}

function idOf(item) {
  const value = Number(item?.id);
  return Number.isFinite(value) ? value : 0;
}

function priceOf(item) {
  const value = Number(item?.selling_price ?? item?.sellingPrice ?? item?.price);
  return Number.isFinite(value) ? value : 0;
}

function isComboOrFamilyItem(item) {
  const haystack = [
    item?.name,
    item?.name_ar,
    item?.nameAr,
    item?.name_en,
    item?.nameEn,
    item?.category_name,
    item?.categoryName,
    item?.category_name_en,
    item?.categoryNameEn,
  ]
    .filter(Boolean)
    .join(' ');
  return COMBO_FAMILY_PATTERN.test(haystack);
}

function compareManualOrder(a, b, categoryRanks = null) {
  if (categoryRanks && typeof categoryRanks.get === 'function') {
    const nameA = String(a?.category_name || a?.categoryName || '').trim();
    const nameB = String(b?.category_name || b?.categoryName || '').trim();
    const rankA =
      categoryRanks.get(nameA) ??
      categoryRanks.get(nameA.toLowerCase()) ??
      Number.MAX_SAFE_INTEGER;
    const rankB =
      categoryRanks.get(nameB) ??
      categoryRanks.get(nameB.toLowerCase()) ??
      Number.MAX_SAFE_INTEGER;
    if (rankA !== rankB) return rankA - rankB;
  }
  const order = displayOrderOf(a) - displayOrderOf(b);
  if (order !== 0) return order;
  return idOf(a) - idOf(b);
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

function parseLineMenuItemId(line) {
  const raw = line?.menuItemId ?? line?.menu_item_id ?? line?.id;
  if (raw == null || raw === '') return null;
  const asNumber = Number(raw);
  if (Number.isFinite(asNumber) && asNumber > 0) return asNumber;
  const digits = String(raw).replace(/\D/g, '');
  if (!digits) return null;
  const parsed = Number(digits);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function isCancelledStatus(status) {
  const value = String(status || '').trim().toLowerCase();
  return value === 'cancelled' || value === 'canceled' || value === 'ملغي';
}

function countItemSales(orders, restaurantId, days = 90) {
  const counts = new Map();
  const wanted = String(restaurantId || '');
  const cutoff = Date.now() - Math.max(1, days) * 24 * 60 * 60 * 1000;
  for (const order of orders || []) {
    const rid = String(order?.restaurant_id || order?.restaurantId || '');
    if (wanted && rid && rid !== wanted) continue;
    if (isCancelledStatus(order?.status)) continue;
    const created = Date.parse(order?.createdAt || order?.created_at || '');
    if (Number.isFinite(created) && created < cutoff) continue;
    for (const line of order?.items || []) {
      const menuItemId = parseLineMenuItemId(line);
      if (!menuItemId) continue;
      const quantity = Math.max(1, Number(line.quantity) || 1);
      counts.set(menuItemId, (counts.get(menuItemId) || 0) + quantity);
    }
  }
  return counts;
}

function classifyBcgQuadrant(profitMarginPercent, quantitySold, thresholds) {
  const highProfit =
    profitMarginPercent != null &&
    profitMarginPercent >= (thresholds.profitMarginMedian || 0);
  const highPopularity = quantitySold >= Math.max(1, thresholds.popularityMedian || 1);
  if (highProfit && highPopularity) return 'star';
  if (!highProfit && highPopularity) return 'plowhorse';
  if (highProfit && !highPopularity) return 'puzzle';
  return 'dog';
}

function catalogBadgeAr(quadrant, phase) {
  if (phase === 'star') {
    if (quadrant === 'star') return 'الأكثر طلباً';
    if (quadrant === 'puzzle') return 'موصى به';
  }
  if (phase === 'plowhorse' && quadrant === 'plowhorse') return 'شائع';
  if (phase === 'budget' && quadrant === 'dog') return 'توفير';
  return null;
}

function profitMarginAmount(item) {
  const metrics = getItemProfitMetrics(item);
  if (metrics.sellingPrice == null || metrics.costPrice == null) return null;
  return Number((metrics.sellingPrice - metrics.costPrice).toFixed(3));
}

function annotateCatalogItem(item, { counts, thresholds, phase, hasSales }) {
  const id = idOf(item);
  const orderCount = counts?.get(id) || Number(item.order_count || item.orderCount || 0) || 0;
  const metrics = getItemProfitMetrics(item);
  const marginPercent = metrics.profitMargin;
  const marginAmount = profitMarginAmount(item);
  const sellingPrice = priceOf(item);
  let quadrant = item.engineeringQuadrant || item.engineering_quadrant;
  if (hasSales) {
    quadrant = classifyBcgQuadrant(marginPercent, orderCount, thresholds);
  } else if (!quadrant) {
    if (marginPercent != null && marginPercent >= (thresholds.profitMarginMedian || 0)) {
      quadrant = isComboOrFamilyItem(item) ? 'puzzle' : 'star';
    } else if (isComboOrFamilyItem(item)) {
      quadrant = 'plowhorse';
    } else {
      quadrant = 'dog';
    }
  }
  const badge = catalogBadgeAr(quadrant, phase);
  return {
    ...item,
    selling_price: sellingPrice,
    sellingPrice,
    order_count: orderCount,
    orderCount,
    profit_margin: marginAmount,
    profitMargin: marginAmount,
    profit_margin_percent: marginPercent,
    profitMarginPercent: marginPercent,
    engineering_quadrant: quadrant,
    engineeringQuadrant: quadrant,
    catalog_badge: badge,
    catalogBadge: badge,
  };
}

function compareByMarginThenPrice(a, b) {
  const marginA = getItemProfitMetrics(a).profitMargin;
  const marginB = getItemProfitMetrics(b).profitMargin;
  if (marginA != null && marginB != null && marginA !== marginB) {
    return marginB - marginA;
  }
  if (marginA != null && marginB == null) return -1;
  if (marginA == null && marginB != null) return 1;
  const price = priceOf(b) - priceOf(a);
  if (price !== 0) return price;
  return compareManualOrder(a, b);
}

function compareStarPhase(a, b) {
  const rank = (QUADRANT_RANK.star[a.engineeringQuadrant] ?? 9) -
    (QUADRANT_RANK.star[b.engineeringQuadrant] ?? 9);
  if (rank !== 0) return rank;
  return compareByMarginThenPrice(a, b);
}

function comparePlowhorsePhase(a, b) {
  const rank = (QUADRANT_RANK.plowhorse[a.engineeringQuadrant] ?? 9) -
    (QUADRANT_RANK.plowhorse[b.engineeringQuadrant] ?? 9);
  if (rank !== 0) return rank;
  const comboA = isComboOrFamilyItem(a) ? 0 : 1;
  const comboB = isComboOrFamilyItem(b) ? 0 : 1;
  if (comboA !== comboB) return comboA - comboB;
  const vol = (b.orderCount || 0) - (a.orderCount || 0);
  if (vol !== 0) return vol;
  return compareManualOrder(a, b);
}

function compareBudgetPhase(a, b) {
  const rank = (QUADRANT_RANK.budget[a.engineeringQuadrant] ?? 9) -
    (QUADRANT_RANK.budget[b.engineeringQuadrant] ?? 9);
  if (rank !== 0) return rank;
  const price = priceOf(a) - priceOf(b);
  if (price !== 0) return price;
  return compareManualOrder(a, b);
}

function buildSalesContext(items, orders, restaurantId) {
  const counts = countItemSales(orders, restaurantId, 90);
  const soldQtys = [...counts.values()].filter((qty) => qty > 0);
  const margins = (items || [])
    .map((item) => getItemProfitMetrics(item).profitMargin)
    .filter((value) => value != null && Number.isFinite(value));
  return {
    counts,
    hasSales: soldQtys.length > 0,
    thresholds: {
      popularityMedian: computeMedian(soldQtys),
      profitMarginMedian: computeMedian(margins),
    },
  };
}

function sortCatalogItems(
  items,
  settings = {},
  now = new Date(),
  salesContext = null,
  categoryRanks = null,
) {
  const list = Array.isArray(items) ? [...items] : [];
  if (!isDynamicMenuSortingEnabled(settings)) {
    return list.sort((a, b) => compareManualOrder(a, b, categoryRanks));
  }
  const { phase } = paydayCycleInfo(now, paydayStartDayFromSettings(settings));
  const sales = salesContext || {
    counts: new Map(),
    hasSales: false,
    thresholds: { popularityMedian: 0, profitMarginMedian: 0 },
  };
  const annotated = list.map((item) =>
    annotateCatalogItem(item, { ...sales, phase }),
  );
  if (phase === 'star') return annotated.sort(compareStarPhase);
  if (phase === 'plowhorse') return annotated.sort(comparePlowhorsePhase);
  return annotated.sort(compareBudgetPhase);
}

module.exports = {
  clampPaydayStartDay,
  isDynamicMenuSortingEnabled,
  paydayStartDayFromSettings,
  paydayCycleInfo,
  isComboOrFamilyItem,
  sortCatalogItems,
  compareManualOrder,
  countItemSales,
  buildSalesContext,
  classifyBcgQuadrant,
  annotateCatalogItem,
};
