'use strict';

const path = require('node:path');
const {
  app,
  BrowserWindow,
  WebContentsView,
  ipcMain,
  Notification,
  safeStorage,
  session,
} = require('electron');

function isBrokenPipe(error) {
  const code = error?.code || error?.cause?.code;
  return code === 'EPIPE' || code === 'ERR_STREAM_DESTROYED';
}

function installSafeConsole() {
  for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
    const original = console[level].bind(console);
    const stream = level === 'warn' || level === 'error' ? process.stderr : process.stdout;
    console[level] = (...args) => {
      if (stream && stream.writable === false) return;
      try {
        original(...args);
      } catch (error) {
        if (!isBrokenPipe(error)) throw error;
      }
    };
  }
  const ignorePipe = (error) => {
    if (isBrokenPipe(error)) return;
  };
  process.stdout?.on?.('error', ignorePipe);
  process.stderr?.on?.('error', ignorePipe);
}

function guardIpcListener(listener) {
  if (typeof listener !== 'function') return listener;
  return (event, ...args) => {
    try {
      const result = listener(event, ...args);
      if (result && typeof result.then === 'function') {
        return result.catch((error) => {
          if (isBrokenPipe(error)) return undefined;
          throw error;
        });
      }
      return result;
    } catch (error) {
      if (isBrokenPipe(error)) return undefined;
      throw error;
    }
  };
}

installSafeConsole();
for (const method of ['on', 'handle', 'once']) {
  const original = ipcMain[method].bind(ipcMain);
  ipcMain[method] = (channel, listener) => original(channel, guardIpcListener(listener));
}

const { loadConfig, partitionFor } = require('./config');
const { StoresConfig, registerStoreIpc } = require('./services/stores-config');
const {
  StoreLifecycleManager,
  applyPortalUserAgent,
  configurePortalSession,
  stampStoreOrder,
} = require('./services/store-lifecycle-manager');
const { DedupeStore } = require('./services/dedupe-store');
const {
  ExternalOrderEnrichmentService,
} = require('./services/external-order-enrichment-service');
const {
  ExternalOrderReconciliationService,
} = require('./services/external-order-reconciliation-service');
const {
  ExternalOrderExistenceService,
} = require('./services/external-order-existence-service');
const {
  ExternalOrderPurgeService,
} = require('./services/external-order-purge-service');
const { MockOrderServer } = require('./services/mock-order-server');
const {
  autoIngestNotice,
  runIsolatedPlatformSync,
} = require('./services/sync-orchestrator');
const { BackgroundOrderWatch } = require('./services/background-order-watch');
const {
  PlatformOrderNetworkInterceptor,
} = require('./services/platform-order-network');
const { createOrderDispatcher, fromDomOrder } = require('./services/orderParser');
const { ProcessedOrderCache } = require('./services/processed-order-cache');
const { OrderIngestor } = require('./services/order-ingestor');
const { OrderSubmitQueue } = require('./services/order-submit-queue');
const {
  TalabatIngestionService,
} = require('./services/talabat-ingestion-service');
const {
  VendorCredentialStore,
} = require('./services/vendor-credential-store');
const {
  DailyReconciliationEngine,
} = require('./services/sync-engine');
const { ViewManager } = require('./views/view-manager');
const { dedupeKey } = require('./services/payload-validator');

const TOOLBAR_HEIGHT = 64;
const PROVIDERS = ['talabat', 'jahez', 'keeta'];

let mainWindow;
let activeView = 'pos';
let config;
let queue;
let dedupe;
let externalOrderExistence;
let externalOrderPurge;
let externalOrderEnrichment;
let externalOrderReconciliation;
let ingestor;
let mockServer;
let dailyReconciliationEngine;
let backgroundOrderWatch;
const platformNetworkInterceptors = [];
let talabatIngestionService;
let vendorCredentialStore;
let viewManager;
let talabatDomActive = false;
let ingestionMode = {
  mode: 'login_required',
  label: '🔒 Login Required',
  reason: '',
  apiOk: false,
  warning: 'أدخل توكن Talabat أو سجّل الدخول للمنصة.',
  updatedAt: new Date().toISOString(),
};
const providerByWebContentsId = new Map();
const storeByWebContentsId = new Map();
let storeLifecycle = null;
let activeIngestionStore = null;
const viewsShowingError = new WeakSet();
const attemptedOrderScreens = new Map();
const reconcilingProviders = new Set();
const reconciliationTimeouts = new Map();
const manualSyncWaiters = new Map();
const pendingReconciliation = new Map();

function publishPosSync(channel, payload) {
  const pos = viewManager?.get('pos');
  if (!pos || pos.webContents.isDestroyed()) return;
  pos.webContents.send(channel, payload);
}

function showDesktopNotice(body) {
  if (!Notification.isSupported()) return;
  const notice = new Notification({
    title: 'AlMenuPro',
    body: String(body || '').slice(0, 180),
    silent: false,
  });
  notice.show();
}

function publishBackgroundCapture(row) {
  const synced = Number(row?.synced) || 0;
  const purged = Number(row?.purged) || 0;
  if (!synced && !purged) {
    if (row?.unread) {
      console.info(
        `[Order Watch] ${row.provider} waiting for the history table${
          row.error ? ` (${row.error})` : ''
        }`,
      );
    }
    return;
  }
  const notice = synced
    ? autoIngestNotice(row.provider, { synced, orderId: row.orderId })
    : '';
  publishPosSync('pos:sync-platform', {
    ...row,
    background: true,
    notice,
  });
  if (notice) showDesktopNotice(notice);
  console.info(
    `[Order Watch] ${row.provider} synced=${synced} purged=${purged}${
      notice ? ` ${notice}` : ''
    }`,
  );
}

function publishIncomingOrder(order) {
  const stamped = stampStoreOrder(order, activeIngestionStore);
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('incoming-order', stamped);
  }
  const posContents = viewManager?.get('pos')?.webContents;
  if (posContents && !posContents.isDestroyed()) {
    posContents.send('incoming-order', stamped);
  }
}

const incomingOrders = createOrderDispatcher({
  send(order) {
    processedOrders.remember(
      order.platform_name,
      order.order_id,
      'NETWORK',
      activeIngestionStore?.id || '',
    );
    publishIncomingOrder({ ...order, source: 'NETWORK' });
  },
  onIngest(order) {
    handleCapturedPlatformOrders(order.platform, [
      stampStoreOrder(order, activeIngestionStore),
    ]);
  },
});

const processedOrders = new ProcessedOrderCache();
let processedOrderSweep;

