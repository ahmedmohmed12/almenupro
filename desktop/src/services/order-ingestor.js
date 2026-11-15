'use strict';

const {
  ALLOWED_PROVIDERS,
  dedupeKey,
  validateOrderPayload,
} = require('./payload-validator');

class OrderIngestor {
  constructor({
    restaurantId,
    dedupe,
    queue,
    onError = () => {},
    onIngest = () => {},
    logger = console,
  }) {
    if (!restaurantId || !dedupe || !queue) {
      throw new TypeError('restaurantId, dedupe, and queue are required');
    }
    this.restaurantId = restaurantId;
    this.dedupe = dedupe;
    this.queue = queue;
    this.onError = onError;
    this.onIngest = onIngest;
    this.logger = logger;
  }

  ingest(provider, payload, { source = 'scraper' } = {}) {
    const normalizedProvider = String(provider || '').trim().toLowerCase();
    if (!ALLOWED_PROVIDERS.has(normalizedProvider)) {
      return this.fail(normalizedProvider || 'unknown', 'Unsupported provider', source);
    }
    if (!Array.isArray(payload) || payload.length === 0 || payload.length > 100) {
      return this.fail(
        normalizedProvider,
        'Order batch must contain between 1 and 100 records',
        source,
      );
    }

    const result = { accepted: 0, duplicates: 0, rejected: 0, errors: [] };
    const ingestionSource =
      String(source).toLowerCase() === 'talabat-rest-api'
        ? 'API'
        : 'DOM_SCRAPER';
    for (const raw of payload) {
      try {
        const order = {
          ...validateOrderPayload(raw, normalizedProvider),
          ingestionSource,
          ingestion_source: ingestionSource,
        };
        const key = dedupeKey(this.restaurantId, order);
        if (this.dedupe.has(key)) {
          result.duplicates += 1;
          continue;
        }
        this.queue.enqueue({
          key,
          restaurantId: this.restaurantId,
          order,
        });
        this.dedupe.add(key);
        result.accepted += 1;
        this.logger.info(
          `[INGESTION MODE] Order #${order.externalOrderId} ingested via ${ingestionSource}`,
        );
        try {
          this.onIngest({
            provider: normalizedProvider,
            externalOrderId: order.externalOrderId,
            ingestionSource,
          });
        } catch (error) {
          this.logger.warn('Order ingestion event callback failed:', error);
        }
      } catch (error) {
        const message = String(error?.message || error).slice(0, 300);
        result.rejected += 1;
        result.errors.push(message);
        this.reportError(normalizedProvider, message, source);
      }
    }
    return result;
  }

  fail(provider, message, source) {
    this.reportError(provider, message, source);
    return { accepted: 0, duplicates: 0, rejected: 1, errors: [message] };
  }

  reportError(provider, message, source) {
    try {
      this.onError({ provider, message, source });
    } catch (error) {
      console.error('Order ingestion error callback failed:', error);
    }
  }
}

module.exports = { OrderIngestor };
