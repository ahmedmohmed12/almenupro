'use strict';

const { getAdapter } = require('../adapters/platforms');

const configuredSessions = new WeakSet();

function chromeDesktopUserAgent() {
  const chrome = process.versions.chrome || '131.0.0.0';
  return `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${chrome} Safari/537.36`;
}

function chromeClientHint(userAgent) {
  const major = userAgent.match(/Chrome\/(\d+)/)?.[1] || '131';
  return `"Google Chrome";v="${major}", "Chromium";v="${major}", "Not_A Brand";v="24"`;
}

/**
 * Makes a portal partition present as desktop Chrome. Electron's default
 * user agent includes an Electron token, which merchant portals challenge.
 */
function configurePortalSession(electronSession) {
  const userAgent = chromeDesktopUserAgent();
  if (!electronSession || configuredSessions.has(electronSession)) return userAgent;
  configuredSessions.add(electronSession);
  electronSession.setUserAgent(userAgent);
  const hint = chromeClientHint(userAgent);
  electronSession.webRequest.onBeforeSendHeaders(
    { urls: ['<all_urls>'] },
    (details, callback) => {
      const headers = details.requestHeaders;
      headers['User-Agent'] = userAgent;
      if (headers['Sec-CH-UA']) headers['Sec-CH-UA'] = hint;
      if (headers['sec-ch-ua']) headers['sec-ch-ua'] = hint;
      callback({ requestHeaders: headers });
    },
  );
  return userAgent;
}

function applyPortalUserAgent(webContents) {
  if (!webContents || webContents.isDestroyed?.()) return '';
  const userAgent = configurePortalSession(webContents.session);
  webContents.setUserAgent(userAgent);
  const major = userAgent.match(/Chrome\/(\d+)/)?.[1] || '131';
  const fullVersion = process.versions.chrome || `${major}.0.0.0`;
  const script = `(() => {
    const ua = ${JSON.stringify(userAgent)};
    const brands = [
      { brand: 'Chromium', version: '${major}' },
      { brand: 'Google Chrome', version: '${major}' },
      { brand: 'Not_A Brand', version: '24' },
    ];
    const data = {
      brands,
      mobile: false,
      platform: 'Windows',
      toJSON() { return { brands, mobile: false, platform: 'Windows' }; },
      getHighEntropyValues() {
        return Promise.resolve({
          brands,
          fullVersionList: brands,
          mobile: false,
          platform: 'Windows',
          architecture: 'x86',
          bitness: '64',
          model: '',
          platformVersion: '15.0.0',
          uaFullVersion: ${JSON.stringify(fullVersion)},
        });
      },
    };
    const define = (key, getter) => {
      try {
        Object.defineProperty(Navigator.prototype, key, { get: getter, configurable: true });
      } catch (_) {}
    };
    define('userAgent', () => ua);
    define('appVersion', () => ua.replace(/^Mozilla\\//, ''));
    define('vendor', () => 'Google Inc.');
    define('userAgentData', () => data);
  })();`;
  const apply = () => {
    if (webContents.isDestroyed()) return;
    webContents.executeJavaScript(script, true).catch(() => {});
  };
  webContents.on('dom-ready', apply);
  return userAgent;
}

/**
 * Opens one isolated portal view for every enabled store and tears it down
 * when that store is disabled or removed. The view factory owns Electron;
 * this class owns the store lifecycle.
 */
class StoreLifecycleManager {
  constructor({ storeConfig, viewFactory, logger = console } = {}) {
    if (!storeConfig || typeof viewFactory !== 'function') {
      throw new TypeError('storeConfig and viewFactory are required');
    }
    this.storeConfig = storeConfig;
    this.viewFactory = viewFactory;
    this.handles = new Map();
    this.logger = logger;
  }

  listStores() {
    return this.storeConfig.list();
  }

  getStore(id) {
    return this.storeConfig.get(id);
  }

  storeForType(type) {
    return (
      this.listStores().find((store) => store.enabled && store.type === type) || null
    );
  }

  start() {
    const spawned = [];
    for (const store of this.storeConfig.list()) {
      if (!store.enabled) continue;
      spawned.push(this.spawn(store));
    }
    return spawned;
  }

  spawn(store) {
    const adapter = getAdapter(store.type);
    if (this.handles.has(store.id)) return this.handles.get(store.id);
    const handle = this.viewFactory(store, adapter);
    this.handles.set(store.id, handle);
    this.logger.info(
      `[Stores] ${store.name} (${store.type}) view started partition=${store.partition}`,
    );
    return handle;
  }

  stop(id) {
    const handle = this.handles.get(id);
    if (!handle) return false;
    this.handles.delete(id);
    handle.destroy();
    this.logger.info(`[Stores] ${id} view stopped`);
    return true;
  }

  async addStore(input) {
    const store = this.storeConfig.add(input);
    if (store.enabled) this.spawn(store);
    return store;
  }

  async removeStore(id) {
    this.stop(String(id || ''));
    this.storeConfig.remove(id);
    return { id: String(id || ''), removed: true };
  }

  async toggleStore(id, enabled) {
    const store = this.storeConfig.update(id, { enabled: Boolean(enabled) });
    if (store.enabled) this.spawn(store);
    else this.stop(store.id);
    return store;
  }
}

function stampStoreOrder(order, store) {
  if (!order || !store) return order;
  return {
    ...order,
    store_id: store.id,
    store_name: store.name,
    platform_type: store.type,
  };
}

module.exports = {
  StoreLifecycleManager,
  applyPortalUserAgent,
  chromeDesktopUserAgent,
  configurePortalSession,
  stampStoreOrder,
};
