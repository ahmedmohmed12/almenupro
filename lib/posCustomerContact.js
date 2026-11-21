'use strict';

function normalizeOrderType(orderLike = {}) {
  return String(orderLike.orderType || orderLike.order_type || '').toLowerCase();
}

function normalizeOrderSource(orderLike = {}) {
  return String(orderLike.orderSource || orderLike.order_source || '').toLowerCase();
}

function isDineInOrder(orderLike = {}) {
  const type = normalizeOrderType(orderLike);
  if (type.includes('dine')) return true;
  return Boolean(
    String(orderLike.tableId || orderLike.table_id || orderLike.tableNumber || orderLike.table_number || '').trim(),
  );
}

function isPickupOrder(orderLike = {}) {
  const type = normalizeOrderType(orderLike);
  if (type.includes('pickup') || type === 'takeaway' || type === 'walkin' || type === 'walk_in') {
    return true;
  }
  const source = normalizeOrderSource(orderLike);
  if (!source.includes('pos')) return false;
  if (type.includes('delivery') || type.includes('scheduled')) return false;
  const address = String(orderLike.address || '').trim();
  return address.includes('استلام');
}

/**
 * POS pickup + dine-in never require customer name/phone at API layer.
 */
function isWalkInPosCustomerOptional(orderLike = {}) {
  if (isDineInOrder(orderLike) || isPickupOrder(orderLike)) return true;
  const source = normalizeOrderSource(orderLike);
  if (source.includes('pos-dine-in')) return true;
  if (source.includes('pos') && isPickupOrder(orderLike)) return true;
  const address = String(orderLike.address || '').trim();
  if (source.includes('pos') && address.includes('استلام')) return true;
  return false;
}

function sanitizePhoneDigits(phone) {
  return String(phone || '').replace(/\D/g, '');
}

function normalizePosOrderCustomerContact(orderLike = {}, defaults = {}) {
  const payload = { ...(orderLike || {}) };
  const optional = isWalkInPosCustomerOptional(payload);
  const rawPhone = String(payload.phone || '').trim();
  const rawName = String(payload.customerName || payload.customer_name || '').trim();
  const tableLabel =
    defaults.tableName ||
    (payload.tableNumber || payload.table_number
      ? `طاولة ${payload.tableNumber || payload.table_number}`
      : 'طاولة');
  const pickupName = defaults.pickupName || 'استلام من المحل';

  if (optional) {
    const digits = sanitizePhoneDigits(rawPhone);
    return {
      ...payload,
      customerName: rawName || (isDineInOrder(payload) ? tableLabel : pickupName),
      customer_name: rawName || (isDineInOrder(payload) ? tableLabel : pickupName),
      phone: digits.length >= 8 ? rawPhone : '00000000',
    };
  }

  return {
    ...payload,
    customerName: rawName,
    customer_name: rawName,
    phone: rawPhone,
  };
}

module.exports = {
  isWalkInPosCustomerOptional,
  isDineInOrder,
  isPickupOrder,
  normalizePosOrderCustomerContact,
};