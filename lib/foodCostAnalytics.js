/**
 * Food cost & profit margin helpers for Smart Seller (البياع الشاطر).
 * profitMargin = ((sellingPrice - costPrice) / sellingPrice) * 100
 * foodCostPercent = (costPrice / sellingPrice) * 100
 */

function parseCostPrice(item) {
  const raw = item?.costPrice ?? item?.cost_price;
  if (raw == null || raw === '') return null;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : null;
}

function parseSellingPrice(item) {
  const value = Number(item?.price);
  return Number.isFinite(value) && value > 0 ? value : null;
}

function computeProfitMarginPercent(sellingPrice, costPrice) {
  if (sellingPrice == null || sellingPrice <= 0 || costPrice == null) return null;
  return ((sellingPrice - costPrice) / sellingPrice) * 100;
}

function computeFoodCostPercent(sellingPrice, costPrice) {
  if (sellingPrice == null || sellingPrice <= 0 || costPrice == null) return null;
  return (costPrice / sellingPrice) * 100;
}

function getItemProfitMetrics(item) {
  const sellingPrice = parseSellingPrice(item);
  const costPrice = parseCostPrice(item);
  if (sellingPrice == null || costPrice == null) {
    return {
      sellingPrice,
      costPrice: null,
      profitMargin: null,
      foodCostPercent: null,
    };
  }
  return {
    sellingPrice,
    costPrice,
    profitMargin: computeProfitMarginPercent(sellingPrice, costPrice),
    foodCostPercent: computeFoodCostPercent(sellingPrice, costPrice),
  };
}

function passesFoodCostFilter(item, options = {}) {
  const maxFoodCostPercent =
    Number(options.maxFoodCostPercent ?? options.maxFoodCostPercentForUpsell ?? 40) || 40;
  const allowHighFoodCost =
    options.allowHighFoodCostUpsell === true || options.allow_high_food_cost_upsell === true;

  if (allowHighFoodCost) return true;

  const { foodCostPercent } = getItemProfitMetrics(item);
  if (foodCostPercent == null) return true;
  return foodCostPercent <= maxFoodCostPercent;
}

/** Bonus points added to recommendation score when profit prioritization is enabled. */
function profitScoreBonus(item) {
  const { profitMargin } = getItemProfitMetrics(item);
  if (profitMargin == null) return 0;
  return Math.max(0, Math.min(100, profitMargin)) * 0.35;
}

function compareByProfitThenScore(a, b, itemById, prioritizeHighProfit) {
  if (!prioritizeHighProfit) {
    return b.score - a.score;
  }

  const metricsA = getItemProfitMetrics(itemById.get(a.menuItemId));
  const metricsB = getItemProfitMetrics(itemById.get(b.menuItemId));
  const marginA = metricsA.profitMargin;
  const marginB = metricsB.profitMargin;

  if (marginA != null && marginB != null && marginA !== marginB) {
    return marginB - marginA;
  }
  if (marginA != null && marginB == null) return -1;
  if (marginA == null && marginB != null) return 1;

  const foodA = metricsA.foodCostPercent;
  const foodB = metricsB.foodCostPercent;
  if (foodA != null && foodB != null && foodA !== foodB) {
    return foodA - foodB;
  }

  return b.score - a.score;
}

function enrichRecommendationEntry(menuItemId, score, reason, itemById) {
  const item = itemById.get(menuItemId);
  const metrics = item ? getItemProfitMetrics(item) : {};
  return {
    menuItemId,
    score,
    reason,
    ...(metrics.profitMargin != null ? { profitMargin: metrics.profitMargin } : {}),
    ...(metrics.foodCostPercent != null ? { foodCostPercent: metrics.foodCostPercent } : {}),
  };
}

module.exports = {
  parseCostPrice,
  parseSellingPrice,
  computeProfitMarginPercent,
  computeFoodCostPercent,
  getItemProfitMetrics,
  passesFoodCostFilter,
  profitScoreBonus,
  compareByProfitThenScore,
  enrichRecommendationEntry,
};
