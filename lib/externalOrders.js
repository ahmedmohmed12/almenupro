'use strict';

const crypto = require('crypto');
const { computePlatformDualTotals } = require('./platformOrderFinance');

const SUPPORTED_PLATFORMS = new Set(['talabat', 'jahez', 'keeta']);
const MAX_ITEMS = 200;
const MAX_AMOUNT = 10_000_000;

function cleanText(value, maxLength = 300) {
  return String(value ?? '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLength);
}

function finiteAmount(value, fallback = 0) {
  const parsed =
    typeof value === 'string'
      ? Number(value.replace(/[^\d.,-]/g, '').replace(/,/g, ''))
      : Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > MAX_AMOUNT) {
    return fallback;
  }
  return Number(parsed.toFixed(3));
}

function normalizePlatform(value) {
  const platform = cleanText(value, 30).toLowerCase();
  // Keep the existing AlMenuPro sales-platform identifier.
  return platform === 'keta' ? 'keeta' : platform;
}

function normalizeIngestionSource(value) {
  return String(value || '').trim().toUpperCase() === 'API'
    ? 'API'
    : 'DOM_SCRAPER';
}

function normalizeExternalOutcome(value) {
  const raw = cleanText(value, 120).toLowerCase();
  if (
    /cancel|refund|reject|void|ملغ|مرفوض|مسترد/.test(raw)
  ) {
    return 'cancelled';
  }
  if (/in[_\s-]*progress|preparing|ongoing|قيد|جاري/.test(raw)) {
    return 'in_progress';
  }
  if (
    /accept|confirm|complete|deliver|success|received|تم القبول|مكتمل|تم التوصيل/.test(
      raw,
    )
  ) {
    return 'successful';
  }
  return raw === 'cancelled' || raw === 'successful' ? raw : 'successful';
}

function findExistingExternalOrderIds(orders, {
  restaurantId,
  platform,
  externalOrderIds,
}) {
  const normalizedPlatform = normalizePlatform(platform);
  const requested = new Set(
    (Array.isArray(externalOrderIds) ? externalOrderIds : [])
      .map((value) => cleanText(value, 160))
      .filter(Boolean),
  );
  if (!SUPPORTED_PLATFORMS.has(normalizedPlatform) || requested.size === 0) {
    return [];
  }
  const existing = new Set();
  for (const order of Array.isArray(orders) ? orders : []) {
    const orderRestaurant = String(
      order?.restaurantId || order?.restaurant_id || '',
    );
    const orderPlatform = normalizePlatform(
      order?.orderSource || order?.order_source || order?.platform,
    );
    const orderExternalId = cleanText(
      order?.externalOrderId || order?.external_order_id,
      160,
    );
    if (
      orderRestaurant === String(restaurantId) &&
      orderPlatform === normalizedPlatform &&
      requested.has(orderExternalId)
    ) {
      existing.add(orderExternalId);
    }
  }
  return [...existing];
}

function normalizeOptions(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.slice(0, 100).map((option) => {
    if (typeof option === 'string') {
      return { group: '', name: cleanText(option), price: 0 };
    }
    return {
      group: cleanText(option?.group || option?.category, 100),
      name: cleanText(option?.name || option?.title || option?.label, 200),
      price: finiteAmount(option?.price || option?.amount),
      platformItemId: cleanText(
        option?.platformItemId ||
          option?.platform_item_id ||
          option?.externalItemId,
        190,
      ),
      sku: cleanText(option?.sku, 190),
      posOptionId: cleanText(
        option?.posOptionId || option?.pos_option_id,
        120,
      ),
      isUnmapped: Boolean(option?.isUnmapped ?? option?.is_unmapped),
      mappingMethod: cleanText(
        option?.mappingMethod || option?.mapping_method,
        40,
      ),
    };
  }).filter((option) => option.name);
}

function normalizeItem(item, index) {
  const name = cleanText(item?.name || item?.title, 300);
  if (!name) {
    const error = new Error(`External order item ${index + 1} is missing a name`);
    error.statusCode = 400;
    error.code = 'INVALID_EXTERNAL_ORDER_ITEM';
    throw error;
  }
  const quantity = Math.min(999, Math.max(1, Math.trunc(Number(item?.quantity ?? item?.qty ?? 1) || 1)));
  const selectedOptions = normalizeOptions(
    item?.selectedOptions || item?.options || item?.addOns || item?.addons,
  );
  let unitPrice = finiteAmount(item?.unitPrice ?? item?.unit_price ?? item?.price);
  const lineTotal = finiteAmount(item?.lineTotal ?? item?.line_total ?? item?.totalPrice);
  if (!unitPrice && lineTotal) unitPrice = Number((lineTotal / quantity).toFixed(3));
  return {
    menuItemId: cleanText(item?.menuItemId || item?.menu_item_id || item?.id, 120),
    platformItemId: cleanText(
      item?.platformItemId ||
        item?.platform_item_id ||
        item?.externalItemId ||
        item?.external_item_id,
      190,
    ),
    sku: cleanText(item?.sku, 190),
    name,
    unitPrice,
    price: unitPrice,
    quantity,
    selectedOptions,
    isUnmapped: Boolean(item?.isUnmapped ?? item?.is_unmapped),
    is_unmapped: Boolean(item?.isUnmapped ?? item?.is_unmapped),
    mappingMethod: cleanText(
      item?.mappingMethod || item?.mapping_method,
      40,
    ),
    ...(cleanText(item?.notes || item?.specialNotes, 500)
      ? { specialNotes: cleanText(item?.notes || item?.specialNotes, 500) }
      : {}),
    lineTotal: Number((unitPrice * quantity).toFixed(3)),
  };
}

