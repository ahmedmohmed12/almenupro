'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ProviderHistoryRefresh,
  sameHistorySurface,
} = require('../src/services/provider-history-refresh');

test('sameHistorySurface matches order history paths ignoring trailing slash', () => {
  assert.equal(
    sameHistorySurface(
      'https://partner-app.talabat.com/orders/history',
      'https://partner-app.talabat.com/orders/history/',
    ),
    true,
  );
  assert.equal(
    sameHistorySurface(
      'https://partner-app.talabat.com/dashboard',
      'https://partner-app.talabat.com/orders/history',
    ),
    false,
  );
});

test('ProviderHistoryRefresh reloads when already on history and navigates otherwise', async () => {
  const reloads = [];
  const loads = [];
  const views = {
    talabat: {
      webContents: {
        isDestroyed: () => false,
        isLoading: () => false,
        getURL: () => 'https://partner-app.talabat.com/orders/history',
        reload: () => reloads.push('talabat'),
        loadURL: async (url) => loads.push(['talabat', url]),
      },
    },
    keeta: {
      webContents: {
        isDestroyed: () => false,
        isLoading: () => false,
        getURL: () => 'https://merchant.mykeeta.com/login',
        reload: () => reloads.push('keeta'),
        loadURL: async (url) => loads.push(['keeta', url]),
      },
    },
    jahez: {
      webContents: {
        isDestroyed: () => false,
        isLoading: () => false,
        getURL: () => 'https://portal.jahez.net/orders',
        reload: () => reloads.push('jahez'),
        loadURL: async (url) => loads.push(['jahez', url]),
      },
    },
  };
  const refresh = new ProviderHistoryRefresh({
    providers: ['talabat', 'keeta', 'jahez'],
    intervalMs: 60_000,
    getView: (provider) => views[provider],
    historyUrlFor: (provider) =>
      ({
        talabat: 'https://partner-app.talabat.com/orders/history',
        keeta: 'https://merchant.mykeeta.com/m/web/mach/b_pc_order_history_list',
        jahez: 'https://portal.jahez.net/orders',
      })[provider],
    shouldSkip: (provider) => provider === 'jahez',
    logger: { info() {}, warn() {} },
  });

  await refresh.runCycle();

  assert.deepEqual(reloads, ['talabat']);
  assert.deepEqual(loads, [
    [
      'keeta',
      'https://merchant.mykeeta.com/m/web/mach/b_pc_order_history_list',
    ],
  ]);
});
