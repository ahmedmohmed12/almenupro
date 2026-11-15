'use strict';

const path = require('node:path');
const { loadConfig } = require('../src/config');

try {
  const config = loadConfig(path.resolve(__dirname, '..'));
  console.log(
    JSON.stringify(
      {
        ok: config.warnings.length === 0,
        loadedEnvFiles: config.loadedEnvFiles,
        posUrl: config.posUrl,
        apiUrl: config.apiUrl,
        restaurantId: config.restaurantId,
        apiToken: config.apiToken
          ? `configured (${config.apiToken.length} characters)`
          : 'missing',
        mockOrders: {
          enabled: config.mockOrders.enabled,
          port: config.mockOrders.port,
          secret: config.mockOrders.secret ? 'configured' : 'missing',
        },
        providerAllowedOrigins: config.providerAllowedOrigins,
        providerOrderScreenUrls: config.providerOrderScreenUrls,
        warnings: config.warnings,
      },
      null,
      2,
    ),
  );
  if (config.warnings.length) process.exitCode = 2;
} catch (error) {
  console.error(JSON.stringify({ ok: false, error: error.message }, null, 2));
  process.exitCode = 1;
}