function acceptDomFallback(provider, payload) {
  const orders = Array.isArray(payload) ? payload : [];
  const fresh = [];
  for (const order of orders) {
    if (!order?.externalOrderId) continue;
    if (processedOrders.has(provider, order.externalOrderId, activeIngestionStore?.id || '')) {
      console.info(
        `[Order Cache] ${provider} ${order.externalOrderId} skipped, already in the 24h cache`,
      );
      continue;
    }
    const stored = dedupeKey(config.restaurantId, {
      platform: provider,
      externalOrderId: order.externalOrderId,
    });
    if (dedupe.has(stored)) {
      processedOrders.remember(
        provider,
        order.externalOrderId,
        'DOM 👁️',
        activeIngestionStore?.id || '',
      );
      continue;
    }
    fresh.push(stampStoreOrder(order, activeIngestionStore));
  }
  if (!fresh.length) return;
  ingestor.ingest(provider, fresh);
  for (const order of fresh) {
    if (order?.customerName || order?.phone || order?.address || order?.paymentMethod) {
      void externalOrderEnrichment.enrich({ ...order, platform: provider }).catch((error) => {
        console.warn(
          `[${provider}] contact enrichment failed: ${String(error?.message || error).slice(0, 300)}`,
        );
      });
    }
    const normalized = fromDomOrder({ ...order, platform: provider });
    if (!normalized.order_id) continue;
    processedOrders.remember(
      provider,
      normalized.order_id,
      'DOM 👁️',
      activeIngestionStore?.id || '',
    );
    incomingOrders.seed(normalized);
    publishIncomingOrder(normalized);
    console.info(
      `[DOM Fallback] ${provider} ${normalized.order_id} source=DOM items=${normalized.items.length}`,
    );
  }
}

function handleCapturedPlatformOrders(provider, orders) {
  for (const order of Array.isArray(orders) ? orders : []) {
    if (!order?.externalOrderId) continue;
    try {
      const reconciling = reconcilingProviders.has(provider);
      const result = reconciling
        ? { accepted: 0, duplicates: 0 }
        : ingestor.ingest(provider, [order], {
            source: `${provider}-order-api`,
          });
      if (order.customerName || order.phone || order.address) {
        void externalOrderEnrichment.enrich({ ...order, platform: provider }).catch((error) => {
          console.warn(
            `[${provider} Network] contact enrichment failed: ${String(error?.message || error).slice(0, 200)}`,
          );
        });
      }
      void externalOrderReconciliation.reconcile({ ...order, platform: provider }).catch((error) => {
        console.warn(
          `[${provider} Network] reconcile failed: ${String(error?.message || error).slice(0, 200)}`,
        );
      });
      console.info(
        `[${provider} Network] order ${order.externalOrderId}: accepted=${result.accepted} duplicate=${result.duplicates} items=${order.items?.length || 0} total=${Number(order.totalAmount) || 0}`,
      );
    } catch (error) {
      console.warn(
        `[${provider} Network] ingest failed: ${String(error?.message || error).slice(0, 200)}`,
      );
    }
  }
}

function noteManualSyncProgress(provider, payload) {
  const cycleId = String(payload?.cycleId || '');
  const waiter = manualSyncWaiters.get(`${cycleId}:${provider}`);
  if (!waiter) return;
  publishPosSync('pos:sync-progress', {
    provider,
    checked: Number(payload?.checked) || 0,
    synced: Number(payload?.synced) || 0,
  });
}

function noteManualSyncResult(provider, payload) {
  const cycleId = String(payload?.cycleId || '');
  const waiter = manualSyncWaiters.get(`${cycleId}:${provider}`);
  if (!waiter || waiter.settled) return;
  waiter.settled = true;
  clearTimeout(waiter.timer);
  manualSyncWaiters.delete(`${cycleId}:${provider}`);
  waiter.resolve({
    checked: Number(payload?.checked) || 0,
    ingested: Number(payload?.ingested) || 0,
    failed: Number(payload?.failed) || 0,
    customersUpdated: Number(payload?.customersUpdated) || 0,
    purged: Number(payload?.purged) || 0,
    unread: Boolean(payload?.unread),
    alert: String(payload?.alert || ''),
    error: payload?.error || '',
    orderId: Array.isArray(payload?.ingestedIds)
      ? String(payload.ingestedIds[0] || '')
      : String(payload?.orderId || ''),
  });
}

function waitForPlatformSync(provider, cycleId, timeoutMs = 3 * 60_000) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      const waiter = manualSyncWaiters.get(`${cycleId}:${provider}`);
      if (!waiter || waiter.settled) return;
      waiter.settled = true;
      manualSyncWaiters.delete(`${cycleId}:${provider}`);
      reconcilingProviders.delete(provider);
      pendingReconciliation.delete(provider);
      resolve({
        checked: 0,
        ingested: 0,
        failed: 1,
        unread: true,
        purged: 0,
        alert: 'table_missing',
        error: 'timeout',
      });
      console.warn(`[Sync] ${provider} scan timed out before the order table returned ids`);
    }, timeoutMs);
    timer.unref?.();
    manualSyncWaiters.set(`${cycleId}:${provider}`, {
      resolve,
      timer,
      settled: false,
    });
  });
}

function dispatchTodaySync(provider, cycleId, { interrupt = true, lockMs = 5 * 60_000 } = {}) {
  if (reconcilingProviders.has(provider)) {
    if (!interrupt) return { started: false, error: 'busy' };
    console.info(
      `[Sync] ${provider} previous cycle interrupted so today's scan can read the live table`,
    );
    clearTimeout(reconciliationTimeouts.get(provider));
    reconciliationTimeouts.delete(provider);
    reconcilingProviders.delete(provider);
    pendingReconciliation.delete(provider);
  }
  const view = viewManager?.get(provider);
  if (!view || view.webContents.isDestroyed()) {
    return { started: false, error: 'unavailable' };
  }
  reconcilingProviders.add(provider);
  clearTimeout(reconciliationTimeouts.get(provider));
  const timeout = setTimeout(() => {
    reconcilingProviders.delete(provider);
    pendingReconciliation.delete(provider);
    reconciliationTimeouts.delete(provider);
  }, lockMs);
  timeout.unref?.();
  reconciliationTimeouts.set(provider, timeout);
  const job = { cycleId, limit: 500, attempts: 0 };
  pendingReconciliation.set(provider, job);
  const sendJob = () => {
    if (view.webContents.isDestroyed() || !reconcilingProviders.has(provider)) return;
    job.attempts += 1;
    view.webContents.send('scraper:run-daily-reconciliation', {
      cycleId: job.cycleId,
      limit: job.limit,
    });
  };
  if (!(view.webContents.isLoadingMainFrame?.() || view.webContents.isLoading?.())) {
    sendJob();
  }
  return { started: true };
}

