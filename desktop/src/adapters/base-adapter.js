'use strict';

class BaseAdapter {
  constructor({ platform, selectors, document }) {
    if (!platform || !selectors || !document) {
      throw new TypeError('platform, selectors, and document are required');
    }
    this.platform = platform;
    this.selectors = selectors;
    this.document = document;
  }

  text(root, key) {
    const selector = this.selectors[key];
    if (!selector) return '';
    const node = root.querySelector(selector);
    return String(node?.textContent || '').replace(/\s+/g, ' ').trim();
  }

  attribute(root, key, attribute) {
    const selector = this.selectors[key];
    if (!selector) return '';
    const node = root.querySelector(selector);
    return String(node?.getAttribute(attribute) || '').trim();
  }

  amount(value) {
    const normalized = String(value || '')
      .replace(/[^\d.,-]/g, '')
      .replace(/,(?=\d{3}(?:\D|$))/g, '')
      .replace(',', '.');
    const parsed = Number(normalized);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
  }

  quantity(value) {
    const match = String(value || '').match(/\d+/);
    return Math.max(1, Math.min(999, Number(match?.[0] || 1)));
  }

  observationModes() {
    const configured = this.selectors.observationModes;
    if (Array.isArray(configured) && configured.length) {
      return configured.filter(
        (mode) => mode && typeof mode.root === 'string' && typeof mode.order === 'string',
      );
    }
    return [
      {
        id: 'default',
        root: this.selectors.observerRoot,
        order: this.selectors.order,
        maxRows: 100,
      },
    ];
  }

  observationRoots() {
    const roots = [];
    for (const mode of this.observationModes()) {
      const root = mode.root && this.document.querySelector(mode.root);
      if (root && !roots.includes(root)) roots.push(root);
    }
    // Keep observing body as well as a currently rendered order surface. Vendor
    // portals are SPAs and commonly replace the entire table/root after routing.
    if (this.document.body && !roots.includes(this.document.body)) {
      roots.push(this.document.body);
    }
    if (roots.length) return roots;
    const fallback =
      (this.selectors.observerRoot &&
        this.document.querySelector(this.selectors.observerRoot)) ||
      this.document.body ||
      this.document.documentElement;
    return fallback ? [fallback] : [];
  }

  observationRoot() {
    return this.observationRoots()[0] || null;
  }

  hasOrderSurface() {
    return this.orderSurfaceIds().length > 0;
  }

  orderSurfaceIds() {
    return this.observationModes()
      .filter((mode) => mode.root && this.document.querySelector(mode.root))
      .map((mode) => mode.id);
  }

  hasAuthenticatedSurface() {
    const selector = this.selectors.authenticatedRoot;
    return Boolean(selector && this.document.querySelector(selector));
  }

  parseItem(node) {
    const quantity = this.quantity(this.text(node, 'itemQuantity'));
    const priceText = this.text(node, 'itemPrice');
    const unitPrice = this.amount(priceText);
    const options = Array.from(
      node.querySelectorAll(this.selectors.itemOptions),
      (option) => {
        const platformItemId =
          option.getAttribute?.('data-option-id') ||
          option.getAttribute?.('data-item-id') ||
          '';
        const sku = option.getAttribute?.('data-sku') || '';
        return {
          name: String(option.textContent || '').replace(/\s+/g, ' ').trim(),
          price: this.amount(option.textContent),
          ...(platformItemId ? { platformItemId } : {}),
          ...(sku ? { sku } : {}),
        };
      },
    ).filter((option) => option.name);

    const platformItemId =
      node.getAttribute?.('data-product-id') ||
      node.getAttribute?.('data-item-id') ||
      node.getAttribute?.('data-product-variation-id') ||
      '';
    const sku = node.getAttribute?.('data-sku') || '';

    return {
      name: this.text(node, 'itemName'),
      ...(platformItemId ? { platformItemId } : {}),
      ...(sku ? { sku } : {}),
      quantity,
      unitPrice,
      lineTotal: Number((unitPrice * quantity).toFixed(3)),
      options,
    };
  }

