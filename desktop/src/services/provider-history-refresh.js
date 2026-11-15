'use strict';

const { normalizedPath } = require('./provider-order-router');

const DEFAULT_INTERVAL_MS = 60_000;

function sameHistorySurface(currentUrl, targetUrl) {
  try {
    const current = new URL(currentUrl);
    const target = new URL(targetUrl);
    return (
      current.origin === target.origin &&
      normalizedPath(currentUrl) === normalizedPath(targetUrl)
    );
  } catch {
    return false;
  }
}

class ProviderHistoryRefresh {
  constructor({
    providers,
    getView,
    historyUrlFor,
    shouldSkip = () => false,
    intervalMs = DEFAULT_INTERVAL_MS,
    logger = console,
  }) {
    if (!Array.isArray(providers) || !providers.length) {
      throw new TypeError('providers are required');
    }
    if (typeof getView !== 'function' || typeof historyUrlFor !== 'function') {
      throw new TypeError('getView and historyUrlFor are required');
    }
    this.providers = [...providers];
    this.getView = getView;
    this.historyUrlFor = historyUrlFor;
    this.shouldSkip = shouldSkip;
    this.intervalMs = Math.max(15_000, Number(intervalMs) || DEFAULT_INTERVAL_MS);
    this.logger = logger;
    this.timer = null;
  }

  start() {
    if (this.timer) return;
    this.timer = setInterval(() => {
      void this.runCycle();
    }, this.intervalMs);
    this.timer.unref?.();
    this.logger.info(
      `[History Refresh] every ${this.intervalMs}ms for ${this.providers.join(',')}`,
    );
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
  }

  async runCycle() {
    for (const provider of this.providers) {
      try {
        if (this.shouldSkip(provider)) continue;
        const view = this.getView(provider);
        if (!view || view.webContents?.isDestroyed?.()) continue;
        if (view.webContents.isLoadingMainFrame?.() || view.webContents.isLoading?.()) {
          continue;
        }
        const target = String(this.historyUrlFor(provider) || '').trim();
        if (!target) continue;
        const current = view.webContents.getURL();
        if (sameHistorySurface(current, target)) {
          view.webContents.reload();
        } else {
          await view.webContents.loadURL(target);
        }
        this.logger.info(`[History Refresh] ${provider} refreshed`);
      } catch (error) {
        this.logger.warn(
          `[History Refresh] ${provider} failed: ${String(
            error?.message || error,
          ).slice(0, 300)}`,
        );
      }
    }
  }
}

module.exports = {
  DEFAULT_INTERVAL_MS,
  ProviderHistoryRefresh,
  sameHistorySurface,
};
