'use strict';

const { ipcRenderer } = require('electron');
const { createAdapter } = require('../adapters/registry');
const { syncTopHistoryOrders, waitForDetail, waitForDetailClosed } = require('./history-sync');
const { attachTalabatLiveDom } = require('./talabat-live-dom');
const { reconcileKuwaitToday } = require('./daily-reconciliation');

function argument(name) {
  const prefix = `--${name}=`;
  const value = process.argv.find((entry) => entry.startsWith(prefix));
  return value ? decodeURIComponent(value.slice(prefix.length)) : '';
}

const provider = argument('scraper-provider');
let orderScreenUrls = [];
try {
  orderScreenUrls = JSON.parse(argument('scraper-order-urls') || '[]');
  if (!Array.isArray(orderScreenUrls)) orderScreenUrls = [];
} catch {
  orderScreenUrls = [];
}
let observer;
let scanTimer;
let historyTimer;
let navigationTimer;
let surfaceDiagnosticTimer;
let surfacePollTimer;
let orderHistoryClickTimer;
let adapter;
let historySyncInFlight = false;
let surfaceDiagnosticAttempts = 0;
let historySurfaceAttached = false;
let orderHistoryClickPending = false;
let talabatLive = null;
const reportedSurfaces = new Set();
const reportedParseMisses = new Set();

function reportParseMisses() {
  for (const miss of adapter?.parseMisses || []) {
    const key = `${miss.reason}:${miss.mode}:${miss.externalOrderId}`;
    if (reportedParseMisses.has(key)) continue;
    reportedParseMisses.add(key);
    ipcRenderer.send('scraper:parse-miss', { provider, ...miss });
  }
}

function alreadyOnPastOrders() {
  return /\/orders\/history|order_history|past-orders|previous-orders/i.test(
    location.href,
  );
}

function openPastOrdersView() {
  if (alreadyOnPastOrders()) return false;
  const label =
    /^(order history|orders history|past orders|previous orders|الطلبات السابقة|سجل الطلبات|تاريخ الطلبات|الطلبات الماضية)$/i;
  const node = Array.from(
    document.querySelectorAll(
      "a, button, [role='tab'], [role='link'], [role='menuitem']",
    ),
  ).find((element) => {
    const text = String(element.textContent || '').replace(/\s+/g, ' ').trim();
    const href = String(element.getAttribute?.('href') || '');
    return (
      (text.length > 0 && text.length <= 40 && label.test(text)) ||
      /\/orders\/history|order_history/i.test(href)
    );
  });
  if (typeof node?.click === 'function') {
    ipcRenderer.send('scraper:observer-status', {
      provider,
      status: 'navigating',
    });
    node.click();
    return true;
  }
  return clickOrderHistoryNavigation();
}

function clickOrderHistoryNavigation() {
  if (
    orderHistoryClickPending ||
    provider !== 'talabat' ||
    !['/', '/dashboard'].includes(location.pathname.replace(/\/+$/, '') || '/')
  ) {
    return false;
  }
  const direct = document.querySelector(
    "a[href='/orders/history'], a[href$='/orders/history']",
  );
  const textMatch =
    direct ||
    Array.from(
      document.querySelectorAll("a, button, [role='link'], [role='menuitem']"),
    ).find((node) =>
      /^(order history|orders history|سجل الطلبات|تاريخ الطلبات)$/i.test(
        String(node.textContent || '').replace(/\s+/g, ' ').trim(),
      ),
    );
  if (typeof textMatch?.click !== 'function') {
    const dashboardReady = document.querySelector(
      "[data-testid='dashboard-root'], [data-testid='app-shell'], nav, aside",
    );
    if (!dashboardReady) return false;
    orderHistoryClickPending = true;
    ipcRenderer.send('scraper:observer-status', {
      provider,
      status: 'navigating',
    });
    history.pushState({}, '', '/orders/history');
    window.dispatchEvent(new PopStateEvent('popstate'));
    clearTimeout(orderHistoryClickTimer);
    orderHistoryClickTimer = setTimeout(() => {
      orderHistoryClickPending = false;
    }, 5000);
    return true;
  }
  ipcRenderer.send('scraper:observer-status', {
    provider,
    status: 'navigating',
  });
  orderHistoryClickPending = true;
  clearTimeout(orderHistoryClickTimer);
  orderHistoryClickTimer = setTimeout(() => {
    orderHistoryClickPending = false;
  }, 5000);
  textMatch.click();
  return true;
}

