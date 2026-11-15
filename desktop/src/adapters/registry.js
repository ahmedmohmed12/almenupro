'use strict';

const { TalabatAdapter } = require('./talabat-adapter');
const { JahezAdapter } = require('./jahez-adapter');
const { KetaAdapter } = require('./keta-adapter');

const adapters = new Map([
  ['talabat', TalabatAdapter],
  ['jahez', JahezAdapter],
  ['keeta', KetaAdapter],
  ['keta', KetaAdapter],
]);

function createAdapter(platform, document) {
  const Adapter = adapters.get(String(platform || '').toLowerCase());
  if (!Adapter) throw new Error(`Unsupported scraper provider: ${platform}`);
  return new Adapter(document);
}

function supportedProviders() {
  return [...new Set(adapters.keys())];
}

module.exports = { createAdapter, supportedProviders };
