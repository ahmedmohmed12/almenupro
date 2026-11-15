'use strict';

const { BaseAdapter } = require('./base-adapter');
const selectors = require('../selectors/keeta.json');
const {
  collectKeetaHistoryRows,
  extractKeetaCreatedAt,
  focusKeetaDateRangeOnToday,
  keetaHistoryScrollRoot,
  extractKeetaCustomerDetails,
  extractKeetaOrderIdColumn,
  extractKeetaOrderIds,
  mapKeetaDomOrderToPos,
} = require('./keeta-dom-adapter');

class KetaAdapter extends BaseAdapter {
  constructor(document) {
    super({ platform: 'keeta', selectors, document });
  }

  historyContainer() {
    return (
      keetaHistoryScrollRoot(this.document) ||
      super.historyContainer()
    );
  }

  async prepareHistoryScan({ wait }) {
    const narrowed = focusKeetaDateRangeOnToday(this.document);
    if (typeof wait === 'function' && narrowed) await wait(600);
  }

  historyRows(limit = 500) {
    const cap = Math.max(1, Math.min(500, Number(limit) || 500));
    const discovered = collectKeetaHistoryRows(this.document, cap);
    if (discovered.length) return discovered;
    return super.historyRows(cap);
  }

  readLiveOrderRows(limit = 500) {
    try {
      return this.historyRows(limit);
    } catch (error) {
      console.warn(
        `[keeta] history selector failed: ${String(error?.message || error).slice(0, 200)}`,
      );
      return [];
    }
  }

  providerCreatedAt(root) {
    return extractKeetaCreatedAt(root) || null;
  }

  externalOrderId(root) {
    const column = extractKeetaOrderIdColumn(root);
    const fromDom = (column || extractKeetaOrderIds(root)).externalOrderId;
    if (fromDom) return fromDom;
    const values = [root?.textContent, super.externalOrderId(root)];
    for (const value of values) {
      const normalized = String(value || '').replace(
        /[\u200b-\u200d\u2060]/g,
        '',
      );
      const match = normalized.match(/\d{10,}/);
      if (match) return match[0];
    }
    return super.externalOrderId(root);
  }

  parseOrder(root, externalOrderIdOverride = '') {
    const fromDom = mapKeetaDomOrderToPos(root, externalOrderIdOverride);
    const details = extractKeetaCustomerDetails(root);
    let order;
    try {
      order = super.parseOrder(
        root,
        externalOrderIdOverride || fromDom.externalOrderId,
      );
    } catch {
      order = {
        platform: 'keeta',
        externalOrderId: fromDom.externalOrderId,
        invoiceNumber: fromDom.invoiceNumber,
        customerName: '',
        phone: '',
        address: '',
        items: [],
        subtotal: 0,
        totalAmount: 0,
        paymentMethod: '',
        deliveryType: '',
        createdAt: new Date().toISOString(),
      };
    }

    const externalOrderId =
      externalOrderIdOverride ||
      fromDom.externalOrderId ||
      order.externalOrderId ||
      details.externalOrderId;

    return {
      ...order,
      platform: 'keeta',
      externalOrderId,
      invoiceNumber:
        fromDom.invoiceNumber ||
        order.invoiceNumber ||
        details.invoiceNumber ||
        externalOrderId,
      shortOrderId: details.shortOrderId || order.shortOrderId || '',
      customerName: order.customerName || fromDom.customerName || '',
      phone: order.phone || fromDom.phone || '',
      address: order.address || fromDom.address || '',
      deliveryInstructions:
        order.deliveryInstructions || fromDom.deliveryInstructions || '',
      deliveryType:
        order.deliveryType || fromDom.deliveryType || details.deliveryType || '',
      externalStatus: fromDom.externalStatus || order.externalStatus || '',
      ...(fromDom.createdAt ? { createdAt: fromDom.createdAt } : {}),
    };
  }
}

module.exports = {
  KetaAdapter,
  // Alias requested by product docs / callers.
  KeetaDomAdapter: KetaAdapter,
};
