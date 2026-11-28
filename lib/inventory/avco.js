'use strict';

const { roundQty, roundMoneyKwd } = require('./constants');

/**
 * Weighted average cost (AVCO). When stock is zero or negative, new price becomes average.
 */
function computeAvco({ currentQty, currentAvgCost, purchasedQty, purchaseUnitCost }) {
  const qty = roundQty(currentQty);
  const avg = roundMoneyKwd(currentAvgCost);
  const addQty = roundQty(purchasedQty);
  const price = roundMoneyKwd(purchaseUnitCost);

  if (addQty <= 0) {
    return avg;
  }
  if (qty <= 0) {
    return price;
  }
  const totalValue = qty * avg + addQty * price;
  const newQty = qty + addQty;
  return roundMoneyKwd(totalValue / newQty);
}

module.exports = {
  computeAvco,
};