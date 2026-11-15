'use strict';

class ExternalOrderReconciliationService {
  constructor({ apiUrl, apiToken, restaurantId, fetchImpl = fetch }) {
    this.apiUrl = String(apiUrl || '').replace(/\/$/, '');
    this.apiToken = apiToken;
    this.restaurantId = restaurantId;
    this.fetchImpl = fetchImpl;
    this.tail = Promise.resolve();
  }

  reconcile(order) {
    const task = this.tail.then(() => this.reconcileNow(order));
    this.tail = task.catch(() => {});
    return task;
  }

  async reconcileNow(order) {
    if (!this.apiToken || !order?.externalOrderId) {
      return { action: 'skipped', reason: 'missing_credentials_or_id' };
    }
    const response = await this.fetchImpl(
      `${this.apiUrl}/v1/orders/external/reconcile`,
      {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${this.apiToken}`,
          'Content-Type': 'application/json',
          'X-Restaurant-Id': this.restaurantId,
        },
        body: JSON.stringify(order),
      },
    );
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(
        `External order reconciliation failed: HTTP ${response.status} ${
          payload.error || ''
        }`.trim(),
      );
    }
    return payload;
  }
}

module.exports = { ExternalOrderReconciliationService };