function externalOrderId(platform, restaurantId, providerOrderId) {
  const digest = crypto
    .createHash('sha256')
    .update(`${platform}\0${restaurantId}\0${providerOrderId}`)
    .digest('hex')
    .slice(0, 24);
  return `ext_${platform}_${digest}`;
}

function normalizeExternalOrder(body, restaurantId) {
  const platform = normalizePlatform(body?.platform || body?.orderSource || body?.source);
  if (!SUPPORTED_PLATFORMS.has(platform)) {
    const error = new Error('Unsupported external ordering platform');
    error.statusCode = 400;
    error.code = 'UNSUPPORTED_EXTERNAL_PLATFORM';
    throw error;
  }
  const providerOrderId = cleanText(
    body?.externalOrderId || body?.external_order_id || body?.orderId || body?.order_id,
    160,
  );
  if (!providerOrderId) {
    const error = new Error('externalOrderId is required');
    error.statusCode = 400;
    error.code = 'EXTERNAL_ORDER_ID_REQUIRED';
    throw error;
  }
  if (!Array.isArray(body?.items) || body.items.length === 0 || body.items.length > MAX_ITEMS) {
    const error = new Error(`External order must contain between 1 and ${MAX_ITEMS} items`);
    error.statusCode = 400;
    error.code = 'INVALID_EXTERNAL_ORDER_ITEMS';
    throw error;
  }

  const items = body.items.map(normalizeItem);
  const calculatedTotal = items.reduce((sum, item) => sum + item.lineTotal, 0);
  const deliveryFee = finiteAmount(
    body.deliveryFee ?? body.delivery_fee ?? body.platformDeliveryFee,
  );
  const discountAmount = finiteAmount(
    body.discountAmount ?? body.discount_amount ?? body.discount,
  );
  const dual = computePlatformDualTotals({
    itemsTotal: finiteAmount(body.subtotal, Number(calculatedTotal.toFixed(3))),
    deliveryFee,
    discount: discountAmount,
  });
  const reportedTotal = finiteAmount(
    body.customerPayableTotal ??
      body.customer_payable_total ??
      body.totalAmount ??
      body.totalPrice ??
      body.total_price ??
      body.total,
    dual.customerPayableTotal,
  );
  const totalPrice =
    deliveryFee > 0 || discountAmount > 0
      ? dual.customerPayableTotal
      : reportedTotal || dual.customerPayableTotal;
  const deliveryType = cleanText(body.deliveryType || body.orderType, 40)
    .toLowerCase()
    .replace(/[\s_-]/g, '');
  const orderType =
    deliveryType === 'pickup' || deliveryType === 'takeaway' ? 'pickup' : 'delivery';
  const createdAt = new Date(body.createdAt || Date.now());
  const safeCreatedAt = Number.isNaN(createdAt.getTime())
    ? new Date().toISOString()
    : createdAt.toISOString();

  return {
    id: externalOrderId(platform, restaurantId, providerOrderId),
    restaurantId,
    restaurant_id: restaurantId,
    externalOrderId: providerOrderId,
    external_order_id: providerOrderId,
    invoiceNumber:
      cleanText(body.invoiceNumber || body.invoice_number, 160) ||
      providerOrderId,
    orderSource: platform,
    order_source: platform,
    ...(cleanText(body.storeName || body.store_name, 120)
      ? {
          storeName: cleanText(body.storeName || body.store_name, 120),
          store_name: cleanText(body.storeName || body.store_name, 120),
        }
      : {}),
    customerName: cleanText(body.customerName || body.customer?.name, 200),
    phone: cleanText(body.phone || body.customer?.phone, 60),
    address: cleanText(body.address || body.customer?.address, 500),
    deliveryInstructions: cleanText(
      body.deliveryInstructions ||
        body.delivery_instructions ||
        body.customer?.instructions,
      500,
    ),
    delivery_instructions: cleanText(
      body.deliveryInstructions ||
        body.delivery_instructions ||
        body.customer?.instructions,
      500,
    ),
    items,
    subtotal: dual.itemsTotal,
    deliveryFee: dual.deliveryFee,
    delivery_fee: dual.deliveryFee,
    discountAmount: dual.discountAmount,
    discount_amount: dual.discountAmount,
    customerPayableTotal: totalPrice,
    customer_payable_total: totalPrice,
    netMerchantSales: dual.netMerchantSales,
    net_merchant_sales: dual.netMerchantSales,
    priceLocked: true,
    price_locked: true,
    totalPrice,
    total_price: totalPrice,
    orderType,
    order_type: orderType,
    paymentMethod: cleanText(body.paymentMethod || body.payment_method, 60),
    status: 'pending',
    createdFromPos: false,
    created_from_pos: false,
    createdAt: safeCreatedAt,
    created_at: safeCreatedAt,
    externalPayloadVersion: 1,
    ingestionSource: normalizeIngestionSource(
      body.ingestionSource || body.ingestion_source,
    ),
    ingestion_source: normalizeIngestionSource(
      body.ingestionSource || body.ingestion_source,
    ),
    externalStatus: normalizeExternalOutcome(
      body.externalStatus || body.providerStatus || body.status,
    ),
    external_status: normalizeExternalOutcome(
      body.externalStatus || body.providerStatus || body.status,
    ),
  };
}

module.exports = {
  MAX_AMOUNT,
  MAX_ITEMS,
  SUPPORTED_PLATFORMS,
  findExistingExternalOrderIds,
  normalizeExternalOrder,
  normalizeExternalOutcome,
  normalizeIngestionSource,
  normalizePlatform,
};