function visibleLoadingIndicator(root = document) {
  return Array.from(
    root.querySelectorAll(
      "[data-testid='centered-circular-progress'], [data-testid*='loading' i], [data-testid*='shimmer' i], [role='progressbar'], .loading, .spinner",
    ),
  ).some((node) => {
    if (typeof node.getClientRects === 'function' && !node.getClientRects().length) {
      return false;
    }
    const style = getComputedStyle(node);
    return style.display !== 'none' && style.visibility !== 'hidden';
  });
}

function reportAttachedSurfaces() {
  for (const surface of adapter.orderSurfaceIds()) {
    if (reportedSurfaces.has(surface)) continue;
    reportedSurfaces.add(surface);
    ipcRenderer.send('scraper:surface-ready', { provider, surface });
  }
}

function attachObserverToCurrentRoots() {
  if (provider === 'talabat') {
    // Talabat rows are ingested by the live table observer, not a timed rescan.
    if (!talabatLive) {
      talabatLive = attachTalabatLiveDom({
        documentRef: document,
        getAdapter: () => adapter,
        ipc: ipcRenderer,
        isBusy: () => historySyncInFlight,
        waitForDetail,
        waitForDetailClosed,
      });
    } else {
      talabatLive.rebind();
    }
    return;
  }
  const roots = adapter.observationRoots();
  if (!roots.length) {
    throw new Error('Could not find a safe DOM observation root');
  }
  observer ||= new MutationObserver(scan);
  observer.disconnect();
  for (const root of roots) {
    observer.observe(root, {
      childList: true,
      subtree: true,
      characterData: true,
    });
  }
}

function dismissNotificationPrompt() {
  if (provider !== 'talabat') return false;
  const title = Array.from(
    document.querySelectorAll('h1, h2, h3, h4, h5, h6, p, span, div, [role="heading"]'),
  ).find((node) => {
    const text = String(node.textContent || '').replace(/\s+/g, ' ').trim();
    return text.length > 0 && text.length <= 80 && /please allow notifications/i.test(text);
  });
  if (!title) return false;
  let scope = title;
  for (let depth = 0; scope && depth < 10; depth += 1) {
    const button = Array.from(scope.querySelectorAll?.('button, [role="button"]') || []).find(
      (node) => /^got it$/i.test(String(node.textContent || '').replace(/\s+/g, ' ').trim()),
    );
    if (typeof button?.click === 'function') {
      button.click();
      ipcRenderer.send('scraper:observer-status', {
        provider,
        status: 'notification-prompt-dismissed',
      });
      return true;
    }
    scope = scope.parentElement;
  }
  return false;
}

