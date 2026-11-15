'use strict';

const axios = require('axios');
const { validateVendorId } = require('./vendor-credential-store');
const { kuwaitDateKey } = require('../../../lib/kuwaitBusinessDay');
const { diffPlatformOrderIds } = require('../../../lib/platformDayReconcile');
const {
  computePlatformDualTotals,
} = require('../../../lib/platformOrderFinance');

const DEFAULT_BASE_URL = 'https://vendor-portal-api.deliveryhero.io/v1';

function normalizeTalabatApiPayment(value, rawOrder = {}) {
  const method = String(value || '').replace(/\s+/g, ' ').trim();
  const paidOnline =
    rawOrder?.paid === true ||
    rawOrder?.is_paid === true ||
    String(rawOrder?.payment_status || '')
      .trim()
      .toLowerCase() === 'paid_online';

  // Cash is settlement-critical — never remap to Prepaid.
  if (
    /\b(cash(?:\s+on\s+delivery)?|cash\s*payment|collect\s+cash|\bCOD\b)\b/i.test(
      method,
    ) ||
    /كاش(?!ير)|نقدي|الدفع\s*عند\s*الاستلام/i.test(method)
  ) {
    return 'Cash';
  }
  if (/\bK[\s-]?NET\b|كي\s*نت/i.test(method)) return 'KNET';
  if (/\bapple\s*pay\b/i.test(method)) return 'Apple Pay';
  if (
    /\b(online(?:\s*payment)?|pre[-\s]?paid|credit\s*card|debit\s*card|visa|mastercard|mada|card)\b/i.test(
      method,
    ) ||
    /دفع\s*إلكتروني|مدفوع(?:ة)?\s*إلكتروني|مدفوع(?:ة)?\s*مسبق/i.test(method) ||
    (paidOnline && method && !/\bcash|كاش|cod/i.test(method))
  ) {
    return 'Prepaid';
  }
  return method.slice(0, 60);
}

function finiteAmount(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0
    ? Number(parsed.toFixed(3))
    : 0;
}

function platformDeliveryFee(raw) {
  // Zone catalog fees are cashier routing data. They must never become the
  // ingested Talabat/Keeta customer delivery charge.
  if (raw?.delivery_fee != null || raw?.deliveryFee != null) {
    return finiteAmount(raw.delivery_fee ?? raw.deliveryFee);
  }
  return 0;
}

function platformCustomerName(name) {
  const text = String(name || '').replace(/\s+/g, ' ').trim();
  if (!text || /^\*+$/.test(text) || /\*{2,}/.test(text)) return 'عميل منصات';
  if (/^(unknown|customer|n\/a|na|null|undefined|عميل|بدون اسم)$/i.test(text)) {
    return 'عميل منصات';
  }
  return text.slice(0, 200);
}

function normalizeOrder(raw) {
  const externalOrderId = String(raw?.order_id || '').trim();
  if (!externalOrderId) throw new Error('Talabat order is missing order_id');
  const items = Array.isArray(raw?.items)
    ? raw.items.map((item) => ({
        platformItemId: String(item?.item_id || '').trim(),
        sku: String(item?.sku || '').trim(),
        name: String(item?.name || '').trim(),
        quantity: Math.max(1, Math.trunc(Number(item?.quantity) || 1)),
        unitPrice: finiteAmount(item?.unit_price),
        lineTotal: Number(
          (
            finiteAmount(item?.unit_price) *
            Math.max(1, Math.trunc(Number(item?.quantity) || 1))
          ).toFixed(3),
        ),
        options: Array.isArray(item?.options)
          ? item.options.map((option) => ({
              platformItemId: String(option?.option_id || '').trim(),
              sku: String(option?.sku || '').trim(),
              name: String(option?.name || '').trim(),
              price: finiteAmount(option?.price),
              entityType: String(option?.entity_type || 'option'),
            }))
          : [],
      }))
    : [];
  const itemsTotal = items.reduce((sum, item) => sum + item.lineTotal, 0);
  const dual = computePlatformDualTotals({
    itemsTotal,
    deliveryFee: platformDeliveryFee(raw),
    discount: finiteAmount(
      raw?.discount_amount ?? raw?.discountAmount ?? raw?.discount,
    ),
  });
  const reported = finiteAmount(raw?.total_amount);
  const customerPayableTotal =
    dual.deliveryFee > 0 || dual.discountAmount > 0
      ? dual.customerPayableTotal
      : reported || dual.customerPayableTotal;
  return {
    platform: 'talabat',
    externalOrderId,
    invoiceNumber: externalOrderId,
    createdAt: raw?.created_at,
    customerName: platformCustomerName(raw?.customer?.name),
    phone: String(raw?.customer?.phone || '').trim(),
    address: String(raw?.customer?.address || '').trim(),
    deliveryInstructions: String(
      raw?.delivery_instructions || raw?.customer?.instructions || '',
    ).trim(),
    items,
    subtotal: dual.itemsTotal,
    deliveryFee: dual.deliveryFee,
    discountAmount: dual.discountAmount,
    customerPayableTotal,
    netMerchantSales: dual.netMerchantSales,
    priceLocked: true,
    totalAmount: customerPayableTotal,
    paymentMethod: normalizeTalabatApiPayment(raw?.payment_method, raw),
    deliveryType: String(raw?.delivery_type || 'delivery').trim(),
    externalStatus: String(
      raw?.order_status || raw?.status || raw?.state || '',
    ).trim(),
  };
}

