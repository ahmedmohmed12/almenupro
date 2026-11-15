'use strict';

const fs = require('node:fs');
const path = require('node:path');

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return false;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!match || Object.hasOwn(process.env, match[1])) continue;
    let value = match[2];
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env[match[1]] = value;
  }
  return true;
}

function validHttpUrl(value, name) {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error(`${name} must be a valid URL`);
  }
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error(`${name} must use http or https`);
  }
  return parsed.toString();
}

function allowedOrigins(value, fallbackUrl, name) {
  const values = String(value || '')
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);
  if (values.length === 0) values.push(fallbackUrl);
  return [...new Set(values.map((entry) => new URL(validHttpUrl(entry, name)).origin))];
}

function envFlag(value) {
  return /^(1|true|yes|on)$/i.test(String(value || '').trim());
}

function providerList(value) {
  const supported = new Set(['talabat', 'jahez', 'keeta']);
  const providers = String(value || 'talabat,jahez,keeta')
    .split(',')
    .map((entry) => entry.trim().toLowerCase())
    .filter(Boolean);
  if (!providers.length || providers.some((entry) => !supported.has(entry))) {
    throw new Error('DESKTOP_SYNC_PROVIDERS contains an unsupported provider');
  }
  return [...new Set(providers)];
}

function allowedUrlList(value, name, origins) {
  return String(value || '')
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const url = validHttpUrl(entry, name);
      if (!origins.includes(new URL(url).origin)) {
        throw new Error(`${name} contains a URL outside the provider allowlist`);
      }
      return url;
    });
}

