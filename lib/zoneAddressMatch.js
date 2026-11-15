'use strict';

function zoneText(value) {
  return String(value || '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function matchDeliveryZone(address, zones) {
  const text = zoneText(address);
  if (text.length < 2) return null;
  let best = null;
  let bestScore = 0;
  for (const zone of zones || []) {
    if (zone?.isActive === false || zone?.is_active === false) continue;
    const area = zoneText(zone.areaName || zone.area_name || zone.name);
    const governorate = zoneText(zone.governorate);
    let score = 0;
    if (area.length >= 2 && text.includes(area)) score = area.length + 10;
    else if (governorate.length >= 2 && text.includes(governorate)) score = governorate.length;
    if (score > bestScore) {
      best = zone;
      bestScore = score;
    }
  }
  return best;
}

function frozenOrderFinancials(order) {
  return {
    subtotal: order.subtotal,
    totalPrice: order.totalPrice,
    total_price: order.total_price,
    deliveryFee: order.deliveryFee,
    delivery_fee: order.delivery_fee,
    discountAmount: order.discountAmount,
    discount_amount: order.discount_amount,
    customerPayableTotal: order.customerPayableTotal,
    customer_payable_total: order.customer_payable_total,
    netMerchantSales: order.netMerchantSales,
    net_merchant_sales: order.net_merchant_sales,
    platformCommission: order.platformCommission,
    platform_commission: order.platform_commission,
    priceLocked: order.priceLocked,
    price_locked: order.price_locked,
    items: order.items,
    paymentMethod: order.paymentMethod,
    payment_method: order.payment_method,
  };
}

module.exports = {
  frozenOrderFinancials,
  matchDeliveryZone,
};
