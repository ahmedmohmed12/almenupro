'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { syncTopHistoryOrders } = require('../src/preload/history-sync');

test('history sync skips existing IDs, opens missing rows, and only checks top three', async () => {
  const clicked = [];
  const closed = [];
  const prepared = [];
  let activeId = '';
  const rows = ['T-1', 'T-2', 'T-3', 'T-4'].map((id) => ({
    id,
    click() {
      activeId = id;
      clicked.push(id);
    },
  }));
  const sent = [];
  const adapter = {
    platform: 'talabat',
    historyRows(limit) {
      return rows.slice(0, limit);
    },
    externalOrderId(row) {
      return row.id;
    },
    detailRoot() {
      return activeId ? { id: activeId } : null;
    },
    async prepareOrderDetail(detail) {
      prepared.push(detail.id);
    },
    parseOrder(detail, externalOrderId) {
      return {
        platform: 'talabat',
        externalOrderId,
        items: [{ name: `Item for ${detail.id}`, quantity: 1, unitPrice: 10 }],
      };
    },
    detailCloseButton() {
      return {
        click() {
          closed.push(activeId);
          activeId = '';
        },
      };
    },
  };
  const ipc = {
    async invoke(channel, ids) {
      if (channel === 'orders:processed-ids') return { ids: [] };
      assert.equal(channel, 'scraper:check-order-ids');
      assert.deepEqual(ids, ['T-1', 'T-2', 'T-3']);
      return { existing: ['T-1'], missing: ['T-2', 'T-3'] };
    },
    send(channel, payload) {
      sent.push({ channel, payload });
    },
  };

  const result = await syncTopHistoryOrders({ adapter, ipc });

  assert.deepEqual(result, {
    checked: 3,
    skipped: 1,
    ingested: 2,
    failed: 0,
    ingestedIds: ['T-2', 'T-3'],
    customersUpdated: 0,
  });
  assert.deepEqual(clicked, ['T-2', 'T-3']);
  assert.deepEqual(prepared, ['T-2', 'T-3']);
  assert.deepEqual(closed, ['T-2', 'T-3']);
  assert.deepEqual(
    sent.filter((entry) => entry.channel === 'scraper:orders')
      .map((entry) => entry.payload[0].externalOrderId),
    ['T-2', 'T-3'],
  );
  assert.equal(clicked.includes('T-4'), false);
});

test('history sync rejects an empty invoice without emitting an order', async () => {
  const errors = [];
  const adapter = {
    platform: 'talabat',
    historyRows: () => [{ click() {} }],
    externalOrderId: () => 'T-EMPTY',
    detailRoot: () => ({}),
    parseOrder: () => ({
      platform: 'talabat',
      externalOrderId: 'T-EMPTY',
      items: [],
    }),
    detailCloseButton: () => ({ click() {} }),
  };
  const ipc = {
    invoke: async () => ({ existing: [], missing: ['T-EMPTY'] }),
    send(channel, payload) {
      errors.push({ channel, payload });
    },
  };

  const result = await syncTopHistoryOrders({ adapter, ipc });

  assert.equal(result.ingested, 0);
  assert.equal(result.failed, 1);
  assert.equal(errors.some((entry) => entry.channel === 'scraper:orders'), false);
  assert.equal(errors.some((entry) => entry.channel === 'scraper:error'), true);
});

test('history sync reacquires rows after closing a drawer rerenders the grid', async () => {
  let generation = 0;
  let activeId = '';
  const clicked = [];
  const ids = ['T-1', 'T-2'];
  const adapter = {
    platform: 'talabat',
    historyRows: (limit) =>
      ids.slice(0, limit).map((id) => {
        const rowGeneration = generation;
        return {
          id,
          click() {
            assert.equal(rowGeneration, generation, 'stale row was clicked');
            activeId = id;
            clicked.push(id);
          },
        };
      }),
    externalOrderId: (row) => row.id,
    detailRoot: () => (activeId ? { id: activeId } : null),
    parseOrder: (_detail, externalOrderId) => ({
      platform: 'talabat',
      externalOrderId,
      items: [{ name: 'Meal', quantity: 1, unitPrice: 1 }],
    }),
    detailCloseButton: () => ({
      click() {
        activeId = '';
        generation += 1;
      },
    }),
  };
  const ipc = {
    async invoke() {
      return { existing: [], missing: ids };
    },
    send() {},
  };

  const result = await syncTopHistoryOrders({ adapter, ipc, limit: 2 });

  assert.deepEqual(clicked, ids);
  assert.equal(result.failed, 0);
});

test('recurring history sync checks at most the top five rows', async () => {
  const checked = [];
  const rows = Array.from({ length: 6 }, (_, index) => ({
    id: `T-${index + 1}`,
    click() {
      throw new Error('Existing rows must not be clicked');
    },
  }));
  const adapter = {
    historyRows: (limit) => rows.slice(0, limit),
    externalOrderId: (row) => row.id,
  };
  const ipc = {
    async invoke(channel, ids) {
      if (channel === 'scraper:check-order-ids') checked.push(...ids);
      return { existing: ids, missing: [] };
    },
    send() {},
  };

  const result = await syncTopHistoryOrders({ adapter, ipc, limit: 5 });

  assert.deepEqual(checked, ['T-1', 'T-2', 'T-3', 'T-4', 'T-5']);
  assert.deepEqual(result, {
    checked: 5,
    skipped: 5,
    ingested: 0,
    failed: 0,
    ingestedIds: [],
    customersUpdated: 0,
  });
});

test('history sync does not open an order already claimed by network capture', async () => {
  const clicked = [];
  const adapter = {
    platform: 'talabat',
    historyRows: () => [
      {
        id: 'T-NET',
        click() {
          clicked.push('T-NET');
        },
      },
    ],
    externalOrderId: (row) => row.id,
  };
  const ipc = {
    async invoke(channel) {
      if (channel === 'orders:processed-ids') return { ids: ['T-NET'] };
      return { existing: [], missing: ['T-NET'] };
    },
    send() {},
  };
  const result = await syncTopHistoryOrders({ adapter, ipc, limit: 1 });
  assert.deepEqual(clicked, []);
  assert.equal(result.skipped, 1);
  assert.equal(result.ingested, 0);
});
