'use strict';

const { normalizeKeetaOrderDetail } = require('./keeta-order-response');
const { normalizeOrder } = require('./talabat-ingestion-service');
const {
  computePlatformDualTotals,
} = require('../../../lib/platformOrderFinance');

const BLOCKED_PATH =
  /login|sign-?in|oauth|\/token|session|password|credential|\/auth(?:\/|$)/i;

const ORDER_PATHS = {
  keeta: [/\/api\/order\/getOrderDtl/i],
  talabat: [/\/vendors\/[^/]+\/orders(?:\/|$)/i, /\/orders\/\d{6,}(?:\/|$)/i],
  jahez: [/\/api\/v1\/incoming(?:\/|$)/i, /\/orders\/(?:detail|history|list)(?:\/|$)/i],
};

function requestPath(rawUrl) {
  try {
    const url = new URL(String(rawUrl || ''));
    return url.pathname || '';
  } catch {
    return '';
  }
}

function matchesOrderEndpoint(provider, rawUrl) {
  const path = requestPath(rawUrl);
  if (!path || BLOCKED_PATH.test(path)) return false;
  const patterns = ORDER_PATHS[provider] || [];
  return patterns.some((pattern) => pattern.test(path));
}

function requestHost(rawUrl) {
  try {
    return new URL(String(rawUrl || '')).hostname || '';
  } catch {
    return '';
  }
}

function isTalabatHost(rawUrl) {
  return /talabat|deliveryhero/i.test(requestHost(rawUrl));
}

function talabatTrafficLabel(provider, params) {
  if (provider !== 'talabat') return '';
  const response = params?.response || {};
  const rawUrl = String(response.url || '');
  if (!isTalabatHost(rawUrl)) return '';
  const path = requestPath(rawUrl);
  if (!path || BLOCKED_PATH.test(path)) return '';
  const type = String(params?.type || 'unknown');
  if (/stylesheet|image|font|media|script|ping|prefetch/i.test(type)) return '';
  const status = Number(response.status) || 0;
  const mime = String(response.mimeType || '');
  const reasons = [];
  if (!matchesOrderEndpoint(provider, rawUrl)) reasons.push('path-filter');
  if (!/json/i.test(mime)) reasons.push('mime');
  if (status >= 400) reasons.push(`http-${status}`);
  if (type && !/xhr|fetch/i.test(type)) reasons.push(`type-${type}`);
  return `[Talabat Network] ${status || '-'} ${type} ${reasons.length ? `filtered:${reasons.join(',')}` : 'order-api'} ${path}`;
}

function isOrderApiEvent(provider, params) {
  const response = params?.response || {};
  if (!matchesOrderEndpoint(provider, response.url)) return false;
  if (!/json/i.test(String(response.mimeType || ''))) return false;
  if (Number(response.status) >= 400) return false;
  const type = String(params?.type || '');
  return !type || /xhr|fetch/i.test(type);
}

function finiteAmount(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Number(parsed.toFixed(3)) : 0;
}

function collectRawOrders(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.orders)) return payload.orders;
  if (Array.isArray(payload?.data?.orders)) return payload.data.orders;
  if (payload?.data?.orderInfo) return [payload];
  if (payload && typeof payload === 'object' && (payload.order_id || payload.orderId)) {
    return [payload];
  }
  return [];
}

function tryTalabatOrder(raw) {
  try {
    const order = normalizeOrder(raw);
    return order?.externalOrderId && order.items?.length ? order : null;
  } catch {
    return null;
  }
}

function tryJahezOrder(raw) {
  const externalOrderId = String(raw?.orderId || raw?.order_id || raw?.id || '')
    .replace(/[^\d]/g, '')
    .slice(0, 20);
  const itemsRaw = raw?.items || raw?.orderItems || raw?.products;
  if (externalOrderId.length < 5 || !Array.isArray(itemsRaw) || !itemsRaw.length) {
    return null;
  }
  const items = itemsRaw
    .map((item) => {
      const quantity = Math.max(1, Math.trunc(Number(item?.quantity || item?.count) || 1));
      const unitPrice = finiteAmount(item?.unitPrice ?? item?.unit_price ?? item?.price);
      return {
        name: String(item?.name || item?.itemName || '').trim(),
        quantity,
        unitPrice,
        lineTotal: Number((unitPrice * quantity).toFixed(3)),
      };
    })
    .filter((item) => item.name);
  if (!items.length) return null;
  const itemsTotal = items.reduce((sum, item) => sum + item.lineTotal, 0);
  const dual = computePlatformDualTotals({
    itemsTotal,
    deliveryFee: finiteAmount(
      raw?.deliveryFee ?? raw?.delivery_fee ?? raw?.deliveryCharge,
    ),
    discount: finiteAmount(
      raw?.discountAmount ?? raw?.discount_amount ?? raw?.discount,
    ),
  });
  const reported = finiteAmount(
    raw?.grandTotal ?? raw?.totalAmount ?? raw?.total_amount ?? raw?.total,
  );
  const customer = raw?.customer && typeof raw.customer === 'object' ? raw.customer : {};
  return {
    platform: 'jahez',
    externalOrderId,
    invoiceNumber: externalOrderId,
    customerName: String(customer.name || raw?.customerName || '').trim(),
    phone: String(customer.phone || raw?.phone || '').trim(),
    address: String(
      customer.address || raw?.address || raw?.deliveryAddress || '',
    ).trim(),
    items,
    subtotal: dual.itemsTotal,
    deliveryFee: dual.deliveryFee,
    discountAmount: dual.discountAmount,
    totalAmount: reported || dual.customerPayableTotal,
    customerPayableTotal: reported || dual.customerPayableTotal,
    netMerchantSales: dual.netMerchantSales,
    priceLocked: true,
    paymentMethod: String(raw?.paymentMethod || raw?.payment_method || '').trim(),
    deliveryType: String(raw?.deliveryType || raw?.delivery_type || 'delivery').trim(),
    ...(raw?.createdAt || raw?.created_at
      ? { createdAt: raw.createdAt || raw.created_at }
      : {}),
  };
}

