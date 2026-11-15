'use strict';

class SyncEngine {
  constructor({
    providers,
    dispatch,
    intervalMs = 60_000,
    logger = console,
  }) {
    if (!Array.isArray(providers) || !providers.length || !dispatch) {
      throw new TypeError('providers and dispatch are required');
    }
    this.providers = [...providers];
    this.dispatch = dispatch;
    this.intervalMs = intervalMs;
    this.logger = logger;
    this.timer = null;
  }

  start() {
    if (this.timer) return;
    this.timer = setInterval(() => {
      void this.runCycle().catch((error) => {
        this.logger.error('[SyncEngine] cycle failed:', error);
      });
    }, this.intervalMs);
    this.timer.unref?.();
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
  }

  async runCycle() {
    const cycleId = `sync-${Date.now()}`;
    for (const provider of this.providers) {
      try {
        await this.dispatch(provider, { cycleId, limit: 5 });
      } catch (error) {
        this.logger.error(
          `[SyncEngine] ${provider} dispatch failed: ${String(
            error?.message || error,
          )}`,
        );
      }
    }
    return cycleId;
  }
}

module.exports = { SyncEngine };

class DailyReconciliationEngine extends SyncEngine {
  constructor(options) {
    super({ ...options, intervalMs: options.intervalMs ?? 15 * 60_000 });
    this.inFlight = false;
    this.startupTimer = null;
  }

  start() {
    if (this.timer) return;
    this.startupTimer = setTimeout(() => {
      void this.runCycle();
    }, 20_000);
    this.startupTimer.unref?.();
    super.start();
  }

  stop() {
    clearTimeout(this.startupTimer);
    this.startupTimer = null;
    super.stop();
  }

  async runCycle() {
    if (this.inFlight) return null;
    this.inFlight = true;
    try {
      return await super.runCycle();
    } finally {
      this.inFlight = false;
    }
  }
}

module.exports.DailyReconciliationEngine = DailyReconciliationEngine;
