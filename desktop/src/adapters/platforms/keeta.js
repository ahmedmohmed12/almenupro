'use strict';

const selectors = require('../../selectors/keeta.json');
const { parseOrderPayloads } = require('../../services/platform-order-network');

const origins = [
  'https://merchant.mykeeta.com',
  'https://merchant.keeta-global.com',
];

function parsePayload(json) {
  return parseOrderPayloads('keeta', json);
}

function getSelectors() {
  return selectors;
}

module.exports = {
  type: 'keeta',
  displayName: 'Keeta',
  origins,
  parsePayload,
  getSelectors,
};