async function runWatchProvider(provider) {
  if (reconcilingProviders.has(provider)) {
    return { checked: 0, ingested: 0 };
  }
  const cycleId = `watch-${provider}-${Date.now()}`;
  const pending = waitForPlatformSync(provider, cycleId, 12 * 60_000);
  const dispatched = dispatchTodaySync(provider, cycleId, {
    interrupt: false,
    lockMs: 12 * 60_000,
  });
  if (!dispatched.started) {
    const waiter = manualSyncWaiters.get(`${cycleId}:${provider}`);
    if (waiter && !waiter.settled) {
      waiter.settled = true;
      clearTimeout(waiter.timer);
      manualSyncWaiters.delete(`${cycleId}:${provider}`);
      waiter.resolve({ checked: 0, ingested: 0, unread: false, purged: 0 });
    }
  }
  return pending;
}

function waitForViewLoad(view, timeoutMs = 20_000) {
  return new Promise((resolve) => {
    if (!view || view.webContents.isDestroyed()) {
      resolve();
      return;
    }
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      view.webContents.removeListener('did-finish-load', finish);
      resolve();
    };
    const timer = setTimeout(finish, timeoutMs);
    timer.unref?.();
    view.webContents.once('did-finish-load', finish);
  });
}

async function refreshProviderHistory(provider) {
  if (provider !== 'talabat' && provider !== 'keeta') return;
  const target = String((config.providerOrderScreenUrls[provider] || [])[0] || '').trim();
  if (!target) return;
  const view = viewManager?.get(provider);
  if (!view || view.webContents.isDestroyed()) return;
  if (reconcilingProviders.has(provider)) return;
  const loaded = waitForViewLoad(view);
  try {
    const current = new URL(view.webContents.getURL());
    const next = new URL(target);
    const same =
      current.origin === next.origin &&
      current.pathname.replace(/\/+$/, '') === next.pathname.replace(/\/+$/, '');
    if (same) view.webContents.reload();
    else await view.webContents.loadURL(target);
  } catch (error) {
    console.warn(
      `[Order Watch] ${provider} history refresh failed: ${String(error?.message || error).slice(0, 160)}`,
    );
    return;
  }
  await loaded;
  console.info(`[Order Watch] ${provider} history refreshed`);
}

async function refreshHistoryBeforeScan() {
  for (const provider of ['talabat', 'keeta']) {
    await refreshProviderHistory(provider);
  }
}
const providerRecoveryAt = new Map();

function secureWebPreferences(preload, extra = {}) {
  return {
    preload,
    contextIsolation: true,
    sandbox: true,
    nodeIntegration: false,
    webSecurity: true,
    allowRunningInsecureContent: false,
    spellcheck: false,
    ...extra,
  };
}

function lockSession(targetSession, { allowNotifications = false } = {}) {
  const allowed = new Set(allowNotifications ? ['notifications'] : []);
  targetSession.setPermissionCheckHandler((_webContents, permission) =>
    allowed.has(permission),
  );
  targetSession.setPermissionRequestHandler((_webContents, permission, reply) => {
    reply(allowed.has(permission));
  });
  targetSession.on('will-download', (event) => event.preventDefault());
}

function urlHasAllowedOrigin(rawUrl, allowedOrigins) {
  try {
    return allowedOrigins.includes(new URL(rawUrl).origin);
  } catch {
    return false;
  }
}

