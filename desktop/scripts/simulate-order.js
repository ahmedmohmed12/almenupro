'use strict';

const path = require('node:path');
const { loadConfig } = require('../src/config');

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

async function waitForBackendOrder(
  config,
  externalOrderId,
  { requireConfirmed = false, attempts = 10 } = {},
) {
  if (!config.apiToken) return null;
  const url = new URL(`${config.apiUrl}/orders`);
  url.searchParams.set('restaurantId', config.restaurantId);
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${config.apiToken}`,
        'X-Restaurant-Id': config.restaurantId,
      },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      throw new Error(`Backend verification failed with HTTP ${response.status}`);
    }
    const orders = await response.json();
    const found = Array.isArray(orders)
      ? orders.find(
          (order) =>
            String(order.externalOrderId || order.external_order_id) ===
            externalOrderId,
        )
      : null;
    if (
      found &&
      (!requireConfirmed ||
        String(found.status || '').toLowerCase() === 'confirmed')
    ) {
      return found;
    }
    await delay(1000);
  }
  return null;
}

async function main() {
  const config = loadConfig(path.resolve(__dirname, '..'));
  if (!config.mockOrders.enabled) {
    throw new Error(
      'Set DESKTOP_ENABLE_MOCK_ORDERS=true and DESKTOP_MOCK_SECRET in desktop/.env, then restart Electron',
    );
  }
  const positional = process.argv
    .slice(2)
    .filter((argument) => !argument.startsWith('--'));
  const requested = String(positional[0] || 'talabat').trim().toLowerCase();
  const platform = requested === 'keta' ? 'keeta' : requested;
  if (!['talabat', 'jahez', 'keeta'].includes(platform)) {
    throw new Error('Provider must be talabat, jahez, or keeta');
  }
  const externalOrderId =
    positional[1] || `MOCK-${platform.toUpperCase()}-${Date.now()}`;
  const waitForConfirmation = process.argv.includes('--wait-confirmed');
  const payload = {
    platform,
    externalOrderId,
    customerName: 'Electron Mock Customer',
    phone: '+96550000000',
    address: 'Local integration test',
    deliveryType: 'delivery',
    paymentMethod: 'cash',
    createdAt: new Date().toISOString(),
    items: [
      {
        name: 'Mock Integration Meal',
        quantity: 2,
        unitPrice: 1.75,
        lineTotal: 3.5,
        options: [{ name: 'Mock sauce', price: 0 }],
      },
    ],
    subtotal: 3.5,
    totalAmount: 3.5,
  };
  const response = await fetch(
    `http://127.0.0.1:${config.mockOrders.port}/inject`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${config.mockOrders.secret}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10_000),
    },
  );
  const result = await response.json();
  if (!response.ok) {
    throw new Error(`Mock injection failed (${response.status}): ${JSON.stringify(result)}`);
  }
  const persisted = await waitForBackendOrder(config, externalOrderId);
  if (config.apiToken && !persisted) {
    throw new Error(
      `Order ${externalOrderId} entered Electron but was not found in the backend after 10 seconds`,
    );
  }
  const confirmed = waitForConfirmation
    ? await waitForBackendOrder(config, externalOrderId, {
        requireConfirmed: true,
        attempts: 25,
      })
    : null;
  if (waitForConfirmation && !confirmed) {
    throw new Error(
      `Order ${externalOrderId} persisted but was not confirmed by the POS within 25 seconds. Check that the POS is open and a cashier shift is active.`,
    );
  }
  console.log(
    JSON.stringify(
      {
        externalOrderId,
        platform,
        queueResult: result,
        backendPersistence: persisted
          ? { confirmed: true, id: persisted.id, status: persisted.status }
          : { confirmed: false, reason: 'DESKTOP_API_TOKEN is missing' },
        posConfirmation: waitForConfirmation
          ? { confirmed: true, status: confirmed.status }
          : { checked: false, hint: 'Pass --wait-confirmed for full POS E2E' },
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
