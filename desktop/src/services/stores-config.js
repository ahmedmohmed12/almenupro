'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { getAdapter, listPlatformTypes } = require('../adapters/platforms');

function cleanId(value) {
  const id = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, '_')
    .slice(0, 40);
  if (!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(id)) {
    throw new Error('Store id must start with a letter or number');
  }
  return id;
}

function cleanName(value) {
  const name = String(value || '').replace(/\s+/g, ' ').trim().slice(0, 80);
  if (!name) throw new Error('Store name is required');
  return name;
}

function sanitizeStoreUrl(value) {
  let text = String(value || '').trim().replace(/^['"]+|['"]+$/g, '');
  const embedded = text.match(/https?:\/\/\S+/i);
  if (embedded) {
    text = embedded[0];
  } else {
    text = text.replace(/^\/+/, '');
    if (text && !/^https?:\/\//i.test(text)) text = `https://${text}`;
  }
  return text.replace(/[),.;]+$/g, '');
}

function cleanUrl(value, type) {
  let parsed;
  try {
    parsed = new URL(sanitizeStoreUrl(value));
  } catch {
    throw new Error('Store URL is invalid');
  }
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Store URL must use http or https');
  }
  const adapter = getAdapter(type);
  if (!adapter.origins.includes(parsed.origin)) {
    throw new Error(`URL origin is not allowed for ${adapter.displayName}`);
  }
  return parsed.toString();
}

function normalizeStore(raw, fallbackPartition) {
  const type = String(raw?.type || '').trim().toLowerCase();
  getAdapter(type);
  const id = cleanId(raw?.id);
  return {
    id,
    name: cleanName(raw?.name),
    type,
    url: cleanUrl(raw?.url, type),
    enabled: raw?.enabled !== false,
    partition: String(raw?.partition || fallbackPartition || `persist:${id}`).slice(0, 120),
  };
}

class StoresConfig {
  constructor({ filePath, defaults = [] } = {}) {
    if (!filePath) throw new TypeError('filePath is required');
    this.filePath = filePath;
    this.defaults = defaults;
    this.stores = [];
    this.load();
  }

  load() {
    try {
      const parsed = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
      const rows = Array.isArray(parsed) ? parsed : parsed?.stores;
      this.stores = (Array.isArray(rows) ? rows : []).map((row) => normalizeStore(row));
      const cleaned = this.stores.some((store, index) => store.url !== rows[index]?.url);
      if (cleaned) this.save();
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      this.stores = this.defaults.map((row) => normalizeStore(row));
      this.save();
    }
  }

  save() {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    const temporary = `${this.filePath}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify({ stores: this.stores }, null, 2));
    fs.renameSync(temporary, this.filePath);
  }

  list() {
    return this.stores.map((store) => ({ ...store }));
  }

  get(id) {
    const key = cleanId(id);
    const store = this.stores.find((entry) => entry.id === key);
    return store ? { ...store } : null;
  }

  add(input) {
    const type = String(input?.type || '').trim().toLowerCase();
    getAdapter(type);
    const id = input?.id
      ? cleanId(input.id)
      : cleanId(`store_${type}_${this.stores.length + 1}`);
    if (this.stores.some((store) => store.id === id)) {
      throw new Error(`Store ${id} already exists`);
    }
    const store = normalizeStore({ ...input, id, type });
    this.stores.push(store);
    this.save();
    return { ...store };
  }

  update(id, patch) {
    const key = cleanId(id);
    const index = this.stores.findIndex((store) => store.id === key);
    if (index < 0) throw new Error(`Store ${key} was not found`);
    const next = normalizeStore({ ...this.stores[index], ...patch, id: key });
    this.stores[index] = next;
    this.save();
    return { ...next };
  }

  remove(id) {
    const key = cleanId(id);
    const before = this.stores.length;
    this.stores = this.stores.filter((store) => store.id !== key);
    if (this.stores.length === before) throw new Error(`Store ${key} was not found`);
    this.save();
    return true;
  }
}

function registerStoreIpc(ipcMain, { manager, authorize, onChanged = () => {} }) {
  ipcMain.handle('list-stores', (event) => {
    if (!authorize(event)) throw new Error('Untrusted IPC sender');
    return manager.listStores();
  });
  ipcMain.handle('add-store', async (event, input) => {
    if (!authorize(event)) throw new Error('Untrusted IPC sender');
    const store = await manager.addStore(input);
    onChanged();
    return store;
  });
  ipcMain.handle('remove-store', async (event, id) => {
    if (!authorize(event)) throw new Error('Untrusted IPC sender');
    const removed = await manager.removeStore(id);
    onChanged();
    return removed;
  });
  ipcMain.handle('toggle-store-status', async (event, payload) => {
    if (!authorize(event)) throw new Error('Untrusted IPC sender');
    const store = await manager.toggleStore(payload?.id, payload?.enabled);
    onChanged();
    return store;
  });
}

module.exports = {
  StoresConfig,
  listPlatformTypes,
  normalizeStore,
  registerStoreIpc,
  sanitizeStoreUrl,
};