  externalOrderId(root) {
    return (
      root.getAttribute('data-order-id') ||
      root.getAttribute('data-order-no') ||
      root.getAttribute('data-id') ||
      this.text(root, 'id').replace(/^#/, '').trim()
    );
  }

  historyRows(limit = 3) {
    const mode = this.observationModes().find((entry) => entry.id === 'history');
    if (!mode) return [];
    const container = mode.root && this.document.querySelector(mode.root);
    if (!container) return [];
    return Array.from(container.querySelectorAll(mode.order)).slice(
      0,
      Math.max(1, Math.min(500, Number(limit) || 3)),
    );
  }

  historyContainer() {
    const mode = this.observationModes().find((entry) => entry.id === 'history');
    return mode?.root ? this.document.querySelector(mode.root) : null;
  }

  detailRoot() {
    const selector = this.selectors.historyDetailRoot;
    if (!selector) return null;
    return (
      Array.from(this.document.querySelectorAll(selector)).find(
        (node) =>
          node.getAttribute('aria-hidden') !== 'true' &&
          (typeof node.getClientRects !== 'function' ||
            node.getClientRects().length > 0),
      ) || null
    );
  }

  detailCloseButton() {
    const selector = this.selectors.historyDetailClose;
    return selector ? this.document.querySelector(selector) : null;
  }

  parseOrder(root, externalOrderIdOverride = '') {
    const externalOrderId =
      externalOrderIdOverride || this.externalOrderId(root);
    const items = Array.from(root.querySelectorAll(this.selectors.item))
      .map((node) => this.parseItem(node))
      .filter((item) => item.name);
    const subtotal = this.amount(this.text(root, 'subtotal'));
    const parsedTotal = this.amount(this.text(root, 'total'));
    const calculatedTotal = items.reduce(
      (sum, item) => sum + Number(item.lineTotal || 0),
      0,
    );
    const createdValue =
      this.attribute(root, 'createdAt', 'datetime') ||
      this.text(root, 'createdAt');
    const createdDate = createdValue ? new Date(createdValue) : null;

    return {
      platform: this.platform,
      externalOrderId,
      invoiceNumber:
        this.text(root, 'invoiceNumber') ||
        externalOrderId.split('|').pop() ||
        externalOrderId,
      customerName: this.text(root, 'customerName'),
      phone: this.text(root, 'phone'),
      address: this.text(root, 'address'),
      items,
      subtotal: subtotal || Number(calculatedTotal.toFixed(3)),
      totalAmount:
        parsedTotal || subtotal || Number(calculatedTotal.toFixed(3)),
      paymentMethod: this.text(root, 'paymentMethod'),
      deliveryType: this.text(root, 'deliveryType'),
      createdAt:
        createdDate && !Number.isNaN(createdDate.getTime())
          ? createdDate.toISOString()
          : new Date().toISOString(),
    };
  }

  scan({ includeHistory = true } = {}) {
    const byId = new Map();
    this.parseMisses = [];
    let foundModeRoot = false;
    const consider = (root, mode) => {
      const order = this.parseOrder(root);
      if (order.externalOrderId && order.items.length) {
        if (!byId.has(order.externalOrderId)) byId.set(order.externalOrderId, order);
        return;
      }
      if (this.parseMisses.length >= 30) return;
      const itemSelector = this.selectors.item || '';
      this.parseMisses.push({
        reason: order.externalOrderId ? 'missing-items' : 'missing-order-id',
        mode: mode?.id || 'default',
        orderSelector: mode?.order || this.selectors.order || '',
        itemSelector,
        externalOrderId: order.externalOrderId || '',
        itemCount: itemSelector ? root.querySelectorAll(itemSelector).length : 0,
      });
    };
    for (const mode of this.observationModes()) {
      if (!includeHistory && mode.id === 'history') continue;
      const container = mode.root && this.document.querySelector(mode.root);
      if (!container) continue;
      foundModeRoot = true;
      const maxRows = Math.max(1, Math.min(100, Number(mode.maxRows) || 100));
      const rows = Array.from(container.querySelectorAll(mode.order)).slice(0, maxRows);
      for (const root of rows) consider(root, mode);
    }

    // Backward compatibility for fixtures and portals not yet mapped to modes.
    if (!foundModeRoot) {
      for (const root of Array.from(
        this.document.querySelectorAll(this.selectors.order),
      ).slice(0, 100)) {
        consider(root, null);
      }
    }
    return [...byId.values()];
  }
}

module.exports = { BaseAdapter };
