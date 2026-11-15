'use strict';

const DAY_MS = 24 * 60 * 60 * 1000;

function canonicalOrderId(value) {
  const text = String(value || '').trim();
  if (!text) return '';
  const tail = text.split('|').pop().trim();
  return tail || text;
}

function platformKey(platform) {
  const name = String(platform || '').trim().toLowerCase();
  if (name === 'keta') return 'keeta';
  return name;
}

/**
 * Shared memory of order ids already handed to the POS.
 * Network interception is the primary writer. The DOM scraper reads this
 * before it opens or dispatches an order, and writes only on a cache miss.
 * Entries expire after 24 hours and the map stays capped so a long shift
 * cannot grow without bound.
 */
class ProcessedOrderCache {
  constructor({ ttlMs = DAY_MS, maxEntries = 5000 } = {}) {
    this.ttlMs = ttlMs;
    this.maxEntries = maxEntries;
    this.entries = new Map();
  }

  key(platform, orderId, storeId = '') {
    const id = canonicalOrderId(orderId);
    const name = platformKey(platform);
    const store = String(storeId || '').trim();
    if (!id || !name) return '';
    return store ? `${name}:${store}:${id}` : `${name}:${id}`;
  }

  prune(now = Date.now()) {
    const cutoff = now - this.ttlMs;
    for (const [key, entry] of this.entries) {
      if (!entry || entry.at < cutoff) this.entries.delete(key);
    }
    if (this.entries.size <= this.maxEntries) return;
    const oldest = [...this.entries.entries()].sort((a, b) => a[1].at - b[1].at);
    const extra = this.entries.size - this.maxEntries;
    for (let index = 0; index < extra; index += 1) {
      this.entries.delete(oldest[index][0]);
    }
  }

  has(platform, orderId, storeId = '') {
    this.prune();
    const key = this.key(platform, orderId, storeId);
    return Boolean(key && this.entries.has(key));
  }

  remember(platform, orderId, source, storeId = '') {
    const key = this.key(platform, orderId, storeId);
    if (!key) return false;
    this.prune();
    this.entries.set(key, { at: Date.now(), source: String(source || '') });
    this.prune();
    return true;
  }

  processedIds(platform, orderIds, storeId = '') {
    this.prune();
    return (Array.isArray(orderIds) ? orderIds : []).filter((orderId) =>
      this.has(platform, orderId, storeId),
    );
  }
}

module.exports = {
  ProcessedOrderCache,
  canonicalOrderId,
  platformKey,
};
