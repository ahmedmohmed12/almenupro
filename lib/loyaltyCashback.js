const { findCustomerByPhone, phonesMatch } = require('./customersStore');

const CASHBACK_TYPES = {
  PERCENTAGE: 'PERCENTAGE',
  FIXED_AMOUNT: 'FIXED_AMOUNT',
};

function normalizeCashbackType(raw) {
  const value = String(raw || CASHBACK_TYPES.PERCENTAGE).trim().toUpperCase();
  if (value === 'FIXED' || value === 'FIXED_AMOUNT') {
    return CASHBACK_TYPES.FIXED_AMOUNT;
  }
  return CASHBACK_TYPES.PERCENTAGE;
}

function normalizeLoyaltySettings(raw = {}) {
  return {
    cashbackType: normalizeCashbackType(raw.cashbackType ?? raw.cashback_type),
    cashbackValue:
      Number(raw.cashbackValue ?? raw.cashback_value ?? 0) || 0,
    minOrderForLoyalty:
      Number(raw.minOrderForLoyalty ?? raw.min_order_for_loyalty ?? 0) || 0,
    loyaltyEnabled:
      raw.loyaltyEnabled !== false &&
      raw.loyalty_enabled !== false &&
      (Number(raw.cashbackValue ?? raw.cashback_value ?? 0) || 0) > 0,
  };
}

function getOrderTotal(order) {
  return Number(order.totalPrice ?? order.total_price ?? order.totalAmount ?? order.total_amount) || 0;
}

function roundCashback(value) {
  return Number((Number(value) || 0).toFixed(3));
}

function isDeliveredStatus(status) {
  const value = String(status || '').trim().toLowerCase();
  return value === 'delivered' || value === 'completed' || value === 'done';
}

function orderQualifiesForLoyalty(order, loyaltySettings) {
  const orderTotal = getOrderTotal(order);
  const minOrder = loyaltySettings.minOrderForLoyalty || 0;
  if (minOrder > 0 && orderTotal < minOrder) {
    return { qualifies: false, orderTotal, reason: 'below_min_order' };
  }
  if (!loyaltySettings.loyaltyEnabled && loyaltySettings.cashbackValue <= 0) {
    return { qualifies: false, orderTotal, reason: 'loyalty_disabled' };
  }
  if (isDeliveredStatus(order.status) === false) {
    return { qualifies: false, orderTotal, reason: 'not_delivered' };
  }
  return { qualifies: true, orderTotal, reason: null };
}

/**
 * Calculate earned cashback for an order based on restaurant loyalty settings.
 */
function calculateEarnedCashback(order, settings = {}) {
  const loyalty = normalizeLoyaltySettings(settings);
  const qualification = orderQualifiesForLoyalty(
    { ...order, status: order.status || 'delivered' },
    loyalty,
  );
  const orderTotal = qualification.orderTotal;

  if (!qualification.qualifies) {
    return {
      earnedCashback: 0,
      qualifies: false,
      reason: qualification.reason,
      orderTotal,
      cashbackType: loyalty.cashbackType,
      cashbackValue: loyalty.cashbackValue,
      minOrderForLoyalty: loyalty.minOrderForLoyalty,
    };
  }

  let earnedCashback = 0;
  if (loyalty.cashbackType === CASHBACK_TYPES.FIXED_AMOUNT) {
    earnedCashback = loyalty.cashbackValue;
  } else {
    earnedCashback = (orderTotal * loyalty.cashbackValue) / 100;
  }

  earnedCashback = roundCashback(Math.max(0, earnedCashback));

  return {
    earnedCashback,
    qualifies: earnedCashback > 0,
    reason: earnedCashback > 0 ? null : 'zero_cashback',
    orderTotal,
    cashbackType: loyalty.cashbackType,
    cashbackValue: loyalty.cashbackValue,
    minOrderForLoyalty: loyalty.minOrderForLoyalty,
  };
}

function previewEarnedCashback(orderTotal, settings = {}) {
  return calculateEarnedCashback(
    { totalPrice: orderTotal, status: 'delivered' },
    settings,
  );
}

function creditCustomerWallet(customers, order, restaurantId, amount) {
  const earned = roundCashback(amount);
  if (earned <= 0) return customers;

  const phone = order.phone;
  if (!phone) return customers;

  const next = [...customers];
  const existingIndex = next.findIndex(
    (customer) =>
      String(customer.restaurant_id || customer.restaurantId || '') ===
        String(restaurantId) && phonesMatch(customer.phone, phone),
  );

  const now = new Date().toISOString();
  const walletEntry = {
    orderId: order.id,
    amount: earned,
    createdAt: now,
  };

  if (existingIndex === -1) {
    return customers;
  }

  const existing = next[existingIndex];
  const currentBalance =
    Number(existing.walletBalance ?? existing.wallet_balance ?? 0) || 0;
  const history = Array.isArray(existing.walletHistory)
    ? [...existing.walletHistory]
    : Array.isArray(existing.wallet_history)
      ? [...existing.wallet_history]
      : [];

  history.unshift(walletEntry);

  next[existingIndex] = {
    ...existing,
    walletBalance: roundCashback(currentBalance + earned),
    wallet_balance: roundCashback(currentBalance + earned),
    walletHistory: history.slice(0, 50),
    wallet_history: history.slice(0, 50),
    updatedAt: now,
    updated_at: now,
  };

  return next;
}

function applyLoyaltyCashbackToOrder(order, settings, customers, restaurantId) {
  if (order.loyaltyCashbackApplied === true || order.loyalty_cashback_applied === true) {
    return { order, customers, applied: false, calculation: null };
  }

  if (!isDeliveredStatus(order.status)) {
    return { order, customers, applied: false, calculation: null };
  }

  const calculation = calculateEarnedCashback(order, settings);
  if (!calculation.qualifies || calculation.earnedCashback <= 0) {
    return { order, customers, applied: false, calculation };
  }

  const nextCustomers = creditCustomerWallet(
    customers,
    order,
    restaurantId,
    calculation.earnedCashback,
  );

  const now = new Date().toISOString();
  const nextOrder = {
    ...order,
    earnedCashback: calculation.earnedCashback,
    loyaltyCashbackApplied: true,
    loyalty_cashback_applied: true,
    loyaltyCashbackAppliedAt: now,
    loyalty_cashback_applied_at: now,
  };

  return {
    order: nextOrder,
    customers: nextCustomers,
    applied: true,
    calculation,
  };
}

module.exports = {
  CASHBACK_TYPES,
  normalizeCashbackType,
  normalizeLoyaltySettings,
  getOrderTotal,
  isDeliveredStatus,
  calculateEarnedCashback,
  previewEarnedCashback,
  creditCustomerWallet,
  applyLoyaltyCashbackToOrder,
};
