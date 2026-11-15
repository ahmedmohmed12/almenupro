'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  attachTalabatLiveDom,
  rowsFromMutationRecords,
} = require('../src/preload/talabat-live-dom');
const {
  focusTalabatTodayFilter,
  talabatRowShouldScan,
  talabatStatusRank,
} = require('../src/services/talabat-history-dom');

function row(id) {
  return {
    nodeType: 1,
    id,
    isConnected: true,
    matches(selector) {
      return String(selector).includes('tbody tr');
    },
    querySelectorAll() {
      return [];
    },
  };
}

test('mutation records keep inserted order rows and ignore text nodes', () => {
  const added = row('3947000111');
  const rows = rowsFromMutationRecords([
    { type: 'characterData', addedNodes: [row('1')] },
    { type: 'childList', addedNodes: [{ nodeType: 3 }, added] },
  ]);
  assert.deepEqual(rows, [added]);
});

function harness(invoke) {
  const sent = [];
  const table = {
    isConnected: true,
    querySelectorAll() {
      return [];
    },
  };
  const documentRef = {
    body: { isConnected: true },
    querySelector(selector) {
      return selector === 'table' ? table : null;
    },
  };
  let listObserver;
  class FakeObserver {
    constructor(callback) {
      this.callback = callback;
      listObserver ||= this;
    }
    observe() {}
    disconnect() {}
  }
  attachTalabatLiveDom({
    documentRef,
    getAdapter: () => ({
      selectors: { item: "[data-testid^='existing-product__']" },
      externalOrderId(node) {
        return node.id || '';
      },
      parseOrder(_node, externalOrderId) {
        return {
          platform: 'talabat',
          externalOrderId,
          items: [{ name: 'Meal', quantity: 1, unitPrice: 1 }],
        };
      },
    }),
    ipc: {
      invoke,
      send(channel, payload) {
        sent.push({ channel, payload });
      },
    },
    MutationObserverImpl: FakeObserver,
  });
  return { sent, listObserver };
}

test('a new Talabat row is dispatched when the 24-hour cache misses it', async () => {
  const { sent, listObserver } = harness(async () => ({ ids: ['3947000111'] }));
  listObserver.callback([{ type: 'childList', addedNodes: [row('3947000111')] }]);
  await new Promise((resolve) => setTimeout(resolve, 30));
  assert.equal(
    sent.some(
      (entry) =>
        entry.channel === 'scraper:orders' &&
        entry.payload[0].externalOrderId === '3947000111',
    ),
    true,
  );
  assert.equal(
    sent.some(
      (entry) =>
        entry.channel === 'scraper:parse-miss' &&
        entry.payload.reason === 'observed-row',
    ),
    true,
  );
});

function filterButton(text, attrs = {}) {
  return {
    textContent: text,
    clicked: false,
    getAttribute(name) {
      return attrs[name] || null;
    },
    classList: {
      contains(name) {
        return String(attrs.class || '').split(/\s+/).includes(name);
      },
    },
    click() {
      this.clicked = true;
    },
  };
}

test('Last 7 days switches to the Today tab when that tab is on the page', () => {
  const last7 = filterButton('Last 7 days', { 'aria-selected': 'true' });
  const today = filterButton('Today');
  const documentRef = { querySelectorAll: () => [last7, today] };
  assert.equal(focusTalabatTodayFilter(documentRef), 'clicked');
  assert.equal(today.clicked, true);
  assert.equal(last7.clicked, false);
});

test('a closed Last 7 days control opens so Today can be chosen', () => {
  const range = filterButton('Last 7 days');
  assert.equal(focusTalabatTodayFilter({ querySelectorAll: () => [range] }), 'opened');
  assert.equal(range.clicked, true);
});

test('Today stays selected when it is already the active range', () => {
  const today = filterButton('Today', { 'aria-selected': 'true' });
  assert.equal(focusTalabatTodayFilter({ querySelectorAll: () => [today] }), 'ready');
  assert.equal(today.clicked, false);
});

test('completed and delivered rows older than the session are ignored', () => {
  const now = new Date('2026-10-12T18:00:00+03:00');
  const session = new Date('2026-10-12T15:00:00+03:00');
  assert.equal(
    talabatRowShouldScan('3947000111 Yesterday, 10:00 COMPLETED', session, now),
    false,
  );
  assert.equal(
    talabatRowShouldScan('3947000111 Today, 14:00 DELIVERED', session, now),
    false,
  );
  assert.equal(
    talabatRowShouldScan('3947000111 Today, 15:10 DELIVERED', session, now),
    true,
  );
  assert.equal(
    talabatRowShouldScan('3947000111 Today, 09:00 ACCEPTED', session, now),
    true,
  );
  assert.ok(talabatStatusRank('PENDING order') < talabatStatusRank('PREPARING order'));
  assert.ok(talabatStatusRank('ACCEPTED order') < talabatStatusRank('COMPLETED order'));
  assert.ok(talabatStatusRank('PICKED UP order') < talabatStatusRank('DELIVERED order'));
});

test('a completed history row is not opened by the live observer', async () => {
  const stale = row('3947000222');
  stale.textContent = '3947000222 Yesterday, 10:00 COMPLETED';
  const { sent, listObserver } = harness(async () => ({ ids: ['3947000222'] }));
  listObserver.callback([{ type: 'childList', addedNodes: [stale] }]);
  await new Promise((resolve) => setTimeout(resolve, 30));
  assert.equal(sent.some((entry) => entry.channel === 'scraper:orders'), false);
});

test('a cached Talabat row is ignored before the invoice is opened', async () => {
  const { sent, listObserver } = harness(async () => ({ ids: [] }));
  listObserver.callback([{ type: 'childList', addedNodes: [row('3947000111')] }]);
  await new Promise((resolve) => setTimeout(resolve, 30));
  assert.equal(sent.some((entry) => entry.channel === 'scraper:orders'), false);
  assert.equal(
    sent.some(
      (entry) =>
        entry.channel === 'scraper:cache-skip' &&
        entry.payload.ids[0] === '3947000111',
    ),
    true,
  );
});