function loadConfig(baseDir = path.resolve(__dirname, '..')) {
  const baseDirs = Array.isArray(baseDir) ? baseDir : [baseDir];
  const loadedEnvFiles = [];
  for (const directory of baseDirs) {
    for (const name of ['.env', '.env.local']) {
      if (loadEnvFile(path.join(directory, name))) {
        loadedEnvFiles.push(path.join(directory, name));
      }
    }
  }

  const restaurantId = String(
    process.env.DESKTOP_RESTAURANT_ID || 'rest_molton',
  ).trim();
  if (!/^[A-Za-z0-9_.:-]{1,100}$/.test(restaurantId)) {
    throw new Error('DESKTOP_RESTAURANT_ID contains unsupported characters');
  }
  const sessionProfile = String(
    process.env.DESKTOP_SESSION_PROFILE || restaurantId,
  ).trim();
  if (!/^[A-Za-z0-9_.:-]{1,100}$/.test(sessionProfile)) {
    throw new Error('DESKTOP_SESSION_PROFILE contains unsupported characters');
  }

  const providers = {
    talabat: validHttpUrl(
      process.env.DESKTOP_TALABAT_URL ||
        'https://partner-app.talabat.com/',
      'DESKTOP_TALABAT_URL',
    ),
    jahez: validHttpUrl(
      process.env.DESKTOP_JAHEZ_URL ||
        'https://portal.jahez.net/restaurant-login.htm',
      'DESKTOP_JAHEZ_URL',
    ),
    keeta: validHttpUrl(
      process.env.DESKTOP_KEETA_URL ||
        'https://merchant.mykeeta.com/m/web/mach/b_pc_order_history_list',
      'DESKTOP_KEETA_URL',
    ),
  };

  const apiToken = String(process.env.DESKTOP_API_TOKEN || '').trim();
  const mockOrdersEnabled = envFlag(process.env.DESKTOP_ENABLE_MOCK_ORDERS);
  const mockPort = Number(process.env.DESKTOP_MOCK_PORT || 17321);
  const mockSecret = String(process.env.DESKTOP_MOCK_SECRET || '').trim();
  const talabatApiPollIntervalMs = Number(
    process.env.DESKTOP_TALABAT_API_POLL_INTERVAL_MS || 60_000,
  );
  const historyRefreshIntervalMs = Number(
    process.env.DESKTOP_HISTORY_REFRESH_MS || 60_000,
  );
  if (
    !Number.isInteger(mockPort) ||
    mockPort < 1024 ||
    mockPort > 65535
  ) {
    throw new Error('DESKTOP_MOCK_PORT must be an integer from 1024 to 65535');
  }
  if (mockOrdersEnabled && mockSecret.length < 16) {
    throw new Error(
      'DESKTOP_MOCK_SECRET must contain at least 16 characters when mock orders are enabled',
    );
  }
  if (
    !Number.isInteger(talabatApiPollIntervalMs) ||
    talabatApiPollIntervalMs < 30_000 ||
    talabatApiPollIntervalMs > 3_600_000
  ) {
    throw new Error(
      'DESKTOP_TALABAT_API_POLL_INTERVAL_MS must be between 30000 and 3600000',
    );
  }
  if (
    !Number.isInteger(historyRefreshIntervalMs) ||
    historyRefreshIntervalMs < 15_000 ||
    historyRefreshIntervalMs > 600_000
  ) {
    throw new Error(
      'DESKTOP_HISTORY_REFRESH_MS must be between 15000 and 600000',
    );
  }

  const providerAllowedOrigins = {
    talabat: allowedOrigins(
      process.env.DESKTOP_TALABAT_ALLOWED_ORIGINS ||
        'https://partner-app.talabat.com,https://portal.talabat.com',
      providers.talabat,
      'DESKTOP_TALABAT_ALLOWED_ORIGINS',
    ),
    jahez: allowedOrigins(
      process.env.DESKTOP_JAHEZ_ALLOWED_ORIGINS ||
        'https://portal.jahez.net',
      providers.jahez,
      'DESKTOP_JAHEZ_ALLOWED_ORIGINS',
    ),
    keeta: allowedOrigins(
      process.env.DESKTOP_KEETA_ALLOWED_ORIGINS ||
        'https://merchant.keeta-global.com,https://merchant.mykeeta.com',
      providers.keeta,
      'DESKTOP_KEETA_ALLOWED_ORIGINS',
    ),
  };

  return {
    loadedEnvFiles,
    posUrl: validHttpUrl(
      process.env.DESKTOP_POS_URL || 'http://localhost:8080',
      'DESKTOP_POS_URL',
    ),
    apiUrl: validHttpUrl(
      process.env.DESKTOP_API_URL ||
        'https://almenupro-backend-1.onrender.com/api',
      'DESKTOP_API_URL',
    ).replace(/\/$/, ''),
    restaurantId,
    sessionProfile,
    syncProviders: providerList(process.env.DESKTOP_SYNC_PROVIDERS),
    talabatApiPollIntervalMs,
    historyRefreshIntervalMs,
    apiToken,
    warnings: apiToken
      ? []
      : ['DESKTOP_API_TOKEN is empty; captured orders cannot be submitted'],
    mockOrders: {
      enabled: mockOrdersEnabled,
      port: mockPort,
      secret: mockSecret,
    },
    providers,
    providerAllowedOrigins,
    providerOrderScreenUrls: {
      talabat: allowedUrlList(
        process.env.DESKTOP_TALABAT_ORDER_URLS,
        'DESKTOP_TALABAT_ORDER_URLS',
        providerAllowedOrigins.talabat,
      ),
      jahez: allowedUrlList(
        process.env.DESKTOP_JAHEZ_ORDER_URLS,
        'DESKTOP_JAHEZ_ORDER_URLS',
        providerAllowedOrigins.jahez,
      ),
      keeta: allowedUrlList(
        process.env.DESKTOP_KEETA_ORDER_URLS,
        'DESKTOP_KEETA_ORDER_URLS',
        providerAllowedOrigins.keeta,
      ),
    },
  };
}

function partitionFor(provider, restaurantId) {
  const safeRestaurant = String(restaurantId)
    .toLowerCase()
    .replace(/[^a-z0-9_.-]/g, '_')
    .slice(0, 100);
  return `persist:provider-${provider}-${safeRestaurant}`;
}

module.exports = {
  allowedOrigins,
  allowedUrlList,
  envFlag,
  loadConfig,
  partitionFor,
  validHttpUrl,
};