function pollForHistorySurface() {
  clearTimeout(surfacePollTimer);
  if (!adapter) return;
  dismissNotificationPrompt();
  if (clickOrderHistoryNavigation()) {
    surfacePollTimer = setTimeout(pollForHistorySurface, 1500);
    return;
  }
  const surfaces = adapter.orderSurfaceIds();
  const historyMode = adapter
    .observationModes()
    .find((entry) => entry.id === 'history');
  const historyRoot =
    historyMode?.root && document.querySelector(historyMode.root);
  const spinner = visibleLoadingIndicator(historyRoot || document);
  const onTalabatHistoryPath = /\/orders\/history\/?$/i.test(location.pathname);
  const ready =
    !spinner &&
    (provider === 'talabat' ? onTalabatHistoryPath : alreadyOnPastOrders() || surfaces.length > 0);
  if (
    provider === 'talabat' &&
    /\/orders\/history/i.test(location.pathname) &&
    typeof adapter.ensureTodayFilter === 'function'
  ) {
    const today = adapter.ensureTodayFilter();
    if (today === 'clicked' || today === 'opened') {
      ipcRenderer.send('scraper:observer-status', {
        provider,
        status: 'today-filter',
        result: today,
      });
      if (today === 'opened') {
        setTimeout(() => adapter.ensureTodayFilter(), 400);
      }
    }
  }
  if (ready) {
    if (!historySurfaceAttached) {
      historySurfaceAttached = true;
      attachObserverToCurrentRoots();
      ipcRenderer.send('scraper:observer-status', {
        provider,
        status: 'attached',
        surface: provider === 'talabat' ? 'history' : surfaces[0],
      });
      reportAttachedSurfaces();
    } else if (provider === 'talabat') {
      talabatLive?.rebind();
    }
    if (provider === 'talabat') {
      surfacePollTimer = setTimeout(pollForHistorySurface, 2000);
    }
    return;
  }
  ipcRenderer.send('scraper:observer-status', {
    provider,
    status: 'waiting',
    spinner,
    path: location.pathname,
  });
  surfacePollTimer = setTimeout(pollForHistorySurface, 1500);
}

function scheduleSurfaceDiagnostic() {
  clearTimeout(surfaceDiagnosticTimer);
  surfaceDiagnosticTimer = setTimeout(() => {
    if (adapter.orderSurfaceIds().length) return;
    const candidates = Array.from(
      document.querySelectorAll(
        "table, [role='grid'], [role='table'], [data-testid], [class*='order' i]",
      ),
    )
      .slice(0, 30)
      .map((node) => ({
        tag: node.tagName,
        role: node.getAttribute('role') || '',
        testId: node.getAttribute('data-testid') || '',
        className: String(node.className || '').slice(0, 160),
      }));
    ipcRenderer.send('scraper:surface-diagnostic', {
      provider,
      path: location.pathname,
      candidates,
    });
    surfaceDiagnosticAttempts += 1;
    if (surfaceDiagnosticAttempts < 3) scheduleSurfaceDiagnostic();
  }, 4000);
}

function scheduleNavigationFallback() {
  clearTimeout(navigationTimer);
  // Talabat must establish its authenticated SPA session on the main portal.
  // A direct loadURL to a deep order route aborts that bootstrap navigation.
  if (provider === 'talabat') return;
  if (
    !orderScreenUrls.length ||
    !adapter?.hasAuthenticatedSurface() ||
    adapter.hasOrderSurface()
  ) {
    return;
  }
  navigationTimer = setTimeout(() => {
    if (!adapter.hasOrderSurface()) {
      ipcRenderer.send('scraper:navigate-fallback', {
        provider,
        candidates: orderScreenUrls.slice(0, 5),
      });
    }
  }, 5000);
}

function scan() {
  clearTimeout(scanTimer);
  scanTimer = setTimeout(() => {
    void publishUncachedScan().catch((error) => {
      ipcRenderer.send('scraper:error', {
        provider,
        message: String(error.message || error).slice(0, 500),
      });
    });
  }, 400);
}