function parseOrderPayloads(provider, payload) {
  if (provider === 'keeta') {
    const order = normalizeKeetaOrderDetail(payload);
    return order ? [order] : [];
  }
  const rows = collectRawOrders(payload);
  if (provider === 'talabat') return rows.map(tryTalabatOrder).filter(Boolean);
  if (provider === 'jahez') return rows.map(tryJahezOrder).filter(Boolean);
  return [];
}

function decodeResponseBody(body) {
  const text = String(body?.body || '');
  if (!text) return '';
  if (!body?.base64Encoded) return text;
  return Buffer.from(text, 'base64').toString('utf8');
}

class PlatformOrderNetworkInterceptor {
  constructor({ webContents, provider, onOrders, onPayload, logger = console }) {
    if (!webContents) throw new TypeError('webContents is required');
    if (!ORDER_PATHS[provider]) throw new TypeError('unsupported provider');
    if (typeof onOrders !== 'function' && typeof onPayload !== 'function') {
      throw new TypeError('onOrders or onPayload is required');
    }
    this.webContents = webContents;
    this.provider = provider;
    this.onOrders = onOrders;
    this.onPayload = onPayload;
    this.logger = logger;
    this.pending = new Map();
    this.attached = false;
    this.onMessage = this.onMessage.bind(this);
    this.onDestroyed = () => this.detach();
  }

  attach() {
    if (this.attached || this.webContents.isDestroyed()) return;
    try {
      if (!this.webContents.debugger.isAttached()) {
        this.webContents.debugger.attach('1.3');
      }
      this.webContents.debugger.on('message', this.onMessage);
      this.webContents.once('destroyed', this.onDestroyed);
      void this.webContents.debugger
        .sendCommand('Network.enable')
        .catch((error) => {
          this.logger.warn(
            `[${this.provider} Network] enable failed: ${String(error?.message || error).slice(0, 200)}`,
          );
        });
      this.attached = true;
    } catch (error) {
      this.logger.warn(
        `[${this.provider} Network] debugger attach failed: ${String(error?.message || error).slice(0, 200)}`,
      );
    }
  }

  detach() {
    this.pending.clear();
    if (!this.attached) return;
    this.attached = false;
    try {
      this.webContents.debugger.removeListener('message', this.onMessage);
    } catch {
      // The debugger may already be gone with the view.
    }
    try {
      if (!this.webContents.isDestroyed()) {
        this.webContents.removeListener('destroyed', this.onDestroyed);
        if (this.webContents.debugger.isAttached()) {
          this.webContents.debugger.detach();
        }
      }
    } catch (error) {
      this.logger.warn(
        `[${this.provider} Network] debugger detach failed: ${String(error?.message || error).slice(0, 200)}`,
      );
    }
  }

  onMessage(_event, method, params) {
    try {
      if (method === 'Network.responseReceived') {
        const traffic = talabatTrafficLabel(this.provider, params);
        if (traffic) this.logger.info(traffic);
      }
      if (method === 'Network.responseReceived' && isOrderApiEvent(this.provider, params)) {
        this.pending.set(params.requestId, String(params?.response?.url || ''));
        if (this.pending.size > 40) {
          const oldest = this.pending.keys().next().value;
          this.pending.delete(oldest);
        }
        return;
      }
      if (method === 'Network.loadingFailed') {
        this.pending.delete(params?.requestId);
        return;
      }
      if (method !== 'Network.loadingFinished' || !this.pending.has(params?.requestId)) {
        return;
      }
      const requestId = params.requestId;
      const sourceUrl = this.pending.get(requestId);
      this.pending.delete(requestId);
      void this.readBody(requestId, sourceUrl);
    } catch (error) {
      this.logger.warn(
        `[${this.provider} Network] event failed: ${String(error?.message || error).slice(0, 200)}`,
      );
    }
  }

  async readBody(requestId, sourceUrl = '') {
    if (this.webContents.isDestroyed() || !this.webContents.debugger.isAttached()) return;
    try {
      const body = await this.webContents.debugger.sendCommand(
        'Network.getResponseBody',
        { requestId },
      );
      const text = decodeResponseBody(body);
      if (!text || text.length > 2_000_000) return;
      const payload = JSON.parse(text);
      if (typeof this.onPayload === 'function') {
        await this.onPayload(payload, { url: sourceUrl });
        return;
      }
      const orders = parseOrderPayloads(this.provider, payload);
      if (!orders.length) return;
      await this.onOrders(orders);
    } catch (error) {
      this.logger.warn(
        `[${this.provider} Network] order body skipped: ${String(error?.message || error).slice(0, 200)}`,
      );
    }
  }
}

module.exports = {
  PlatformOrderNetworkInterceptor,
  isOrderApiEvent,
  matchesOrderEndpoint,
  parseOrderPayloads,
};
