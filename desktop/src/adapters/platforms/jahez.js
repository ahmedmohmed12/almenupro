'use strict';

const selectors = require('../../selectors/jahez.json');
const { parseOrderPayloads } = require('../../services/platform-order-network');

const origins = ['https://portal.jahez.net'];

function parsePayload(json) {
  return parseOrderPayloads('jahez', json);
}

function getSelectors() {
  return selectors;
}

module.exports = {
  type: 'jahez',
  displayName: 'Jahez',
  origins,
  parsePayload,
  getSelectors,
};
