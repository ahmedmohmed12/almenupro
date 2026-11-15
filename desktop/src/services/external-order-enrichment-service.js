'use strict';

class ExternalOrderEnrichmentService {
  constructor({ apiUrl, apiToken, restaurantId, fetchImpl = fetch }) {
    this.apiUrl = String(apiUrl || '').replace(/\/$/, '');
    this.apiToken = apiToken;
    this.restaurantId = restaurantId;
    this.fetchImpl = fetchImpl;
  }

  async enrich(order) {
    if (!this.apiToken) return false;
    if (
      !order?.customerName &&
      !order?.phone &&
      !order?.address &&
      !order?.paymentMethod
    ) {
      return false;
    }
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const response = await this.fetchImpl(
        `${this.apiUrl}/v1/orders/external/enrich`,
        {
          method: 'PATCH',
          headers: {
            Authorization: `Bearer ${this.apiToken}`,
            'Content-Type': 'application/json',
            'X-Restaurant-Id': this.restaurantId,
          },
          body: JSON.stringify({
            platform: order.platform,
            externalOrderId: order.externalOrderId,
            customerName: order.customerName,
            phone: order.phone,
            address: order.address,
            paymentMethod: order.paymentMethod,
          }),
        },
      );
      if (response.ok) return true;
      if (response.status !== 404 || attempt === 2) {
        throw new Error(`External order enrichment failed: HTTP ${response.status}`);
      }
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }
    return false;
  }
}

module.exports = { ExternalOrderEnrichmentService };