async function publishUncachedScan() {
  if (clickOrderHistoryNavigation()) return;
  reportAttachedSurfaces();
  const orders = adapter.scan({ includeHistory: false }).slice(0, 100);
  reportParseMisses();
  scheduleNavigationFallback();
  if (!orders.length) return;
  let fresh = orders;
  try {
    const result = await ipcRenderer.invoke(
      'orders:unprocessed',
      orders.map((order) => order.externalOrderId),
    );
    const allowed = new Set(Array.isArray(result?.ids) ? result.ids : []);
    const skipped = orders.filter((order) => !allowed.has(order.externalOrderId));
    if (skipped.length) {
      ipcRenderer.send('scraper:cache-skip', {
        provider,
        source: 'scan',
        ids: skipped.map((order) => order.externalOrderId),
      });
    }
    fresh = orders.filter((order) => allowed.has(order.externalOrderId));
  } catch {
    fresh = orders;
  }
  if (fresh.length) ipcRenderer.send('scraper:orders', fresh);
}

async function executeHistorySync(
  limit = 3,
  { refreshExisting = false, onlyMissing = false, kuwaitTodayOnly = false } = {},
) {
  if (historySyncInFlight || !adapter) {
    return { checked: 0, skipped: 0, ingested: 0, failed: 0, busy: true };
  }
  historySyncInFlight = true;
  try {
    return await syncTopHistoryOrders({
      adapter,
      ipc: ipcRenderer,
      limit,
      refreshExisting,
      onlyMissing,
      kuwaitTodayOnly,
    });
  } finally {
    historySyncInFlight = false;
  }
}

function scheduleHistorySync(delayMs = 900) {
  clearTimeout(historyTimer);
  historyTimer = setTimeout(() => {
    void executeHistorySync().catch((error) => {
      ipcRenderer.send('scraper:error', {
        provider,
        message: `Order history sync failed: ${String(
          error.message || error,
        ).slice(0, 400)}`,
      });
    });
  }, delayMs);
}

function wait(delayMs) {
  return new Promise((resolve) => setTimeout(resolve, delayMs));
}

function onHistoryPage() {
  if (alreadyOnPastOrders()) return true;
  return provider === 'talabat' && /\/orders\/history\/?$/i.test(location.pathname);
}

async function waitForHistorySurface(timeoutMs = 12_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (portalBlocksHistory()) return false;
    const loading = visibleLoadingIndicator(document);
    const renderedRows = onHistoryPage() ? adapter?.historyRows(8) || [] : [];
    const hasIdentifiedOrder = renderedRows.some((row) =>
      Boolean(adapter?.externalOrderId(row)),
    );
    if (onHistoryPage() && !loading && hasIdentifiedOrder) return true;
    if (!onHistoryPage()) openPastOrdersView();
    await wait(400);
  }
  return onHistoryPage() && !portalBlocksHistory();
}

async function runBackgroundSyncCycle(payload) {
  ipcRenderer.send('scraper:sync-cycle-result', {
    cycleId: String(payload?.cycleId || '').slice(0, 100),
    checked: 0,
    skipped: 0,
    ingested: 0,
    failed: 0,
  });
}

function portalBlocksHistory() {
  const href = String(location.href || '');
  const path = String(location.pathname || '');
  const text = String(document.body?.innerText || '').replace(/\s+/g, ' ').slice(0, 800);
  return (
    /login|sign-?in|restaurant-login|تسجيل الدخول/i.test(`${href} ${path}`) ||
    (/تسجيل الدخول|sign in|log in/i.test(text) && !(adapter?.historyRows(1).length))
  );
}