function errorPageUrl({ label, targetUrl, message }) {
  const escape = (value) =>
    String(value || '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  const html = `<!doctype html>
<html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escape(label)} unavailable</title>
<style>
body{margin:0;background:#f8fafc;color:#172033;font:16px system-ui;display:grid;min-height:100vh;place-items:center}
main{max-width:680px;margin:24px;padding:32px;border:1px solid #dbe2ea;border-radius:16px;background:#fff;box-shadow:0 12px 36px #0f172a18}
h1{margin:0 0 12px;color:#6b1124}code{display:block;overflow-wrap:anywhere;background:#f1f5f9;padding:12px;border-radius:8px}
p{line-height:1.55}.hint{color:#526071}
</style></head><body><main>
<h1>${escape(label)} could not be loaded</h1>
<p>${escape(message)}</p>
<code>${escape(targetUrl)}</code>
<p class="hint">Check the network and allowed origins, then use Home or Reload in the toolbar.</p>
</main></body></html>`;
  return `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;
}

function showViewError(view, label, targetUrl, message) {
  if (view.webContents.isDestroyed() || viewsShowingError.has(view)) return;
  viewsShowingError.add(view);
  void view.webContents
    .loadURL(errorPageUrl({ label, targetUrl, message }))
    .catch((error) => {
      if (error?.code !== 'ERR_ABORTED') {
        console.error(`${label} error page failed:`, error);
      }
    });
}

function hardenView(view, allowedOrigins, label) {
  view.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  view.webContents.on('will-attach-webview', (event) => event.preventDefault());
  view.webContents.on('will-navigate', (event, targetUrl) => {
    if (
      !targetUrl.startsWith('data:text/html') &&
      !urlHasAllowedOrigin(targetUrl, allowedOrigins)
    ) {
      event.preventDefault();
      showViewError(
        view,
        label,
        targetUrl,
        'Navigation was blocked because its origin is not allowlisted.',
      );
    }
  });
  view.webContents.on(
    'did-fail-load',
    (_event, errorCode, errorDescription, validatedUrl, isMainFrame) => {
      if (
        !isMainFrame ||
        errorCode === -3 ||
        validatedUrl.startsWith('data:text/html') ||
        viewsShowingError.has(view)
      ) {
        return;
      }
      showViewError(
        view,
        label,
        validatedUrl,
        `${errorDescription} (${errorCode})`,
      );
    },
  );
  view.webContents.on('did-finish-load', () => {
    sendState();
  });
  view.webContents.on('render-process-gone', (_event, details) => {
    sendState({ error: `View renderer stopped: ${details.reason}` });
  });
}

function safeLoadURL(view, url, label) {
  viewsShowingError.delete(view);
  return view.webContents.loadURL(url).catch((error) => {
    // A deliberate redirect starts a new navigation and aborts the previous
    // load. Electron reports that expected transition as ERR_ABORTED.
    if (error?.code === 'ERR_ABORTED') return;
    const message = `${label} failed to load: ${String(error.message || error)}`;
    console.error(message);
    sendState({ error: message });
    showViewError(view, label, url, String(error.message || error));
  });
}

function navigationLabel(rawUrl) {
  try {
    const url = new URL(rawUrl);
    return `${url.origin}${url.pathname}`;
  } catch {
    return '<invalid-url>';
  }
}

function createContentViews() {
  const posView = new WebContentsView({
    webPreferences: secureWebPreferences(
      path.join(__dirname, 'preload', 'pos-preload.js'),
      {
        partition: partitionFor('pos', config.sessionProfile),
      },
    ),
  });
  lockSession(posView.webContents.session);
  hardenView(posView, [new URL(config.posUrl).origin], 'POS');
  viewManager.add('pos', posView);
  void safeLoadURL(posView, config.posUrl, 'POS');

  const scraperPreload = path.join(
    __dirname,
    '..',
    'dist',
    'scraper-preload.cjs',
  );
  const storeConfig = new StoresConfig({
    filePath: path.join(app.getPath('userData'), 'storesConfig.json'),
    defaults: PROVIDERS.map((provider) => ({
      id: `store_${provider}`,
      name: provider.charAt(0).toUpperCase() + provider.slice(1),
      type: provider,
      url: config.providers[provider],
      enabled: true,
      partition: partitionFor(provider, config.sessionProfile),
    })),
  });
  storeLifecycle = new StoreLifecycleManager({
    storeConfig,
    viewFactory: (store) => spawnStoreView(store, scraperPreload),
  });
  storeLifecycle.start();
}

function spawnStoreView(store, scraperPreload) {
  const provider = store.type;
  const providerSession = session.fromPartition(store.partition, { cache: true });
  lockSession(providerSession, { allowNotifications: true });
  configurePortalSession(providerSession);
  const view = new WebContentsView({
    webPreferences: secureWebPreferences(scraperPreload, {
      session: providerSession,
      backgroundThrottling: false,
      additionalArguments: [
        `--scraper-provider=${encodeURIComponent(provider)}`,
        `--scraper-store-id=${encodeURIComponent(store.id)}`,
        `--scraper-order-urls=${encodeURIComponent(
          JSON.stringify(config.providerOrderScreenUrls[provider] || []),
        )}`,
      ],
    }),
  });
  hardenView(view, config.providerAllowedOrigins[provider], store.name);
  applyPortalUserAgent(view.webContents);
  const networkInterceptor = new PlatformOrderNetworkInterceptor({
    webContents: view.webContents,
    provider,
    onPayload: (payload, meta) => {
      const previous = activeIngestionStore;
      activeIngestionStore = store;
      try {
        return incomingOrders.accept(payload, provider, meta);
      } finally {
        activeIngestionStore = previous;
      }
    },
  });
  networkInterceptor.attach();
  platformNetworkInterceptors.push(networkInterceptor);
  if (provider === 'keeta') {
    providerSession.webRequest.onCompleted(
      { urls: ['https://merchant.mykeeta.com/*'] },
      (details) => {
        if (details.statusCode < 400) return;
        console.warn(
          `[Keeta Network] HTTP ${details.statusCode} ${navigationLabel(details.url)}`,
        );
      },
    );
  }
  view.webContents.on('did-navigate', (_event, url) => {
    console.info(`[${store.id}] navigated to ${navigationLabel(url)}`);
  });
  view.webContents.on('did-finish-load', () => {
    if (provider === 'talabat') void dismissPortalNotificationPrompt(view.webContents);
    const job = pendingReconciliation.get(provider);
    if (!job || !reconcilingProviders.has(provider) || job.attempts >= 3) return;
    if (view.webContents.isDestroyed()) return;
    job.attempts += 1;
    view.webContents.send('scraper:run-daily-reconciliation', {
      cycleId: job.cycleId,
      limit: job.limit,
    });
  });
  providerByWebContentsId.set(view.webContents.id, provider);
  storeByWebContentsId.set(view.webContents.id, store);
  if (!viewManager.has(provider)) viewManager.add(provider, view);
  viewManager.add(store.id, view);
  const notificationPromptTimer =
    provider === 'talabat'
      ? setInterval(() => {
          void dismissPortalNotificationPrompt(view.webContents);
        }, 2000)
      : null;
  void safeLoadURL(view, store.url, store.name);
  return {
    destroy() {
      if (notificationPromptTimer) clearInterval(notificationPromptTimer);
      const index = platformNetworkInterceptors.indexOf(networkInterceptor);
      if (index >= 0) platformNetworkInterceptors.splice(index, 1);
      networkInterceptor.detach();
      providerByWebContentsId.delete(view.webContents.id);
      storeByWebContentsId.delete(view.webContents.id);
      viewManager.release(view);
    },
  };
}

function collectFrames(frame, into = []) {
  if (!frame) return into;
  into.push(frame);
  for (const child of frame.frames || []) collectFrames(child, into);
  return into;
}

const DISMISS_NOTIFICATION_PROMPT = `(() => {
  const title = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6,p,span,div,[role="heading"]')).find((node) => {
    const text = String(node.textContent || '').replace(/\\s+/g, ' ').trim();
    return text.length > 0 && text.length <= 80 && /please allow notifications/i.test(text);
  });
  if (!title) return false;
  let scope = title;
  for (let depth = 0; scope && depth < 10; depth += 1) {
    const button = Array.from(scope.querySelectorAll('button,[role="button"]')).find((node) =>
      /^got it$/i.test(String(node.textContent || '').replace(/\\s+/g, ' ').trim()),
    );
    if (typeof button?.click === 'function') {
      button.click();
      return true;
    }
    scope = scope.parentElement;
  }
  return false;
})()`;

async function dismissPortalNotificationPrompt(webContents) {
  if (!webContents || webContents.isDestroyed()) return false;
  let closed = false;
  for (const frame of collectFrames(webContents.mainFrame)) {
    try {
      if (await frame.executeJavaScript(DISMISS_NOTIFICATION_PROMPT, true)) closed = true;
    } catch {
      // A frame can disappear while the portal is navigating.
    }
  }
  if (closed) console.info('[Talabat Observer] closed the notifications prompt');
  return closed;
}

function showView(name) {
  viewManager?.show(name);
}

function state(extra = {}) {
  return {
    activeView,
    restaurantId: config.restaurantId,
    stores: storeLifecycle?.listStores() || [],
    queue: queue?.status() || { pending: 0, failed: 0 },
    warnings: config.warnings,
    ingestion: { ...ingestionMode },
    mockOrders: {
      enabled: config.mockOrders.enabled,
      port: config.mockOrders.enabled ? config.mockOrders.port : null,
    },
    ...extra,
  };
}

function cashierIngestionPresentation(mode, reason = '', domActive = false) {
  const detail = String(reason || '');
  if (mode === 'api_connected') {
    return {
      label: domActive ? '⚡ API شغال · DOM: شغال' : '⚡ API شغال',
      apiOk: true,
      warning: '',
    };
  }
  if (mode === 'login_required') {
    return {
      label: '🔒 التوكن غير مضبوط',
      apiOk: false,
      warning: 'التوكن غير مضبوط — افتح «توكن API» أو سجّل دخول Talabat.',
    };
  }
  // DOM active / API fallback
  if (/http_401|http_403|token|unauthorized|forbidden/i.test(detail)) {
    return {
      label: 'DOM: شغال',
      apiOk: false,
      warning:
        'توكن Talabat منتهي أو مرفوض — الطلبات تُسحب عبر مراقبة الصفحة حتى تجديد التوكن.',
    };
  }
  if (/network|timeout|credentials_missing/i.test(detail)) {
    return {
      label: 'DOM: شغال',
      apiOk: false,
      warning:
        'سحب API متوقف — الطلبات تُسحب عبر مراقبة الصفحة. راجع التوكن أو الاتصال.',
    };
  }
  return {
    label: 'DOM: شغال',
    apiOk: false,
    warning:
      'API غير مستقر — الطلبات تُسحب عبر مراقبة الصفحة حتى يعود الاتصال.',
  };
}

function noteTalabatDomWatching() {
  talabatDomActive = true;
  const mode = ingestionMode.mode === 'api_connected' ? 'api_connected' : 'dom_active';
  updateIngestionMode(mode, ingestionMode.reason);
}

function applyTalabatIngestionStatus({ mode, reason = '' } = {}) {
  if (mode === 'api_connected') {
    updateIngestionMode('api_connected');
    return;
  }
  if (mode === 'dom_fallback') {
    updateIngestionMode('dom_active', reason);
    return;
  }
  if (mode === 'credentials_missing') {
    updateIngestionMode(
      talabatDomActive ? 'dom_active' : 'login_required',
      'credentials_missing',
    );
  }
}

function sendState(extra = {}) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('shell:state', state(extra));
  }
}

function updateIngestionMode(mode, reason = '') {
  const normalized = ['api_connected', 'dom_active', 'login_required'].includes(
    mode,
  )
    ? mode
    : 'login_required';
  const nextReason = String(reason || '').slice(0, 120);
  const presentation = cashierIngestionPresentation(
    normalized,
    nextReason,
    talabatDomActive,
  );
  if (
    ingestionMode.mode === normalized &&
    ingestionMode.reason === nextReason &&
    ingestionMode.label === presentation.label &&
    ingestionMode.apiOk === presentation.apiOk
  ) {
    return;
  }
  ingestionMode = {
    mode: normalized,
    label: presentation.label,
    reason: nextReason,
    apiOk: presentation.apiOk,
    warning: presentation.warning,
    updatedAt: new Date().toISOString(),
  };
  console.info(
    `[Ingestion Status] ${presentation.label}${
      nextReason ? ` (${nextReason})` : ''
    }`,
  );
  sendState();
}

function registerIpc() {
  const fromShell = (event) =>
    mainWindow &&
    !mainWindow.isDestroyed() &&
    event.sender.id === mainWindow.webContents.id &&
    event.senderFrame === event.sender.mainFrame;
  const providerForEvent = (event) => {
    const provider = providerByWebContentsId.get(event.sender.id);
    if (!provider) return undefined;
    const frame = event.senderFrame;
    if (frame && event.sender.mainFrame && frame !== event.sender.mainFrame) return undefined;
    const url = String(frame?.url || event.sender.getURL?.() || '');
    if (
      url &&
      !url.startsWith('about:') &&
      !urlHasAllowedOrigin(url, config.providerAllowedOrigins[provider])
    ) {
      return undefined;
    }
    return provider;
  };
  const recoverProviderPortal = (provider, reason) => {
    const now = Date.now();
    const lastRecovery = providerRecoveryAt.get(provider) || 0;
    if (now - lastRecovery < 5 * 60_000) return false;
    const view = viewManager?.get(provider);
    if (!view || view.webContents.isDestroyed()) return false;
    providerRecoveryAt.set(provider, now);
    console.warn(
      `[${provider} Observer] recovering stalled background portal session (${reason})`,
    );
    void view.webContents.loadURL(config.providers[provider]);
    return true;
  };

  ipcMain.on('shell:select-view', (event, name) => {
    if (!fromShell(event)) return;
    const store = storeLifecycle?.getStore(name);
    if (store?.id && viewManager.has(store.id)) {
      showView(store.id);
      return;
    }
    const alias = storeLifecycle?.storeForType(name)?.id;
    const target = viewManager.has(name) ? name : alias;
    if (target && viewManager.has(target)) showView(target);
  });
  ipcMain.on('shell:reload', (event) => {
    if (fromShell(event)) viewManager.get(activeView)?.webContents.reload();
  });
  ipcMain.on('shell:home', (event) => {
    if (!fromShell(event)) return;
    const store =
      storeLifecycle?.getStore(activeView) ||
      storeLifecycle?.storeForType(activeView);
    const url = activeView === 'pos' ? config.posUrl : store?.url || config.providers[activeView];
    const view = viewManager.get(activeView);
    if (PROVIDERS.includes(activeView)) {
      attemptedOrderScreens.delete(activeView);
    }
    if (view) void safeLoadURL(view, url, activeView);
  });
  registerStoreIpc(ipcMain, {
    manager: {
      listStores: () => storeLifecycle?.listStores() || [],
      addStore: (input) => storeLifecycle.addStore(input),
      removeStore: (id) => storeLifecycle.removeStore(id),
      toggleStore: (id, enabled) => storeLifecycle.toggleStore(id, enabled),
    },
    authorize: fromShell,
    onChanged: () => sendState(),
  });
  ipcMain.handle('open-store', async (event, id) => {
    if (!fromShell(event)) throw new Error('Untrusted IPC sender');
    const existing = storeLifecycle?.getStore(id);
    if (!existing) throw new Error('Store was not found');
    const store =
      existing.enabled && viewManager.has(existing.id)
        ? existing
        : await storeLifecycle.toggleStore(existing.id, true);
    const target = viewManager.has(store.id) ? store.id : store.type;
    showView(target);
    const view = viewManager.get(store.id) || viewManager.get(store.type);
    if (!view || view.webContents.isDestroyed()) {
      throw new Error('Store view is not available');
    }
    await view.webContents.loadURL(store.url);
    return store;
  });
  ipcMain.handle('shell:get-state', (event) => {
    if (!fromShell(event)) throw new Error('Untrusted IPC sender');
    return state();
  });
  ipcMain.handle('shell:force-sync', async (event) => {
    if (!fromShell(event)) throw new Error('Untrusted IPC sender');
    if (!dailyReconciliationEngine) {
      throw new Error('Daily reconciliation engine is not ready');
    }
    const cycleId = await dailyReconciliationEngine.runCycle();
    console.info(`[Reconciliation] manual sync started: ${cycleId}`);
    return { ok: true, cycleId };
  });
  ipcMain.handle('pos:sync-today', async (event) => {
    const posView = viewManager?.get('pos');
    if (
      !posView ||
      posView.webContents.isDestroyed() ||
      event.sender.id !== posView.webContents.id ||
      event.senderFrame !== event.sender.mainFrame
    ) {
      throw new Error('Untrusted POS sender');
    }
    const providers = (config.syncProviders || []).filter((provider) =>
      PROVIDERS.includes(provider),
    );
    const cycleId = `manual-${Date.now()}`;
    const waited = await runIsolatedPlatformSync({
      providers,
      runProvider: async (provider) => {
        const pending = waitForPlatformSync(provider, cycleId);
        const dispatched = dispatchTodaySync(provider, cycleId);
        if (!dispatched.started) {
          const waiter = manualSyncWaiters.get(`${cycleId}:${provider}`);
          if (waiter && !waiter.settled) {
            waiter.settled = true;
            clearTimeout(waiter.timer);
            manualSyncWaiters.delete(`${cycleId}:${provider}`);
            waiter.resolve({
              checked: 0,
              ingested: 0,
              failed: dispatched.error === 'unavailable' ? 1 : 0,
              unread: true,
              purged: 0,
              error: dispatched.error || 'unavailable',
            });
          }
        }
        return pending;
      },
      onPlatformResult: (row) => {
        publishPosSync('pos:sync-platform', row);
        console.info(
          `[Sync] ${row.provider} finished independently: checked=${row.checked} synced=${row.synced} purged=${row.purged} unread=${row.unread}${row.error ? ` error=${row.error}` : ''}`,
        );
      },
    });
    console.info(
      `[Reconciliation] manual POS sync ${cycleId}: synced=${waited.synced} customers=${waited.customersUpdated}`,
    );
    return waited;
  });
  ipcMain.handle('shell:set-overlay', (event, visible) => {
    if (!fromShell(event)) throw new Error('Untrusted IPC sender');
    viewManager?.setShellOverlayVisible(Boolean(visible));
    return { ok: true, overlay: Boolean(visible) };
  });
  // Opens DevTools on Talabat only — never reads/captures session JWTs.
  ipcMain.handle('shell:open-talabat-devtools', (event) => {
    if (!fromShell(event)) throw new Error('Untrusted IPC sender');
    const view = viewManager?.get('talabat');
    if (!view || view.webContents.isDestroyed()) {
      throw new Error('Talabat view is not ready');
    }
    showView('talabat');
    viewManager?.setShellOverlayVisible(false);
    if (!view.webContents.isDevToolsOpened()) {
      view.webContents.openDevTools({ mode: 'detach' });
    } else {
      view.webContents.devToolsWebContents?.focus?.();
    }
    return {
      ok: true,
      filterHint: 'vendor-portal-api',
      pathHint: '/vendors/787662/orders',
    };
  });
  ipcMain.handle('vendor-credentials:status', (event, provider) => {
    if (!fromShell(event)) throw new Error('Untrusted IPC sender');
    return vendorCredentialStore.status(provider);
  });
  ipcMain.handle('vendor-credentials:save', (event, payload) => {
    if (!fromShell(event)) throw new Error('Untrusted IPC sender');
    if (!payload || typeof payload !== 'object') {
      throw new Error('Credential payload is required');
    }
    const result = vendorCredentialStore.save(payload.provider, {
      vendorId: payload.vendorId,
      authToken: payload.authToken,
    });
    console.info(
      `[Vendor Credentials] encrypted ${result.provider} credentials saved for vendor ${result.vendorId}`,
    );
    if (result.provider === 'talabat') {
      console.info('[Talabat API] credentials updated; polling immediately');
      void talabatIngestionService.pollNow().catch((error) => {
        sendState({
          error: `Talabat API: ${String(error?.message || error).slice(0, 300)}`,
        });
      });
    }
    return result;
  });
  ipcMain.handle('vendor-credentials:clear', (event, provider) => {
    if (!fromShell(event)) throw new Error('Untrusted IPC sender');
    return vendorCredentialStore.clear(provider);
  });
  ipcMain.handle('vendor-orders:poll-now', async (event, provider) => {
    if (!fromShell(event)) throw new Error('Untrusted IPC sender');
    if (String(provider || '').toLowerCase() !== 'talabat') {
      throw new Error('REST polling is not configured for this provider');
    }
    return talabatIngestionService.pollNow();
  });

  ipcMain.on('scraper:orders', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    if (provider === 'talabat') noteTalabatDomWatching();
    const previous = activeIngestionStore;
    activeIngestionStore = storeByWebContentsId.get(event.sender.id) || previous;
    try {
      acceptDomFallback(provider, payload);
    } finally {
      activeIngestionStore = previous;
    }
  });
  ipcMain.on('scraper:reconcile-orders', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    for (const order of Array.isArray(payload) ? payload : []) {
      void externalOrderReconciliation
        .reconcile({ ...order, platform: provider })
        .then((result) => {
          console.info(
            `[Reconciliation] ${provider} ${order.externalOrderId}: ${
              result.action || 'unknown'
            }`,
          );
        })
        .catch((error) => {
          console.warn(
            `[Reconciliation] ${provider} failed: ${String(
              error?.message || error,
            ).slice(0, 300)}`,
          );
        });
    }
  });
  ipcMain.handle('scraper:reconcile-order', async (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) throw new Error('Untrusted reconciliation sender');
    const order = { ...payload, platform: provider };
    const result = await externalOrderReconciliation.reconcile(order);
    console.info(
      `[Reconciliation] ${provider} ${order.externalOrderId}: ${
        result.action || 'unknown'
      }${result.reason ? ` (${result.reason})` : ''}`,
    );
    return result;
  });
  ipcMain.on('scraper:sync-diagnostic', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    const ids = Array.isArray(payload?.ids) ? payload.ids.map(String) : [];
    const label = provider.charAt(0).toUpperCase() + provider.slice(1);
    console.info(
      `[${label} Scraped IDs]: ${JSON.stringify(ids)} count=${ids.length} url=${String(
        payload?.href || '',
      )} visibility=${String(payload?.visibility || '')} history=${Boolean(
        payload?.historyPage,
      )} login=${Boolean(payload?.loginWall)} path=${String(payload?.path || '')}`,
    );
    if (payload?.containerText) {
      console.info(`[${label} table innerText]: ${String(payload.containerText).slice(0, 2500)}`);
    }
    if (payload?.containerHtml) {
      console.info(`[${label} table html]: ${String(payload.containerHtml).slice(0, 2500)}`);
    }
  });
  ipcMain.on('scraper:preload-ready', (event) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    console.info(`[Order Watch] ${provider} scraper ready`);
  });
  ipcMain.on('scraper:sync-progress', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    noteManualSyncProgress(provider, payload);
  });
  ipcMain.on('scraper:reconciliation-result', async (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    reconcilingProviders.delete(provider);
    pendingReconciliation.delete(provider);
    clearTimeout(reconciliationTimeouts.get(provider));
    reconciliationTimeouts.delete(provider);
    let purged = 0;
    if (payload?.scanReliable && Array.isArray(payload?.liveOrderIds) && externalOrderPurge) {
      try {
        purged = await externalOrderPurge.purge(provider, payload.liveOrderIds);
      } catch (error) {
        console.warn(
          `[Reconciliation] ${provider} extra purge failed: ${String(error?.message || error).slice(0, 200)}`,
        );
      }
    }
    noteManualSyncResult(provider, { ...payload, purged });
    console.info(
      `[Reconciliation] ${provider} completed: checked=${
        payload?.checked || 0
      } dispatched=${payload?.ingested || 0} failed=${payload?.failed || 0} unread=${Boolean(
        payload?.unread,
      )} purged=${purged}${
        payload?.actions
          ? ` actions=${JSON.stringify(payload.actions)}`
          : ''
      }${
        payload?.error ? ` error=${payload.error}` : ''
      }`,
    );
  });
  ipcMain.handle('scraper:check-order-ids', async (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) throw new Error('Untrusted order history sender');
    const ids = [
      ...new Set(
        (Array.isArray(payload) ? payload : [])
          .map((value) => String(value || '').trim().slice(0, 160))
          .filter(Boolean),
      ),
    ].slice(0, 200);
    const existing = new Set();
    const unresolved = [];
    for (const externalOrderId of ids) {
      const key = dedupeKey(config.restaurantId, {
        platform: provider,
        externalOrderId,
      });
      if (
        dedupe.has(key) ||
        processedOrders.has(provider, externalOrderId, storeByWebContentsId.get(event.sender.id)?.id || '')
      ) existing.add(externalOrderId);
      else unresolved.push(externalOrderId);
    }
    if (unresolved.length) {
      const backendExisting = await externalOrderExistence.check(
        provider,
        unresolved,
      );
      for (const externalOrderId of backendExisting) {
        existing.add(externalOrderId);
        dedupe.add(
          dedupeKey(config.restaurantId, {
            platform: provider,
            externalOrderId,
          }),
        );
      }
    }
    return {
      existing: ids.filter((id) => existing.has(id)),
      missing: ids.filter((id) => !existing.has(id)),
    };
  });
  ipcMain.handle('orders:processed-ids', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return { ids: [] };
    const ids = (Array.isArray(payload) ? payload : [])
      .map((value) => String(value || '').trim())
      .filter(Boolean)
      .slice(0, 200);
    return { ids: processedOrders.processedIds(provider, ids, storeByWebContentsId.get(event.sender.id)?.id || '') };
  });
  ipcMain.handle('orders:unprocessed', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return { ids: [] };
    const ids = (Array.isArray(payload) ? payload : [])
      .map((value) => String(value || '').trim())
      .filter(Boolean)
      .slice(0, 200);
    const seen = new Set(processedOrders.processedIds(provider, ids, storeByWebContentsId.get(event.sender.id)?.id || ''));
    return { ids: ids.filter((id) => !seen.has(id)) };
  });
  ipcMain.on('scraper:cache-skip', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    const ids = (Array.isArray(payload?.ids) ? payload.ids : [])
      .map((value) => String(value || '').trim())
      .filter(Boolean)
      .slice(0, 50);
    if (!ids.length) return;
    console.info(
      `[Order Cache] ${provider} skipped ${ids.join(',')} already in the 24h cache (${String(payload?.source || 'dom')})`,
    );
  });
  ipcMain.on('scraper:parse-miss', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    const reason = String(payload?.reason || 'selector-mismatch');
    const line = `[DOM Parse] ${provider} ${reason} order=${String(payload?.externalOrderId || '')} mode=${String(payload?.mode || '')} items=${Number(payload?.itemCount) || 0} itemSelector=${String(payload?.itemSelector || '')}`;
    if (reason === 'observed-row') console.info(line);
    else console.warn(line);
  });
  ipcMain.on('scraper:error', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    const message = String(payload?.message || '');
    console.warn(`[${provider}] scraper error: ${message}`);
    if (/network|timeout|fetch|http|invoice|فاتورة/i.test(message)) {
      const orderId = message.match(/#?\d{6,20}/)?.[0] || '';
      publishPosSync('pos:sync-alert', {
        provider,
        alert: 'invoice_network',
        orderId,
        error: message.slice(0, 200),
      });
    }
    sendState({
      error: `${provider}: ${String(payload?.message || 'Scraper error').slice(0, 300)}`,
    });
  });
  ipcMain.on('scraper:surface-ready', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    const surface = String(payload?.surface || '').slice(0, 40);
    if (!['live', 'history', 'default'].includes(surface)) return;
    if (provider === 'talabat') noteTalabatDomWatching();
    console.info(`[${provider}] observer attached to ${surface} order surface`);
  });
  ipcMain.on('scraper:observer-status', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    const status = payload?.status;
    if (provider === 'talabat' && status === 'waiting') {
      console.info(
        `[Talabat Observer] waiting for table render` +
          (payload?.spinner ? ' (loading spinner visible)' : ''),
      );
      return;
    }
    if (provider === 'talabat' && status === 'today-filter') {
      console.info(`[Talabat Observer] date filter ${String(payload?.result || 'today')}`);
      return;
    }
    if (provider === 'talabat' && status === 'attached') {
      noteTalabatDomWatching();
      console.info('[Talabat Observer] attached successfully; starting 3-order sync');
      return;
    }
    if (provider === 'talabat' && status === 'notification-prompt-dismissed') {
      console.info('[Talabat Observer] closed the notifications prompt');
      return;
    }
    if (provider === 'talabat' && status === 'navigating') {
      console.info('[Talabat Observer] opening Order History through portal navigation');
    }
  });
  ipcMain.on('scraper:sync-cycle-result', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    const ingested = Math.max(0, Number(payload?.ingested) || 0);
    if (payload?.busy) {
      console.info(
        `[SyncEngine] 1-min check deferred (${provider}): daily reconciliation is running`,
      );
      return;
    }
    if (payload?.error) {
      console.warn(
        `[SyncEngine] 1-min check failed (${provider}): ${String(
          payload.error,
        ).slice(0, 300)}`,
      );
      if (/table was not rendered/i.test(String(payload.error))) {
        recoverProviderPortal(provider, 'one-minute sync timeout');
      }
      return;
    }
    console.info(
      `[SyncEngine] 1-min check completed (${provider}): ${ingested} new orders ingested`,
    );
  });
  ipcMain.on('scraper:surface-diagnostic', (event, payload) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    console.info(
      `[${provider}] unmatched order surface ${JSON.stringify({
        path: String(payload?.path || '').slice(0, 120),
        candidates: Array.isArray(payload?.candidates)
          ? payload.candidates.slice(0, 30)
          : [],
      })}`,
    );
  });
  ipcMain.on('scraper:navigate-fallback', (event) => {
    const provider = providerForEvent(event);
    if (!provider) return;
    const attempted =
      attemptedOrderScreens.get(provider) || new Set([event.senderFrame.url]);
    attemptedOrderScreens.set(provider, attempted);
    const target = config.providerOrderScreenUrls[provider].find(
      (candidate) =>
        !attempted.has(candidate) &&
        urlHasAllowedOrigin(candidate, config.providerAllowedOrigins[provider]),
    );
    if (!target) return;
    attempted.add(target);
    const view = viewManager.get(provider);
    if (view) void safeLoadURL(view, target, `${provider} orders`);
  });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    ...(app.isPackaged
      ? {}
      : {
          icon: path.resolve(
            __dirname,
            '..',
            '..',
            'windows',
            'runner',
            'resources',
            'app_icon.ico',
          ),
        }),
    width: 1440,
    height: 900,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: '#101827',
    show: false,
    webPreferences: secureWebPreferences(
      path.join(__dirname, 'preload', 'shell-preload.js'),
    ),
  });
  mainWindow.setMenuBarVisibility(false);
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  lockSession(mainWindow.webContents.session);
  mainWindow
    .loadFile(path.join(__dirname, 'renderer', 'index.html'))
    .catch((error) => console.error('Shell UI failed to load:', error));

  viewManager = new ViewManager({
    window: mainWindow,
    toolbarHeight: TOOLBAR_HEIGHT,
    onActiveChanged: (name) => {
      activeView = name;
      sendState();
    },
  });
  createContentViews();
  viewManager.show('pos');

  mainWindow.on('resize', () => viewManager?.layout());
  mainWindow.once('ready-to-show', () => mainWindow.show());
  mainWindow.on('closed', () => {
    viewManager?.destroy();
    viewManager = null;
    providerByWebContentsId.clear();
    attemptedOrderScreens.clear();
    mainWindow = null;
  });
}

