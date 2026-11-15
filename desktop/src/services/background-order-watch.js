'use strict';

const { runIsolatedPlatformSync } = require('./sync-orchestrator');

class BackgroundOrderWatch {
  constructor({
    providers,
    intervalMs = 45_000,
    isBusy = () => false,
    runProvider,
    onPlatformResult,
    prepare,
    logger = console,
  }) {
    if (!Array.isArray(providers) || !providers.length) {
      throw new TypeError('providers are required');
    }
    if (typeof runProvider !== 'function') {
      throw new TypeError('runProvider is required');
    }
    this.providers = [...providers];
    this.intervalMs = Math.min(60_000, Math.max(30_000, Number(intervalMs) || 45_000));
    this.isBusy = isBusy;
    this.runProvider = runProvider;
    this.onPlatformResult = onPlatformResult;
    this.prepare = prepare;
    this.logger = logger;
    this.timer = null;
    this.startupTimer = null;
    this.mutationTimers = new Map();
    this.lastStarted = new Map();
    this.running = false;
    this.readyAt = 0;
    this.stopped = false;
  }

  start() {
    if (this.timer || this.stopped) return;
    this.stopped = false;
    this.timer = setTimeout(() => {
      void this.loop();
    }, 8_000);
    this.timer.unref?.();
    this.logger.info(
      `[Order Watch] every ${this.intervalMs}ms after each finished pass for ${this.providers.join(',')}`,
    );
  }

  stop() {
    this.stopped = true;
    clearTimeout(this.timer);
    clearTimeout(this.startupTimer);
    for (const timer of this.mutationTimers.values()) clearTimeout(timer);
    this.mutationTimers.clear();
    this.startupTimer = null;
    this.timer = null;
  }

  async loop() {
    if (this.stopped) return;
    try {
      if (typeof this.prepare === 'function') await this.prepare();
      if (!this.stopped) await this.runCycle();
    } catch (error) {
      this.logger.warn(
        `[Order Watch] pass failed: ${String(error?.message || error).slice(0, 200)}`,
      );
    }
    if (this.stopped) return;
    this.timer = setTimeout(() => {
      void this.loop();
    }, this.intervalMs);
    this.timer.unref?.();
  }

  nudge(provider) {
    if (Date.now() < this.readyAt) return;
    if (!this.providers.includes(provider)) return;
    if (this.isBusy(provider)) return;
    const last = this.lastStarted.get(provider) || 0;
    if (Date.now() - last < 20_000) return;
    clearTimeout(this.mutationTimers.get(provider));
    const timer = setTimeout(() => {
      this.mutationTimers.delete(provider);
      if (this.isBusy(provider)) return;
      this.lastStarted.set(provider, Date.now());
      void runIsolatedPlatformSync({
        providers: [provider],
        runProvider: this.runProvider,
        onPlatformResult: (row) => {
          if (typeof this.onPlatformResult === 'function') this.onPlatformResult(row);
        },
        logger: this.logger,
      }).catch((error) => {
        this.logger.warn(
          `[Order Watch] ${provider} mutation scan failed: ${String(
            error?.message || error,
          ).slice(0, 200)}`,
        );
      });
    }, 5_000);
    timer.unref?.();
    this.mutationTimers.set(provider, timer);
  }

  async runCycle() {
    if (this.running) return null;
    const ready = this.providers.filter((provider) => !this.isBusy(provider));
    if (!ready.length) return null;
    this.running = true;
    const startedAt = Date.now();
    for (const provider of ready) this.lastStarted.set(provider, startedAt);
    try {
      return await runIsolatedPlatformSync({
        providers: ready,
        runProvider: this.runProvider,
        onPlatformResult: (row) => {
          if (typeof this.onPlatformResult === 'function') this.onPlatformResult(row);
        },
        logger: this.logger,
      });
    } finally {
      this.running = false;
    }
  }
}

module.exports = { BackgroundOrderWatch };
