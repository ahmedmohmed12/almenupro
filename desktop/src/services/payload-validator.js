'use strict';

const ALLOWED_PROVIDERS = new Set(['talabat', 'jahez', 'keeta']);
const MAX_ITEMS = 200;
const MAX_AMOUNT = 10_000_000;

function cleanText(value, maxLength) {
  return String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, maxLength);
}

function amount(value, field = 'amount') {
  if (value == null || value === '') return 0;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > MAX_AMOUNT) {
    throw new Error(`${field} is outside the allowed range`);
  }
  return Number(parsed.toFixed(3));
}

function validateOrderPayload(raw, expectedProvider) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new TypeError('Scraper payload must be an object');
  }
  const platform =
    cleanText(raw.platform, 30).toLowerCase() === 'keta'
      ? 'keeta'
      : cleanText(raw.platform, 30).toLowerCase();
  if (!ALLOWED_PROVIDERS.has(platform) || platform !== expectedProvider) {
    throw new Error('Scraper provider does not match its view');
  }
  const externalOrderId = cleanText(raw.externalOrderId, 160);
  if (!externalOrderId) throw new Error('External order ID is required');
  if (
    !Array.isArray(raw.items) ||
    raw.items.length === 0 ||
    raw.items.length > MAX_ITEMS
  ) {
    throw new Error(`Order must contain between 1 and ${MAX_ITEMS} items`);
  }

  const items = raw.items.map((item, index) => {
    const name = cleanText(item?.name, 300);
    if (!name) throw new Error(`Item ${index + 1} is missing a name`);
    const quantity = Math.max(
      1,
      Math.min(999, Math.trunc(Number(item.quantity) || 1)),
    );
    return {
      name,
      platformItemId: cleanText(
        item?.platformItemId ||
          item?.platform_item_id ||
          item?.externalItemId,
        190,
      ),
      sku: cleanText(item?.sku, 190),
      quantity,
      unitPrice: amount(item.unitPrice, `Item ${index + 1} unit price`),
      lineTotal: amount(item.lineTotal, `Item ${index + 1} line total`),
      options: Array.isArray(item.options)
        ? item.options.slice(0, 100).map((option) => ({
            name: cleanText(option?.name, 200),
            price: amount(option?.price, `Item ${index + 1} option price`),
          platformItemId: cleanText(
            option?.platformItemId ||
              option?.platform_item_id ||
              option?.externalItemId,
            190,
          ),
          sku: cleanText(option?.sku, 190),
          entityType: cleanText(
            option?.entityType || option?.entity_type || 'option',
            20,
          ),
          })).filter((option) => option.name)
        : [],
    };
  });

  return {
    platform,
    externalOrderId,
    invoiceNumber: cleanText(raw.invoiceNumber, 160) || externalOrderId,
    customerName: cleanText(raw.customerName, 200),
    phone: cleanText(raw.phone, 60),
    address: cleanText(raw.address, 500),
    deliveryInstructions: cleanText(
      raw.deliveryInstructions || raw.delivery_instructions,
      500,
    ),
    items,
    subtotal: amount(raw.subtotal, 'Subtotal'),
    deliveryFee: amount(raw.deliveryFee ?? raw.delivery_fee, 'Delivery fee'),
    discountAmount: amount(
      raw.discountAmount ?? raw.discount_amount,
      'Discount',
    ),
    customerPayableTotal: amount(
      raw.customerPayableTotal ?? raw.customer_payable_total ?? raw.totalAmount,
      'Customer payable total',
    ),
    netMerchantSales: amount(
      raw.netMerchantSales ?? raw.net_merchant_sales ?? raw.subtotal,
      'Net merchant sales',
    ),
    priceLocked: true,
    totalAmount: amount(raw.totalAmount, 'Total amount'),
    paymentMethod: cleanText(raw.paymentMethod, 60),
    storeName: cleanText(raw.storeName || raw.store_name, 120),
    store_name: cleanText(raw.storeName || raw.store_name, 120),
    deliveryType: cleanText(raw.deliveryType, 40),
    createdAt: Number.isNaN(Date.parse(raw.createdAt))
      ? new Date().toISOString()
      : new Date(raw.createdAt).toISOString(),
  };
}

function dedupeKey(restaurantId, order) {
  return `${restaurantId}\u0000${order.platform}\u0000${order.externalOrderId}`;
}

module.exports = {
  ALLOWED_PROVIDERS,
  dedupeKey,
  validateOrderPayload,
};