app.whenReady().then(async () => {
  processedOrderSweep = setInterval(() => processedOrders.prune(), 15 * 60 * 1000);
  processedOrderSweep.unref?.();
  app.setAppUserModelId('com.almenupro.desktop');
  const configDirectories = app.isPackaged
    ? [app.getPath('userData'), path.dirname(process.execPath)]
    : [path.resolve(__dirname, '..')];
  config = loadConfig(configDirectories);
  dedupe = new DedupeStore(
    path.join(app.getPath('userData'), 'scraper-dedupe.json'),
  );
  queue = new OrderSubmitQueue({
    filePath: path.join(app.getPath('userData'), 'order-submit-queue.json'),
    apiUrl: config.apiUrl,
    apiToken: config.apiToken,
  });
  externalOrderExistence = new ExternalOrderExistenceService({
    apiUrl: config.apiUrl,
    apiToken: config.apiToken,
    restaurantId: config.restaurantId,
  });
  externalOrderPurge = new ExternalOrderPurgeService({
    apiUrl: config.apiUrl,
    apiToken: config.apiToken,
    restaurantId: config.restaurantId,
  });
  externalOrderEnrichment = new ExternalOrderEnrichmentService({
    apiUrl: config.apiUrl,
    apiToken: config.apiToken,
    restaurantId: config.restaurantId,
  });
  externalOrderReconciliation = new ExternalOrderReconciliationService({
    apiUrl: config.apiUrl,
    apiToken: config.apiToken,
    restaurantId: config.restaurantId,
  });
  queue.on('status', () => sendState());
  ingestor = new OrderIngestor({
    restaurantId: config.restaurantId,
    dedupe,
    queue,
    onError: ({ provider, message, source }) => {
      sendState({ error: `${provider} (${source}): ${message}` });
    },
    onIngest: (event) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('shell:order-ingested', event);
      }
    },
  });
  vendorCredentialStore = new VendorCredentialStore({
    filePath: path.join(app.getPath('userData'), 'vendor-credentials.json'),
    safeStorage,
  });
  talabatIngestionService = new TalabatIngestionService({
    ingestor,
    credentialStore: vendorCredentialStore,
    intervalMs: config.talabatApiPollIntervalMs,
    onStatus: applyTalabatIngestionStatus,
    onFallback: async ({ reason }) => {
      updateIngestionMode('dom_active', reason);
    },
  });
  queue.start();
  registerIpc();
  createWindow();
  talabatIngestionService.start();
  dailyReconciliationEngine = new DailyReconciliationEngine({
    providers: config.syncProviders,
    dispatch: async (provider, payload) => {
      if (reconcilingProviders.has(provider)) {
        console.info(
          `[Reconciliation] ${provider} cycle skipped because the previous cycle is still running`,
        );
        return;
      }
      const view = viewManager?.get(provider);
      if (!view || view.webContents.isDestroyed()) {
        throw new Error('Provider view is unavailable');
      }
      reconcilingProviders.add(provider);
      clearTimeout(reconciliationTimeouts.get(provider));
      const timeout = setTimeout(() => {
        reconcilingProviders.delete(provider);
        pendingReconciliation.delete(provider);
        reconciliationTimeouts.delete(provider);
      }, 5 * 60_000);
      timeout.unref?.();
      reconciliationTimeouts.set(provider, timeout);
      pendingReconciliation.set(provider, {
        cycleId: payload?.cycleId,
        limit: 500,
        attempts: 0,
      });
      if (!(view.webContents.isLoadingMainFrame?.() || view.webContents.isLoading?.())) {
        const job = pendingReconciliation.get(provider);
        job.attempts += 1;
        view.webContents.send('scraper:run-daily-reconciliation', {
          cycleId: job.cycleId,
          limit: job.limit,
        });
      }
    },
  });
  backgroundOrderWatch = new BackgroundOrderWatch({
    providers: config.syncProviders,
    intervalMs: 45_000,
    isBusy: (provider) => reconcilingProviders.has(provider),
    runProvider: runWatchProvider,
    onPlatformResult: publishBackgroundCapture,
    prepare: refreshHistoryBeforeScan,
  });
  backgroundOrderWatch.start();
  if (config.mockOrders.enabled) {
    mockServer = new MockOrderServer({
      port: config.mockOrders.port,
      secret: config.mockOrders.secret,
      ingestor,
      onError: (error) =>
        sendState({ error: `Mock server: ${String(error.message || error)}` }),
    });
    await mockServer.start();
    sendState();
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
}).catch((error) => {
  console.error('Electron startup failed:', error);
  app.exit(1);
});

process.on('uncaughtException', (error) => {
  if (isBrokenPipe(error)) return;
  console.error('Unhandled main-process exception:', error);
});

process.on('unhandledRejection', (error) => {
  if (isBrokenPipe(error)) return;
  console.error('Unhandled main-process rejection:', error);
  sendState({ error: `Unhandled error: ${String(error?.message || error)}` });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  clearInterval(processedOrderSweep);
  for (const interceptor of platformNetworkInterceptors) interceptor.detach();
  backgroundOrderWatch?.stop();
  dailyReconciliationEngine?.stop();
  talabatIngestionService?.stop();
  queue?.stop();
  void mockServer?.stop();
});
