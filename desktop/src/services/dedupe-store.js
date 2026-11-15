'use strict';

const fs = require('node:fs');
const path = require('node:path');

class DedupeStore {
  constructor(filePath, { maxEntries = 20_000, maxAgeMs = 90 * 86400000 } = {}) {
    this.filePath = filePath;
    this.maxEntries = maxEntries;
    this.maxAgeMs = maxAgeMs;
    this.entries = new Map();
    this.load();
  }

  load() {
    try {
      const data = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
      const cutoff = Date.now() - this.maxAgeMs;
      for (const [key, timestamp] of Object.entries(data.entries || {})) {
        if (Number(timestamp) >= cutoff) this.entries.set(key, Number(timestamp));
      }
    } catch (error) {
      if (error.code !== 'ENOENT') {
        console.warn('Could not load scraper dedupe state:', error.message);
      }
    }
  }

  has(key) {
    return this.entries.has(key);
  }

  add(key) {
    this.entries.set(key, Date.now());
    if (this.entries.size > this.maxEntries) {
      const oldest = [...this.entries.entries()]
        .sort((a, b) => a[1] - b[1])
        .slice(0, this.entries.size - this.maxEntries);
      for (const [entryKey] of oldest) this.entries.delete(entryKey);
    }
    this.persist();
  }

  persist() {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    const temporary = `${this.filePath}.tmp`;
    fs.writeFileSync(
      temporary,
      JSON.stringify({ version: 1, entries: Object.fromEntries(this.entries) }),
      { encoding: 'utf8', mode: 0o600 },
    );
    fs.renameSync(temporary, this.filePath);
  }
}

module.exports = { DedupeStore };
