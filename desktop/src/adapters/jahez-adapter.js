'use strict';

const { BaseAdapter } = require('./base-adapter');
const selectors = require('../selectors/jahez.json');

class JahezAdapter extends BaseAdapter {
  constructor(document) {
    super({ platform: 'jahez', selectors, document });
  }

  historyContainer() {
    const row = this.historyRows(1)[0];
    let node = row?.parentElement || null;
    let best = super.historyContainer();
    let bestRoom = 0;
    while (node) {
      const room = Number(node.scrollHeight) - Number(node.clientHeight);
      if (room > bestRoom + 40 && Number(node.clientHeight) > 80) {
        best = node;
        bestRoom = room;
      }
      node = node.parentElement || null;
    }
    return best;
  }

  historyRows(limit = 500) {
    const cap = Math.max(1, Math.min(500, Number(limit) || 500));
    const primary = super.historyRows(cap);
    if (primary.length) return primary;
    return Array.from(
      this.document?.querySelectorAll?.(
        "tbody tr, [role='row'], [class*='order-row' i]",
      ) || [],
    )
      .filter((row) => /\b\d{5,}\b/.test(String(row.textContent || '')))
      .slice(0, cap);
  }

  externalOrderId(root) {
    const attribute =
      root?.getAttribute?.('data-order-id') ||
      root?.getAttribute?.('data-order-no') ||
      root?.getAttribute?.('data-id') ||
      '';
    const fromAttribute = String(attribute).match(/\d{6,20}/)?.[0] || '';
    if (fromAttribute) return fromAttribute;
    const text = String(root?.textContent || '').replace(/\s+/g, ' ').trim();
    return text.match(/\b\d{9,16}\b/)?.[0] || super.externalOrderId(root);
  }

  readLiveOrderRows(limit = 500) {
    try {
      return this.historyRows(limit);
    } catch (error) {
      console.warn(
        `[jahez] history selector failed: ${String(error?.message || error).slice(0, 200)}`,
      );
      return [];
    }
  }
}

module.exports = { JahezAdapter };
