'use strict';

const { orderDateKey } = require('../../../lib/kuwaitBusinessDay');

/**
 * Keeta merchant portal DOM helpers for the order-detail drawer:
 *   #9251  5464144081829251
 *   Keeta delivery
 *   Q7D513704043 / +965 … / Customer address: …
 */

function normalizedText(nodeOrText) {
  const raw =
    nodeOrText && typeof nodeOrText === 'object' && 'textContent' in nodeOrText
      ? nodeOrText.textContent
      : nodeOrText;
  return String(raw || '')
    .replace(/[\u200b-\u200d\u2060]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function leafTexts(root) {
  if (!root?.querySelectorAll) {
    const single = normalizedText(root);
    return single ? [single] : [];
  }
  return Array.from(root.querySelectorAll('*'))
    .filter((node) => node.children.length === 0)
    .map(normalizedText)
    .filter(Boolean);
}

function extractKeetaOrderIdColumn(root) {
  const column = root?.querySelector?.(
    "[data-testid='order-no'], [data-testid='order-view-id'], [data-column='order-id'], [data-field='order-id'], [class*='orderid' i], [class*='order-id' i]",
  );
  if (!column) return null;
  const ids = extractKeetaOrderIds(column);
  return ids.externalOrderId || ids.shortOrderId ? ids : null;
}

function extractKeetaPortalOrderId(value) {
  const text = String(value || '');
  return (
    text.match(/\b(54\d{13,14})\b/)?.[1] ||
    text.match(/\b(\d{15,16})\b/)?.[1] ||
    ''
  );
}

function keetaTodayStamp(value, now = new Date()) {
  const text = normalizedText(value);
  if (/\b(today|اليوم)\b/i.test(text)) return orderDateKey(now);
  if (/\b(yesterday|أمس)\b/i.test(text)) {
    return orderDateKey(new Date(now.getTime() - 24 * 60 * 60 * 1000));
  }
  const dmy = text.match(/\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b/);
  if (!dmy) return '';
  return `${dmy[3]}-${String(dmy[2]).padStart(2, '0')}-${String(dmy[1]).padStart(2, '0')}`;
}

function keetaTodayLabel(now = new Date()) {
  const [year, month, day] = orderDateKey(now).split('-');
  return `${day}-${month}-${year}`;
}

function keetaRangeIsMultiDay(document) {
  const values = Array.from(document?.querySelectorAll?.('input') || [])
    .map((input) => String(input.value || '').trim())
    .filter((value) => /^\d{2}-\d{2}-\d{4}$/.test(value));
  return values.length >= 2 && values[0] !== values[1];
}

function focusKeetaDateRangeOnToday(document, now = new Date()) {
  const today = keetaTodayLabel(now);
  const inputs = Array.from(document?.querySelectorAll?.('input') || []).filter((input) =>
    /\d{2}-\d{2}-\d{4}/.test(String(input.value || '')),
  );
  if (inputs.length < 2) return false;
  const values = inputs.slice(0, 2).map((input) => String(input.value || ''));
  if (values[0] === today && values[1] === today) return false;
  for (const input of inputs.slice(0, 2)) {
    input.value = today;
    input.dispatchEvent?.(new Event('input', { bubbles: true }));
    input.dispatchEvent?.(new Event('change', { bubbles: true }));
  }
  return true;
}

function flexibleOrderId(value) {
  const text = String(value || '');
  const fromAttribute = text.match(
    /(?:data-order-id|data-order-no|data-id)=["']?#?(\d{6,20})/i,
  );
  if (fromAttribute) return fromAttribute[1];
  const longId = text.match(/\b(\d{14,20})\b/);
  if (longId) return longId[1];
  const hashed = text.match(/#\s*(\d{6,15})\b/);
  if (hashed) return hashed[1];
  const plain = text.match(/(?:^|\s)#?(\d{6,15})(?:\s|$)/);
  return plain ? plain[1] : '';
}

function extractKeetaOrderIds(root) {
  const blob = normalizedText(root);
  const leaves = leafTexts(root);
  const attributes = [
    root?.getAttribute?.('data-order-id'),
    root?.getAttribute?.('data-order-no'),
    root?.getAttribute?.('data-id'),
  ].filter(Boolean);
  const shortFromLeaf = leaves
    .map((value) => value.match(/^#\s*(\d{3,6})$/)?.[1])
    .find(Boolean);
  const shortFromBlob = blob.match(/#\s*(\d{3,6})\b/)?.[1] || '';
  const shortOrderId = shortFromLeaf || shortFromBlob || '';

  let externalOrderId = '';
  for (const value of [...attributes, ...leaves, blob]) {
    const portalId = extractKeetaPortalOrderId(value);
    if (portalId) {
      externalOrderId = portalId;
      break;
    }
  }
  if (!externalOrderId) {
    for (const value of [...attributes, ...leaves, blob]) {
      const match = flexibleOrderId(value);
      if (match && match.length >= 14) {
        externalOrderId = match;
        break;
      }
    }
  }
  if (!externalOrderId || externalOrderId.length < 10) {
    const fallback = flexibleOrderId(blob);
    externalOrderId = fallback && fallback.length >= 10 ? fallback : '';
  }

  return {
    shortOrderId,
    externalOrderId,
    invoiceNumber: shortOrderId ? `#${shortOrderId}` : externalOrderId,
  };
}

function extractKeetaPhone(root) {
  const blob = [normalizedText(root), ...leafTexts(root)].join('\n');
  const match = blob.match(
    /\+965[\s-]?\d{7,8}|\+\d{1,3}[\s-]?\d{7,12}|\b965[\s-]?\d{7,8}\b/,
  );
  return match ? match[0].replace(/\s+/g, ' ').trim() : '';
}

function extractKeetaAddress(root) {
  const blob = normalizedText(root);
  const labeled = blob.match(
    /Customer\s*address\s*:\s*(.+?)(?=\s+(?:Courier|Item details|Order placed|Upload meal|Finding courier)|$)/i,
  );
  if (labeled?.[1]) {
    return labeled[1].replace(/\s+/g, ' ').trim().replace(/[|,;.\s]+$/g, '');
  }
  for (const value of leafTexts(root)) {
    if (/^Customer\s*address\s*:/i.test(value)) {
      return value.replace(/^Customer\s*address\s*:\s*/i, '').trim();
    }
  }
  // Address often sits on the leaf after the "Customer address:" label.
  const leaves = leafTexts(root);
  const labelIndex = leaves.findIndex((value) =>
    /^Customer\s*address\s*:?\s*$/i.test(value),
  );
  if (labelIndex >= 0 && leaves[labelIndex + 1]) {
    return leaves[labelIndex + 1];
  }
  return '';
}

function extractKeetaCustomerName(root, { phone = '', address = '' } = {}) {
  const leaves = leafTexts(root);
  const blocked = new Set(
    [
      phone,
      address,
      'Customer address:',
      'Customer address',
      'Courier',
      'Item details',
      'Keeta delivery',
      'Upload meal-ready proof',
    ]
      .map((value) => normalizedText(value).toLowerCase())
      .filter(Boolean),
  );

  for (const value of leaves) {
    const text = normalizedText(value);
    if (!text || blocked.has(text.toLowerCase())) continue;
    if (/^#\s*\d{3,6}$/.test(text)) continue;
    if (/^\d{10,}$/.test(text)) continue;
    if (/keeta\s*delivery|order\s+(placed|accepted|to be)/i.test(text)) continue;
    if (/\+?\d[\d\s-]{6,}/.test(text) && !/[A-Za-z\u0600-\u06FF]/.test(text)) {
      continue;
    }
    // Privacy customer codes (Q7D513704043) or real names.
    if (/^[A-Z]\d[A-Z0-9]{5,}$/i.test(text) || /[\u0600-\u06FFa-zA-Z]{2,}/.test(text)) {
      if (text.length <= 80) return text;
    }
  }

  const blob = normalizedText(root);
  const code = blob.match(/\b([A-Z]\d[A-Z0-9]{5,})\b/i);
  return code?.[1] || '';
}

function extractKeetaDeliveryType(root) {
  const blob = normalizedText(root);
  if (/keeta\s*delivery/i.test(blob)) return 'Keeta delivery';
  if (/self\s*delivery|merchant\s*delivery|restaurant\s*delivery/i.test(blob)) {
    return 'Merchant delivery';
  }
  if (/pickup|takeaway|collection/i.test(blob)) return 'Pickup';
  return '';
}

function extractKeetaCustomerDetails(root) {
  const phone = extractKeetaPhone(root);
  const address = extractKeetaAddress(root);
  const customerName = extractKeetaCustomerName(root, { phone, address });
  const deliveryType = extractKeetaDeliveryType(root);
  const ids = extractKeetaOrderIds(root);
  return {
    ...ids,
    customerName,
    phone,
    address,
    deliveryType,
  };
}

function extractKeetaDeliveryInstructions(root) {
  const blob = normalizedText(root);
  const labeled = blob.match(
    /(?:delivery instructions|ملاحظات التوصيل|تعليمات التوصيل)\s*:?\s*(.+?)(?=\s+(?:Item details|Courier|Order placed)|$)/i,
  );
  return labeled?.[1]?.replace(/\s+/g, ' ').trim() || '';
}

function extractKeetaOrderStatus(root) {
  const text = normalizedText(root);
  if (/cancel|refund|reject|void|ملغ|مرفوض|مسترد/i.test(text)) return 'cancelled';
  if (/in\s*progress|preparing|ongoing|قيد|جاري/i.test(text)) return 'in_progress';
  if (/completed|complete|delivered|مكتمل|تم التوصيل/i.test(text)) return 'completed';
  return '';
}

function extractKeetaCreatedAt(root) {
  const text = normalizedText(root);
  const time = text.match(/\b(\d{1,2}):(\d{2})(?:\s*(AM|PM|ص|م))?\b/i);
  let hour = Number(time?.[1] || 12);
  const meridiem = String(time?.[3] || '').toUpperCase();
  if ((meridiem === 'PM' || meridiem === 'م') && hour < 12) hour += 12;
  if ((meridiem === 'AM' || meridiem === 'ص') && hour === 12) hour = 0;
  let year;
  let month;
  let day;
  const dmy = text.match(/\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b/);
  const ymd = text.match(/\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b/);
  const named = text.match(
    /\b(\d{1,2})\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(\d{4})\b/i,
  );
  if (dmy) {
    [, day, month, year] = dmy;
  } else if (ymd) {
    [, year, month, day] = ymd;
  } else if (named) {
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    day = named[1];
    month = String(months.indexOf(named[2].slice(0, 3).toLowerCase()) + 1);
    year = named[3];
  } else if (/\b(today|اليوم|yesterday|أمس)\b/i.test(text)) {
    const key = keetaTodayStamp(text);
    if (!key) return '';
    [year, month, day] = key.split('-');
  } else {
    return '';
  }
  const iso = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T${String(hour).padStart(2, '0')}:${time?.[2] || '00'}:00+03:00`;
  const parsed = new Date(iso);
  return Number.isNaN(parsed.getTime()) ? '' : parsed.toISOString();
}

function keetaHistoryScrollRoot(document) {
  return (
    document?.querySelector?.(
      "[class*='virtualScroller' i], [class*='virtual-list' i], [role='grid'], table",
    ) ||
    document?.scrollingElement ||
    document?.documentElement ||
    null
  );
}

function describeKeetaHistoryDom(document) {
  const rows = collectKeetaHistoryRows(document, 500);
  const ids = [];
  for (const row of rows) {
    const id = extractKeetaOrderIds(row).externalOrderId;
    if (id && !ids.includes(id)) ids.push(id);
  }
  const href = String(document?.location?.href || '');
  const text = normalizedText(document?.body).slice(0, 1600);
  return {
    href,
    path: String(document?.location?.pathname || ''),
    title: String(document?.title || ''),
    historyPage: /order_history|الطلبات السابقة|order history/i.test(`${href} ${text}`),
    loginWall: /login|sign-?in|تسجيل الدخول/i.test(`${href} ${text}`) && ids.length === 0,
    rowCount: rows.length,
    ids,
    scrollRoot: Boolean(keetaHistoryScrollRoot(document)),
  };
}

function dumpKeetaHistoryContainer(document) {
  const root =
    keetaHistoryScrollRoot(document) ||
    document?.querySelector?.("table, [role='grid'], [class*='order' i]") ||
    null;
  return {
    url: String(document?.location?.href || ''),
    title: String(document?.title || ''),
    visibility: String(document?.visibilityState || ''),
    found: Boolean(root),
    tag: String(root?.tagName || ''),
    text: normalizedText(root).slice(0, 2500),
    html: String(root?.innerHTML || '').replace(/\s+/g, ' ').trim().slice(0, 2500),
  };
}

function collectKeetaHistoryRows(document, cap = 500, now = new Date()) {
  const today = orderDateKey(now);
  const multiDay = keetaRangeIsMultiDay(document);
  const nodes = Array.from(
    document?.querySelectorAll?.(
      "tbody tr, [role='row'], [data-order-id], [data-order-no]",
    ) || [],
  );
  const ranked = nodes
    .filter((node) => {
      const text = normalizedText(node);
      return text.length > 0 && text.length <= 4000 && Boolean(extractKeetaPortalOrderId(text) || /\b\d{14,20}\b/.test(text));
    })
    .sort((left, right) => normalizedText(left).length - normalizedText(right).length);
  const seen = new Set();
  const rows = [];
  for (const node of ranked) {
    const text = normalizedText(node);
    const ids = extractKeetaOrderIds(node);
    const key = ids.externalOrderId;
    if (!key || seen.has(key)) continue;
    const stamp = keetaTodayStamp(text, now);
    if (stamp && stamp !== today) continue;
    if (!stamp && multiDay) continue;
    seen.add(key);
    rows.push(node);
    if (rows.length >= cap) break;
  }
  return rows;
}

function mapKeetaDomOrderToPos(root, externalOrderIdOverride = '') {
  const details = extractKeetaCustomerDetails(root);
  const externalOrderId =
    String(externalOrderIdOverride || '').trim() || details.externalOrderId;
  const createdAt = extractKeetaCreatedAt(root);
  return {
    platform: 'keeta',
    externalOrderId,
    invoiceNumber: details.invoiceNumber || externalOrderId,
    shortOrderId: details.shortOrderId,
    customerName: details.customerName || 'عميل منصات',
    phone: details.phone,
    address: details.address,
    deliveryInstructions: extractKeetaDeliveryInstructions(root),
    deliveryType: details.deliveryType,
    externalStatus: extractKeetaOrderStatus(root),
    ...(createdAt ? { createdAt } : {}),
    priceLocked: true,
  };
}

module.exports = {
  extractKeetaAddress,
  extractKeetaCustomerDetails,
  extractKeetaCustomerName,
  extractKeetaDeliveryInstructions,
  extractKeetaDeliveryType,
  collectKeetaHistoryRows,
  describeKeetaHistoryDom,
  extractKeetaPortalOrderId,
  focusKeetaDateRangeOnToday,
  keetaTodayStamp,
  dumpKeetaHistoryContainer,
  flexibleOrderId,
  extractKeetaCreatedAt,
  keetaHistoryScrollRoot,
  extractKeetaOrderIdColumn,
  extractKeetaOrderIds,
  extractKeetaOrderStatus,
  extractKeetaPhone,
  mapKeetaDomOrderToPos,
  normalizedText,
};
