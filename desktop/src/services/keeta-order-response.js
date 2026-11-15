'use strict';

function money(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0
    ? Number((parsed / 1000).toFixed(3))
    : 0;
}

function isPrivacyMaskedContact(value) {
  const text = String(value || '').trim();
  if (!text) return true;
  if (/^\*+$/.test(text)) return true;
  if (/\*{2,}/.test(text)) return true;
  if (/^0{1,3}\*+\d{0,4}$/.test(text.replace(/\s+/g, ''))) return true;
  return false;
}

function findContactValue(root, keys) {
  const wanted = new Set(keys.map((key) => key.toLowerCase()));
  const matches = [];
  const visit = (value, path = '', depth = 0) => {
    if (depth > 10 || value == null || typeof value !== 'object') return;
    for (const [key, child] of Object.entries(value)) {
      const childPath = path ? `${path}.${key}` : key;
      if (
        wanted.has(key.toLowerCase()) &&
        ['string', 'number'].includes(typeof child) &&
        String(child).trim()
      ) {
        const text = String(child).trim();
        let score = 0;
        if (/recipient|receiver|customer|consumer|user|delivery/i.test(childPath)) {
          score += 10;
        }
        if (/courier|rider|merchant|shop|vendor|device/i.test(childPath)) {
          score -= 20;
        }
        // Prefer real PII over Keeta privacy placeholders like *** / 00****97.
        if (isPrivacyMaskedContact(text)) score -= 50;
        if (/privacy/i.test(childPath)) score -= 15;
        matches.push({ value: text, score });
      }
      if (child && typeof child === 'object') {
        visit(child, childPath, depth + 1);
      }
    }
  };
  visit(root);
  const ranked = matches.sort((a, b) => b.score - a.score);
  const preferred = ranked.find((entry) => !isPrivacyMaskedContact(entry.value));
  return preferred?.value || ranked[0]?.value || '';
}

function providerCreatedAt(...values) {
  for (const value of values) {
    if (value == null || value === '') continue;
    const numeric = Number(value);
    let date;
    if (Number.isFinite(numeric) && numeric > 0) {
      const milliseconds =
        numeric >= 1e15 ? numeric / 1000 : numeric < 1e11 ? numeric * 1000 : numeric;
      date = new Date(milliseconds);
    } else {
      date = new Date(String(value));
    }
    if (!Number.isNaN(date.getTime())) return date.toISOString();
  }
  return null;
}

function normalizeKeetaOrderDetail(payload) {
  const orderInfo = payload?.data?.orderInfo;
  const base = orderInfo?.baseOrder || {};
  const merchant = orderInfo?.merchantOrder || {};
  const externalOrderId = String(
    base.orderViewIdStr || base.orderViewId || merchant.orderViewId || '',
  ).trim();
  const products = Array.isArray(orderInfo?.products)
    ? orderInfo.products
    : [];
  if (!externalOrderId || !products.length) return null;

  const items = products
    .map((product) => {
      const quantity = Math.max(1, Math.trunc(Number(product?.count) || 1));
      const unitPrice = money(
        product?.priceWithGroup?.unitPrice ??
          product?.priceWithoutGroup?.unitPrice ??
          product?.price,
      );
      const reportedTotal = money(
        product?.priceWithGroup?.amount ??
          product?.priceWithoutGroup?.amount,
      );
      return {
        name: String(
          product?.nameI18n?.en ||
            product?.nameI18n?.default ||
            product?.name ||
            '',
        ).trim(),
        platformItemId: String(
          product?.skuId ||
            product?.productId ||
            product?.spuId ||
            product?.id ||
            '',
        ).trim(),
        sku: String(product?.skuCode || product?.sku || '').trim(),
        quantity,
        unitPrice,
        lineTotal:
          reportedTotal || Number((unitPrice * quantity).toFixed(3)),
        options: [],
      };
    })
    .filter((item) => item.name);
  if (!items.length) return null;

  const totalAmount = Number(
    items.reduce((sum, item) => sum + item.lineTotal, 0).toFixed(3),
  );
  const createdAt = providerCreatedAt(
    base.ctime,
    base.createTime,
    base.createdAt,
    base.orderCreateTime,
    merchant.ctime,
    merchant.createTime,
    merchant.createdAt,
  );
  const customerName = findContactValue(orderInfo, [
    'customerName',
    'recipientName',
    'receiverName',
    'consumerName',
    'userName',
    'contactName',
  ]);
  const phone = findContactValue(orderInfo, [
    'customerPhone',
    'recipientPhone',
    'receiverPhone',
    'consumerPhone',
    'userPhone',
    'contactPhone',
    'privacyPhone',
    'mobile',
  ]);
  const address = findContactValue(orderInfo, [
    'customerAddress',
    'recipientAddress',
    'receiverAddress',
    'deliveryAddress',
    'addressDetail',
    'fullAddress',
    'address',
  ]);
  const rawStatus = String(
    base.statusDesc ||
      base.orderStatusDesc ||
      base.status ||
      base.orderStatus ||
      merchant.statusDesc ||
      merchant.status ||
      '',
  ).trim();
  const externalStatus = /cancel|refund|reject|void|ملغ|مرفوض|مسترد/i.test(
    rawStatus,
  )
    ? 'cancelled'
    : 'successful';
  const shortOrderId = String(
    base.orderSeqNo ||
      base.seqNo ||
      base.daySeq ||
      merchant.orderSeqNo ||
      merchant.seqNo ||
      '',
  ).trim();
  const deliveryTypeRaw = findContactValue(orderInfo, [
    'deliveryTypeDesc',
    'deliveryType',
    'fulfillmentType',
    'fulfillTypeDesc',
  ]);
  const deliveryType = /keeta\s*delivery/i.test(deliveryTypeRaw)
    ? 'Keeta delivery'
    : Array.isArray(orderInfo?.merchantOrderDeliveries) &&
        orderInfo.merchantOrderDeliveries.length
      ? deliveryTypeRaw || 'delivery'
      : deliveryTypeRaw || 'pickup';

  return {
    platform: 'keeta',
    externalOrderId,
    invoiceNumber: shortOrderId ? `#${shortOrderId}` : externalOrderId,
    shortOrderId,
    customerName,
    phone,
    address,
    externalStatus,
    items,
    subtotal: totalAmount,
    totalAmount,
    paymentMethod: String(base.payTypeDesc || base.payType || '').trim(),
    deliveryType,
    ...(createdAt ? { createdAt } : {}),
  };
}

module.exports = {
  findContactValue,
  normalizeKeetaOrderDetail,
  providerCreatedAt,
};
