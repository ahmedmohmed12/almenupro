'use strict';

class ExternalOrderPurgeService {
  constructor({ apiUrl, apiToken, restaurantId, fetchImpl = globalThis.fetch }) {
    this.endpoint = `${String(apiUrl || '').replace(/\/$/, '')}/v1/orders/external/purge-extras`;
    this.apiToken = apiToken;
    this.restaurantId = restaurantId;
    this.fetchImpl = fetchImpl;
  }

  async purge(provider, liveOrderIds) {
    const ids = [
      ...new Set(
        (Array.isArray(liveOrderIds) ? liveOrderIds : [])
          .map((value) => String(value || '').trim())
          .filter(Boolean),
      ),
    ].slice(0, 500);
    if (!this.apiToken || !ids.length) return 0;
    const response = await this.fetchImpl(this.endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.apiToken}`,
        'Content-Type': 'application/json',
        'X-Restaurant-Id': this.restaurantId,
      },
      body: JSON.stringify({
        platform: provider,
        liveOrderIds: ids,
        scanReliable: true,
      }),
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) {
      throw new Error(`Platform extra purge failed: HTTP ${response.status}`);
    }
    const payload = await response.json().catch(() => ({}));
    return Number(payload.purged) || 0;
  }
}

module.exports = { ExternalOrderPurgeService };
