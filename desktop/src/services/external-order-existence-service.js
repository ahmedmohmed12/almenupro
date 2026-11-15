'use strict';

class ExternalOrderExistenceService {
  constructor({
    apiUrl,
    apiToken,
    restaurantId,
    fetchImpl = globalThis.fetch,
  }) {
    this.endpoint = `${apiUrl.replace(/\/$/, '')}/v1/orders/external/exists`;
    this.apiToken = apiToken;
    this.restaurantId = restaurantId;
    this.fetchImpl = fetchImpl;
  }

  async check(provider, externalOrderIds) {
    if (!this.apiToken) {
      throw new Error('DESKTOP_API_TOKEN is required for order history sync');
    }
    const ids = [
      ...new Set(
        (Array.isArray(externalOrderIds) ? externalOrderIds : [])
          .map((value) => String(value || '').trim().slice(0, 160))
          .filter(Boolean),
      ),
    ].slice(0, 100);
    if (!ids.length) return new Set();

    const url = new URL(this.endpoint);
    url.searchParams.set('platform', provider);
    for (const id of ids) url.searchParams.append('id', id);
    const response = await this.fetchImpl(url, {
      headers: {
        Authorization: `Bearer ${this.apiToken}`,
        'X-Restaurant-Id': this.restaurantId,
      },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      throw new Error(`External order existence check failed: HTTP ${response.status}`);
    }
    const payload = await response.json();
    return new Set(
      (Array.isArray(payload?.existing) ? payload.existing : []).map(String),
    );
  }
}

module.exports = { ExternalOrderExistenceService };
