'use strict';

const { getAdapter } = require('../adapters/platforms');

const PLATFORM_NAMES = {
  keeta: 'Keeta',
  talabat: 'Talabat',
  jahez: 'Jahez',
};

// IPC `status` stays NEW, UPDATED, or CANCELLED so the POS can alert on first
// sight and refresh when a later ACCEPTED, PREPARING, or CONFIRMED payload fills in.

function roundMoney(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return 0;
  return Number(parsed.toFixed(3));
}

function identifyPlatform(payload, hint = '') {
  const hinted = String(hint || '').trim().toLowerCase();
  if (PLATFORM_NAMES[hinted]) return hinted;
  if (payload?.data?.orderInfo) return 'keeta';
  if (payload?.order_id || payload?.orders?.[0]?.order_id) return 'talabat';
  if (payload?.orderId || payload?.orderItems) return 'jahez';
  return '';
}

function textOf(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function isCancelledStatus(value) {
  return /cancel|refund|reject|void|ملغ|مرفوض|مسترد/i.test(textOf(value));
}

function isWeakName(value) {
  return /^(عميل منصات|عميل|customer|unknown|n\/a|بدون اسم|\*+|)$/i.test(textOf(value));
}

function phoneDigits(value) {
  return textOf(value).replace(/\D/g, '');
}

/**
 * History and archive APIs repeat old invoices. Live detail and vendor order
 * feeds stay eligible, including ACCEPTED / PREPARING / CONFIRMED updates.
 */
function isArchiveEndpoint(rawUrl) {
  let path = String(rawUrl || '');
  if (!path) return false;
  try {
    path = new URL(path).pathname;
  } catch {
    path = path.split('?')[0];
  }
  return /\/history(?:\/|$)|\/past-orders(?:\/|$)/i.test(path);
}

function normalizeLifecycle(value) {
  const text = textOf(value);
  if (!text) return '';
  if (isCancelledStatus(text)) return 'CANCELLED';
  if (/prepar|cook|in[\s_-]*progress|تحضير/i.test(text)) return 'PREPARING';
  if (/accept|مقبول/i.test(text)) return 'ACCEPTED';
  if (/confirm|مؤكد/i.test(text)) return 'CONFIRMED';
  return '';
}

function fullAddress(order) {
  return {
    street: textOf(order?.address),
    building: textOf(order?.building),
    floor: textOf(order?.floor),
    notes: textOf(order?.deliveryInstructions),
  };
}

function mapItems(items) {
  return (Array.isArray(items) ? items : [])
    .map((item) => ({
      item_name: textOf(item?.name),
      quantity: Math.max(1, Math.trunc(Number(item?.quantity) || 1)),
      price: roundMoney(item?.unitPrice ?? item?.price),
      options: (Array.isArray(item?.options) ? item.options : [])
        .map((option) => ({
          item_name: textOf(option?.name),
          price: roundMoney(option?.price),
        }))
        .filter((option) => option.item_name),
    }))
    .filter((item) => item.item_name);
}

function lineItemsSubtotal(items) {
  return roundMoney(
    (Array.isArray(items) ? items : []).reduce(
      (sum, item) => sum + roundMoney(item?.price) * (Number(item?.quantity) || 0),
      0,
    ),
  );
}

function buildTotals(order, items) {
  const fromItems = lineItemsSubtotal(items);
  const subtotal = roundMoney(order?.subtotal == null ? fromItems : order.subtotal);
  const delivery_fee = roundMoney(order?.deliveryFee);
  const discount = roundMoney(order?.discountAmount);
  const computed = roundMoney(subtotal - discount + delivery_fee);
  const grand_total = roundMoney(
    order?.totalAmount == null ? computed : order.totalAmount,
  );
  return { subtotal, delivery_fee, discount, grand_total };
}

/**
 * Early Talabat (and similar) payloads sometimes send a subtotal that is not
 * the sum of the lines. Replace only that subtotal from `price * quantity`.
 * Delivery fee, discount, and the platform grand total stay as reported.
 */
function reconcileTotals(totals, items) {
  const fromItems = lineItemsSubtotal(items);
  if (fromItems <= 0) return totals;
  if (Math.abs(fromItems - totals.subtotal) <= 0.001) return totals;
  return { ...totals, subtotal: fromItems };
}

function totalsMatch(totals) {
  const expected = roundMoney(
    totals.subtotal - totals.discount + totals.delivery_fee,
  );
  return Math.abs(expected - totals.grand_total) <= 0.001;
}

function orderFingerprint(order) {
  return JSON.stringify({
    items: order.items,
    totals: order.totals,
    full_address: order.full_address,
    customer_name: order.customer_name,
    customer_phone: order.customer_phone,
    platform_status: order.platform_status || '',
    payment_method: order.payment_method || '',
  });
}

function preferName(previous, incoming) {
  if (!isWeakName(incoming)) return textOf(incoming);
  if (!isWeakName(previous)) return textOf(previous);
  return textOf(incoming || previous);
}

function preferPhone(previous, incoming) {
  const nextDigits = phoneDigits(incoming);
  const prevDigits = phoneDigits(previous);
  if (nextDigits.length >= 8) return textOf(incoming);
  if (prevDigits.length >= 8) return textOf(previous);
  return textOf(incoming || previous);
}

function mergeAddress(previous, incoming) {
  const prev = previous || {};
  const next = incoming || {};
  const pick = (key) => textOf(next[key]) || textOf(prev[key]);
  return {
    street: pick('street'),
    building: pick('building'),
    floor: pick('floor'),
    notes: pick('notes'),
  };
}

/**
 * Same `order_id` is one POS record. A later ACCEPTED / PREPARING / CONFIRMED
 * payload fills blank address or totals; a thinner follow-up must not erase
 * a verified address, phone, or payment method already stored.
 */
function mergeRecord(previous, incoming) {
  if (!previous) {
    return {
      ...incoming,
      full_address: { ...incoming.full_address },
      items: incoming.items || [],
      totals: incoming.totals,
    };
  }
  const incomingHasItems = Array.isArray(incoming.items) && incoming.items.length > 0;
  const incomingTotalsOk = incomingHasItems && totalsMatch(incoming.totals);
  return {
    ...previous,
    customer_name: preferName(previous.customer_name, incoming.customer_name),
    customer_phone: preferPhone(previous.customer_phone, incoming.customer_phone),
    full_address: mergeAddress(previous.full_address, incoming.full_address),
    items: incomingHasItems ? incoming.items : previous.items,
    totals: incomingTotalsOk ? incoming.totals : previous.totals,
    payment_method: textOf(incoming.payment_method) || previous.payment_method,
    platform_status: incoming.platform_status || previous.platform_status || '',
    status: incoming.status,
  };
}

function applyStatus(order, records) {
  const key = `${order.platform_name}:${order.order_id}`;
  const previous = records.get(key);
  const merged = mergeRecord(previous?.order, order);
  const cancelled =
    isCancelledStatus(order.status) ||
    order.platform_status === 'CANCELLED' ||
    merged.platform_status === 'CANCELLED';
  if (cancelled) {
    merged.status = 'CANCELLED';
    merged.platform_status = 'CANCELLED';
  } else if (!previous) {
    merged.status = 'NEW';
  } else {
    merged.status = 'UPDATED';
  }
  const fingerprint = `${cancelled ? 'CANCELLED:' : ''}${orderFingerprint(merged)}`;
  const duplicate = previous?.fingerprint === fingerprint;
  records.set(key, { fingerprint, order: merged });
  return { ok: true, order: merged, duplicate };
}

function toSchema(platform, internal) {
  const items = mapItems(internal.items);
  const totals = reconcileTotals(buildTotals(internal, items), items);
  const lifecycle = normalizeLifecycle(internal.externalStatus);
  return {
    order_id: textOf(internal.externalOrderId),
    platform_name: PLATFORM_NAMES[platform] || platform,
    customer_name: textOf(internal.customerName),
    customer_phone: textOf(internal.phone),
    full_address: fullAddress(internal),
    items,
    totals,
    status: textOf(internal.externalStatus),
    platform_status: lifecycle,
    payment_method: textOf(internal.paymentMethod),
  };
}

function walkOrders(payload, visit) {
  const seen = new Set();
  const walk = (value, depth) => {
    if (!value || typeof value !== 'object' || depth > 4 || seen.has(value)) return;
    seen.add(value);
    if (Array.isArray(value)) {
      value.slice(0, 20).forEach((entry) => walk(entry, depth + 1));
      return;
    }
    visit(value);
    if (value.data) walk(value.data, depth + 1);
    if (value.orderInfo) walk(value.orderInfo, depth + 1);
  };
  walk(payload, 0);
}

function cancelledWithoutItems(platform, payload) {
  let found = null;
  walkOrders(payload, (value) => {
    if (found) return;
    const status = textOf(
      value.status || value.orderStatus || value.statusDesc || value.order_status,
    );
    const orderId = textOf(
      value.orderViewIdStr || value.order_id || value.orderId || value.externalOrderId,
    );
    if (!orderId || !isCancelledStatus(status)) return;
    found = toSchema(platform, {
      externalOrderId: orderId,
      externalStatus: 'cancelled',
      items: [],
      subtotal: 0,
      deliveryFee: 0,
      discountAmount: 0,
      totalAmount: 0,
    });
  });
  return found;
}

function statusSignal(payload) {
  let found = null;
  walkOrders(payload, (value) => {
    if (found) return;
    const status = textOf(
      value.status || value.orderStatus || value.statusDesc || value.order_status,
    );
    const orderId = textOf(
      value.orderViewIdStr || value.order_id || value.orderId || value.externalOrderId,
    );
    const lifecycle = normalizeLifecycle(status);
    if (!orderId || !lifecycle) return;
    found = { orderId, status, lifecycle };
  });
  return found;
}

function indexRows(payload) {
  const rows = [];
  if (Array.isArray(payload?.orders)) rows.push(...payload.orders);
  if (payload && !Array.isArray(payload) && (payload.order_id || payload.orderId)) {
    rows.push(payload);
  }
  return rows;
}

function reportedTotals(platform, payload) {
  const totals = new Map();
  if (platform === 'keeta') return totals;
  for (const row of indexRows(payload)) {
    const id = textOf(row.order_id || row.orderId);
    const reported = row.total_amount ?? row.totalAmount ?? row.grandTotal ?? row.grand_total;
    if (id && reported != null) totals.set(id, reported);
  }
  return totals;
}

function reportedSubtotals(platform, payload) {
  const totals = new Map();
  if (platform === 'keeta') return totals;
  for (const row of indexRows(payload)) {
    const id = textOf(row.order_id || row.orderId);
    const reported = row.subtotal ?? row.sub_total ?? row.items_total ?? row.itemsTotal;
    if (id && reported != null) totals.set(id, reported);
  }
  return totals;
}

function expectedGrandTotal(totals) {
  return roundMoney(
    (totals?.subtotal || 0) - (totals?.discount || 0) + (totals?.delivery_fee || 0),
  );
}

function rawOrderRow(payload, orderId) {
  return (
    indexRows(payload).find((row) => textOf(row.order_id || row.orderId) === orderId) ||
    payload
  );
}

function finishOrder(order, provider, parsed, records, payload) {
  if (!order.order_id) return { ok: false, reason: 'missing_order_id', platform: provider };
  const cancelled = isCancelledStatus(order.status) || order.platform_status === 'CANCELLED';
  const key = `${order.platform_name}:${order.order_id}`;
  const known = records.get(key);
  if (!cancelled && !order.items.length && !known) {
    return { ok: false, reason: 'missing_items', order };
  }
  if (!cancelled && order.items.length && !totalsMatch(order.totals)) {
    return {
      ok: false,
      reason: 'totals_mismatch',
      order,
      calculated: expectedGrandTotal(order.totals),
      expected: order.totals.grand_total,
      payload: rawOrderRow(payload, order.order_id),
    };
  }
  if (!cancelled && !order.items.length && known) {
    order.items = known.order.items;
    order.totals = known.order.totals;
  }
  const internal = parsed.find((entry) => textOf(entry.externalOrderId) === order.order_id) || null;
  return { ...applyStatus(order, records), platform: provider, ingest: internal };
}

function parseIncomingOrders(payload, { platform = '', records = new Map(), sourceUrl = '' } = {}) {
  if (isArchiveEndpoint(sourceUrl)) return [{ ok: false, reason: 'archive_endpoint' }];
  const provider = identifyPlatform(payload, platform);
  if (!provider) return [{ ok: false, reason: 'unknown_platform' }];
  const parsed = getAdapter(provider).parsePayload(payload);
  const reported = reportedTotals(provider, payload);
  const rawSubtotals = reportedSubtotals(provider, payload);
  const schemas = parsed.length
    ? parsed.map((order) => {
        const schema = toSchema(provider, order);
        const reportedTotal = reported.get(schema.order_id);
        if (reportedTotal != null) schema.totals.grand_total = roundMoney(reportedTotal);
        const reportedSubtotal = rawSubtotals.get(schema.order_id);
        if (reportedSubtotal != null) schema.totals.subtotal = roundMoney(reportedSubtotal);
        schema.totals = reconcileTotals(schema.totals, schema.items);
        return schema;
      })
    : [cancelledWithoutItems(provider, payload)].filter(Boolean);
  if (!schemas.length) {
    const signal = statusSignal(payload);
    if (!signal) return [{ ok: false, reason: 'unparsed', platform: provider }];
    const draft = toSchema(provider, {
      externalOrderId: signal.orderId,
      externalStatus: signal.status,
      items: [],
      subtotal: 0,
      deliveryFee: 0,
      discountAmount: 0,
      totalAmount: 0,
    });
    draft.platform_status = signal.lifecycle;
    return [finishOrder(draft, provider, [], records, payload)];
  }
  return schemas.map((order) => finishOrder(order, provider, parsed, records, payload));
}

function fromDomOrder(raw) {
  const platform = String(raw?.platform || '').trim().toLowerCase() === 'keta'
    ? 'keeta'
    : String(raw?.platform || '').trim().toLowerCase();
  const items = mapItems(raw?.items);
  const totals = reconcileTotals(
    buildTotals(
      {
        subtotal: raw?.subtotal,
        deliveryFee: raw?.deliveryFee,
        discountAmount: raw?.discountAmount,
        totalAmount: raw?.totalAmount,
      },
      items,
    ),
    items,
  );
  if (!totalsMatch(totals) && items.length) {
    totals.grand_total = roundMoney(
      totals.subtotal - totals.discount + totals.delivery_fee,
    );
  }
  const orderId = textOf(raw?.externalOrderId).split('|').pop().trim();
  return {
    order_id: orderId,
    platform_name: PLATFORM_NAMES[platform] || platform,
    customer_name: textOf(raw?.customerName),
    customer_phone: textOf(raw?.phone),
    full_address: fullAddress(raw),
    items,
    totals,
    status: 'NEW',
    platform_status: normalizeLifecycle(raw?.externalStatus),
    payment_method: textOf(raw?.paymentMethod),
    source: 'DOM 👁️',
  };
}

function createOrderDispatcher({ send, onIngest, logger = console } = {}) {
  if (typeof send !== 'function') throw new TypeError('send is required');
  const records = new Map();
  return {
    seed(order) {
      if (!order?.order_id || !order?.platform_name) return;
      const key = `${order.platform_name}:${order.order_id}`;
      if (records.has(key)) return;
      records.set(key, { fingerprint: orderFingerprint(order), order });
    },
    accept(payload, platform, meta = {}) {
      const sourceUrl = meta?.url || meta?.sourceUrl || '';
      const results = parseIncomingOrders(payload, { platform, records, sourceUrl });
      for (const result of results) {
        if (!result.ok) {
          if (result.reason === 'totals_mismatch') {
            const totals = result.order?.totals || {};
            logger.warn(
              `[Order Parser] totals mismatch order=${result.order?.order_id || ''} calculated=${result.calculated} expected=${result.expected} subtotal=${totals.subtotal} discount=${totals.discount} delivery_fee=${totals.delivery_fee} grand_total=${totals.grand_total} payload=${JSON.stringify(result.payload).slice(0, 12000)}`,
            );
          } else if (result.reason === 'unparsed') {
            const path = sourceUrl ? sourceUrl.split('?')[0] : '';
            logger.warn(
              `[Order Parser] ${platform || 'unknown'} skipped: unparsed${path ? ` path=${path}` : ''} payload=${JSON.stringify(payload).slice(0, 12000)}`,
            );
          } else {
            const path = sourceUrl ? sourceUrl.split('?')[0] : '';
            logger.warn(
              `[Order Parser] ${platform || 'unknown'} skipped: ${result.reason}${path ? ` path=${path}` : ''}`,
            );
          }
          continue;
        }
        if (result.duplicate) continue;
        send(result.order);
        if (
          result.order.status !== 'CANCELLED' &&
          result.ingest &&
          typeof onIngest === 'function'
        ) {
          onIngest(result.ingest, result.order);
        }
      }
      return results;
    },
  };
}

module.exports = {
  createOrderDispatcher,
  fromDomOrder,
  identifyPlatform,
  isArchiveEndpoint,
  parseIncomingOrders,
  reconcileTotals,
  totalsMatch,
};
