'use strict';

const selectors = require('../../selectors/talabat.json');
const { parseOrderPayloads } = require('../../services/platform-order-network');

const origins = [
  'https://partner-app.talabat.com',
  'https://portal.talabat.com',
  'https://vendor-portal-api.deliveryhero.io',
];

function parsePayload(json) {
  return parseOrderPayloads('talabat', json);
}

function getSelectors() {
  return selectors;
}

module.exports = {
  type: 'talabat',
  displayName: 'Talabat',
  origins,
  parsePayload,
  getSelectors,
};
