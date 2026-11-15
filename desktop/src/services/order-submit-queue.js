'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { EventEmitter } = require('node:events');

class OrderSubmitQueue extends EventEmitter {
  constructor({
    filePath,
    apiUrl,
    apiToken,
    fetchImpl = globalThis.fetch,
    baseRetryMs = 5_000,
  }) {
    super();
    this.filePath = filePath;
    this.endpoint = `${apiUrl.replace(/\/$/, '')}/v1/orders/external`;
    this.apiToken = apiToken;
    this.fetchImpl = fetchImpl;
    this.baseRetryMs = baseRetryMs;
    this.records = [];
    this.processing = false;
    this.timer = null;
    this.load();
  }

  load() {
    try {
      const data = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
      this.records = Array.isArray(data.records) ? data.records : [];
    } catch (error) {
      if (error.code !== 'ENOENT') {
        console.warn('Could not load order queue:', error.message);
      }
    }
  }

  enqueue({ key, restaurantId, order }) {
    if (this.records.some((record) => record.key === key)) return false;
    this.records.push({
      key,
      restaurantId,
      order,
      attempts: 0,
      nextAttemptAt: Date.now(),
      status: 'pending',
      createdAt: new Date().toISOString(),
    });
    this.persist();
    this.schedule(0);
    this.emitStatus();
    return true;
  }

  start() {
    this.schedule(0);
  }

  stop() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }

  schedule(delayMs) {
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = null;
      this.process().catch((error) => {
        console.error('Order queue processing failed:', error);
        this.schedule(this.baseRetryMs);
      });
    }, Math.max(0, delayMs));
  }

  async process() {
    if (this.processing) return;
    this.processing = true;
    try {
      const now = Date.now();
      const record = this.records.find(
        (candidate) =>
          candidate.status === 'pending' && candidate.nextAttemptAt <= now,
      );
      if (!record) return;
      await this.submit(record);
      await this.process();
    } finally {
      this.processing = false;
      this.scheduleNext();
      this.emitStatus();
    }
  }

  async submit(record) {
    try {
      const headers = {
        'Content-Type': 'application/json',
        'X-Restaurant-Id': record.restaurantId,
      };
      if (this.apiToken) headers.Authorization = `Bearer ${this.apiToken}`;
      const response = await this.fetchImpl(this.endpoint, {
        method: 'POST',
        headers,
        body: JSON.stringify(record.order),
        signal: AbortSignal.timeout(20_000),
      });
      if (response.ok) {
        this.records = this.records.filter((item) => item.key !== record.key);
        this.persist();
        return;
      }

      const retriable =
        response.status === 401 ||
        response.status === 403 ||
        response.status === 408 ||
        response.status === 429 ||
        response.status >= 500;
      if (!retriable) {
        record.status = 'failed';
        record.lastError = `HTTP ${response.status}`;
        this.persist();
        return;
      }
      throw new Error(`HTTP ${response.status}`);
    } catch (error) {
      record.attempts += 1;
      record.lastError = String(error.message || error).slice(0, 300);
      const delay = Math.min(
        15 * 60_000,
        this.baseRetryMs * 2 ** Math.min(record.attempts - 1, 8),
      );
      record.nextAttemptAt = Date.now() + delay;
      this.persist();
    }
  }

  scheduleNext() {
    const next = this.records
      .filter((record) => record.status === 'pending')
      .reduce(
        (minimum, record) => Math.min(minimum, record.nextAttemptAt),
        Infinity,
      );
    if (Number.isFinite(next)) this.schedule(Math.max(0, next - Date.now()));
  }

  status() {
    return {
      pending: this.records.filter((record) => record.status === 'pending').length,
      failed: this.records.filter((record) => record.status === 'failed').length,
    };
  }

  emitStatus() {
    this.emit('status', this.status());
  }

  persist() {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    const temporary = `${this.filePath}.tmp`;
    fs.writeFileSync(
      temporary,
      JSON.stringify({ version: 1, records: this.records }, null, 2),
      { encoding: 'utf8', mode: 0o600 },
    );
    fs.renameSync(temporary, this.filePath);
  }
}

module.exports = { OrderSubmitQueue };
