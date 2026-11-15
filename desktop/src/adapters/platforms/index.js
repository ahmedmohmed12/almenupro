'use strict';

const talabat = require('./talabat');
const keeta = require('./keeta');
const jahez = require('./jahez');

const adapters = {
  talabat,
  keeta,
  jahez,
};

function listPlatformTypes() {
  return Object.keys(adapters);
}

function getAdapter(type) {
  const key = String(type || '').trim().toLowerCase();
  const adapter = adapters[key === 'keta' ? 'keeta' : key];
  if (!adapter) {
    throw new Error(`Unsupported platform: ${type || 'unknown'}`);
  }
  return adapter;
}

module.exports = {
  getAdapter,
  listPlatformTypes,
};