function ordersForKuwaitDay(orders, dayKey) {
  const target = dayKey || kuwaitDateKey(new Date());
  return (orders || []).filter((order) => {
    const created = order?.createdAt || order?.created_at;
    if (!created) return true;
    return kuwaitDateKey(created) === target;
  });
}

function shouldFallback(error) {
  // Network/timeouts have no HTTP response. Auth and upstream failures must
  // never pause order intake — DOM monitoring remains the safety net.
  if (!error?.response) return true;
  const status = Number(error.response.status);
  return (
    status === 400 ||
    status === 401 ||
    status === 403 ||
    status === 404 ||
    status === 408 ||
    status === 429 ||
    status >= 500
  );
}

class TalabatIngestionService {
  constructor({
    ingestor,
    credentialStore,
    onFallback = async () => {},
    onStatus = () => {},
    httpClient = axios,
    baseUrl = DEFAULT_BASE_URL,
    intervalMs = 60_000,
    logger = console,
  }) {
    if (!ingestor || !credentialStore) {
      throw new TypeError('ingestor and credentialStore are required');
    }
    if (new URL(baseUrl).origin !== new URL(DEFAULT_BASE_URL).origin) {
      throw new Error('Talabat API base URL origin is not allowlisted');
    }
    this.ingestor = ingestor;
    this.credentialStore = credentialStore;
    this.onFallback = onFallback;
    this.onStatus = onStatus;
    this.httpClient = httpClient;
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this.intervalMs = Math.max(30_000, Number(intervalMs) || 60_000);
    this.logger = logger;
    this.timer = null;
    this.inFlight = null;
    this.reportedMissingCredentials = false;
  }

  notifyStatus(status) {
    try {
      this.onStatus(status);
    } catch (error) {
      this.logger.warn(
        `[Talabat API] status callback failed: ${String(
          error?.message || error,
        )}`,
      );
    }
  }

  async fetchActiveOrders(vendorIdValue, authTokenValue) {
    const vendorId = validateVendorId(vendorIdValue);
    const authToken = String(authTokenValue || '').trim().replace(/^Bearer\s+/i, '');
    if (!authToken) throw new Error('Talabat auth token is required');
    try {
      const response = await this.httpClient.get(
        `${this.baseUrl}/vendors/${encodeURIComponent(vendorId)}/orders`,
        {
          headers: {
            Authorization: `Bearer ${authToken}`,
            Accept: 'application/json',
          },
          timeout: 15_000,
          maxRedirects: 0,
          validateStatus: (status) => status >= 200 && status < 300,
        },
      );
      if (
        response?.data?.status !== 'success' ||
        !Array.isArray(response?.data?.data?.orders)
      ) {
        throw new Error('Talabat API returned an invalid order payload');
      }
      const orders = response.data.data.orders.map(normalizeOrder);
      if (!orders.length) {
        this.notifyStatus({ mode: 'api_connected' });
        return {
          fetched: 0,
          accepted: 0,
          duplicates: 0,
          rejected: 0,
          fallback: false,
        };
      }
      const result = this.ingestor.ingest('talabat', orders, {
        source: 'talabat-rest-api',
      });
      this.notifyStatus({ mode: 'api_connected' });
      return { fetched: orders.length, ...result, fallback: false };
    } catch (error) {
      if (!shouldFallback(error)) throw error;
      const status = Number(error?.response?.status) || null;
      const reason = status ? `http_${status}` : 'network_error';
      this.logger.warn(`[Talabat API] ${reason}; using local DOM fallback`);
      await this.onFallback({ provider: 'talabat', reason });
      this.notifyStatus({ mode: 'dom_fallback', reason });
      return {
        fetched: 0,
        accepted: 0,
        duplicates: 0,
        rejected: 0,
        fallback: true,
        reason,
      };
    }
  }

  pollNow() {
    if (this.inFlight) return this.inFlight;
    this.inFlight = Promise.resolve()
      .then(async () => {
        const credentials = this.credentialStore.get('talabat');
        if (!credentials) {
          if (!this.reportedMissingCredentials) {
            this.logger.info(
              '[Talabat API] polling ready; waiting for encrypted credentials',
            );
            this.reportedMissingCredentials = true;
          }
          this.notifyStatus({ mode: 'credentials_missing' });
          return { skipped: true, reason: 'credentials_not_configured' };
        }
        this.reportedMissingCredentials = false;
        return this.fetchActiveOrders(
          credentials.vendorId,
          credentials.authToken,
        );
      })
      .finally(() => {
        this.inFlight = null;
      });
    return this.inFlight;
  }

  start() {
    if (this.timer) return;
    this.logger.info(
      `[Talabat API] ingestion service started; interval=${this.intervalMs}ms`,
    );
    this.timer = setInterval(() => {
      void this.pollNow().catch((error) => {
        this.logger.error(
          `[Talabat API] poll failed: ${String(error?.message || error)}`,
        );
      });
    }, this.intervalMs);
    this.timer.unref?.();
    void this.pollNow().catch((error) => {
      this.logger.error(
        `[Talabat API] startup poll failed: ${String(error?.message || error)}`,
      );
    });
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
  }
}

const historyDom = require('./talabat-history-dom');

function reconcileTodayOrderIds(liveOrderIds, localOrderIds) {
  const { missing, extra } = diffPlatformOrderIds(liveOrderIds, localOrderIds);
  return { missing, extra };
}

module.exports = {
  normalizeTalabatApiPayment,
  platformDeliveryFee,
  DEFAULT_BASE_URL,
  TalabatIngestionService,
  diffPlatformOrderIds,
  reconcileTodayOrderIds,
  normalizeOrder,
  ordersForKuwaitDay,
  shouldFallback,
  ...historyDom,
};