async function runDailyReconciliation(payload) {
  const cycleId = String(payload?.cycleId || '').slice(0, 100);
  const reportDom = (info) => {
    const ids = Array.isArray(info?.ids) ? info.ids : [];
    const label = provider.charAt(0).toUpperCase() + provider.slice(1);
    console.log(`${label} DOM found IDs:`, ids.length);
    console.log(`[${provider} Scraped IDs]: ${JSON.stringify(ids)}`);
    ipcRenderer.send('scraper:sync-diagnostic', {
      provider,
      cycleId,
      href: String(info?.href || location.href || ''),
      path: String(info?.path || location.pathname || ''),
      title: String(info?.title || document.title || ''),
      visibility: String(info?.visibility || document.visibilityState || ''),
      historyPage: Boolean(info?.historyPage),
      loginWall: Boolean(info?.loginWall),
      containerFound: Boolean(info?.containerFound),
      containerText: String(info?.containerText || '').slice(0, 2500),
      containerHtml: String(info?.containerHtml || '').slice(0, 2500),
      rowCount: Number(info?.rowCount) || ids.length,
      ids,
    });
  };
  try {
    console.log(
      `[${provider}] sync url=${location.href} visibility=${document.visibilityState} hidden=${document.hidden} title=${document.title}`,
    );
    if (portalBlocksHistory()) {
      ipcRenderer.send('scraper:reconciliation-result', {
        cycleId,
        checked: 0,
        ingested: 0,
        unread: true,
        loginWall: true,
        historyPage: false,
        scanReliable: false,
        alert: 'table_missing',
        error: 'history_unread',
      });
      return;
    }
    if (!(await waitForHistorySurface(12_000))) {
      const unread = new Error('Order History table was not rendered');
      unread.unread = true;
      throw unread;
    }
    openPastOrdersView();
    historySyncInFlight = true;
    const summary = await reconcileKuwaitToday({
      adapter,
      ipc: ipcRenderer,
      maxOrders: Math.max(5, Math.min(500, Number(payload?.limit) || 500)),
      onProgress: (progress) => {
        ipcRenderer.send('scraper:sync-progress', {
          cycleId,
          provider,
          checked: Number(progress?.checked) || 0,
          synced: Number(progress?.ingested) || 0,
        });
      },
      onDiagnostic: reportDom,
    });
    const scrapedIds = Array.isArray(summary.liveOrderIds) ? summary.liveOrderIds : [];
    const label = provider.charAt(0).toUpperCase() + provider.slice(1);
    console.log(`${label} DOM found IDs:`, scrapedIds.length);
    if (provider === 'talabat') {
      console.log('Talabat Scraped Today IDs:', scrapedIds);
    }
    if (provider === 'keeta') {
      console.log('Keeta Scraped Today IDs:', scrapedIds);
    }
    if (!scrapedIds.length) {
      summary.unread = true;
      summary.scanReliable = false;
      summary.alert = adapter?.historyContainer?.() ? 'no_order_ids' : 'table_missing';
      summary.error = summary.alert;
    }
    ipcRenderer.send('scraper:reconciliation-result', {
      cycleId,
      ...summary,
    });
  } catch (error) {
    ipcRenderer.send('scraper:reconciliation-result', {
      cycleId,
      checked: 0,
      ingested: 0,
      unread: true,
      scanReliable: false,
      alert: 'table_missing',
      error: String(error?.message || error).slice(0, 300),
    });
  } finally {
    historySyncInFlight = false;
  }
}

function start() {
  try {
    observer?.disconnect();
    adapter = createAdapter(provider, document);
    attachObserverToCurrentRoots();
    scan();
    pollForHistorySurface();
    scheduleSurfaceDiagnostic();
  } catch (error) {
    ipcRenderer.send('scraper:error', {
      provider,
      message: String(error.message || error).slice(0, 500),
    });
  }
}

ipcRenderer.on('scraper:run-history-sync', (_event, payload) => {
  void runBackgroundSyncCycle(payload);
});
ipcRenderer.on('scraper:run-daily-reconciliation', (_event, payload) => {
  void runDailyReconciliation(payload);
});
ipcRenderer.send('scraper:preload-ready', { provider });

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', start, { once: true });
} else {
  start();
}

window.addEventListener('pagehide', () => {
  observer?.disconnect();
  talabatLive?.disconnect();
  talabatLive = null;
  clearTimeout(scanTimer);
  clearTimeout(historyTimer);
  clearTimeout(navigationTimer);
  clearTimeout(surfaceDiagnosticTimer);
  clearTimeout(surfacePollTimer);
  clearTimeout(orderHistoryClickTimer);
});
