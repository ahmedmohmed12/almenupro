'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { handleTableRoutes } = require('../lib/tableRoutes');

function fixture(body, action = 'request-check') {
  const restaurant = {
    id: 'rest-1',
    slug: 'demo',
    status: 'active',
    subscriptionStatus: 'active',
    features: { tableManagement: true },
  };
  const tables = [
    {
      id: 'table-4',
      restaurant_id: 'rest-1',
      number: '4',
      status: 'occupied',
      activeSession: {
        id: 'session-4',
        cartItems: [
          { name: 'Meal', quantity: 2, unitPrice: 3 },
          { name: 'Drink', quantity: 1, lineTotal: 1.5 },
        ],
      },
    },
  ];
  let writtenTables;
  const response = {};
  return {
    response,
    get writtenTables() {
      return writtenTables;
    },
    run: () =>
      handleTableRoutes(
        { method: 'POST' },
        response,
        new URL(
          `https://example.test/api/public/tables/demo/table-4/${action}`,
        ),
        {
          readBody: async () => JSON.stringify(body),
          sendJson: (res, status, payload) => {
            res.status = status;
            res.payload = payload;
          },
          readRestaurants: async () => [restaurant],
          readTables: async () => tables,
          writeTables: async (next) => {
            writtenTables = next;
          },
        },
      ),
  };
}

test('public bill request validates and stores total with tip and payment', async () => {
  const request = fixture({ tipAmount: 1, paymentMethod: 'knet' });

  assert.equal(await request.run(), true);
  assert.equal(request.response.status, 200);
  const session = request.writtenTables[0].activeSession;
  assert.equal(request.writtenTables[0].status, 'awaiting_check');
  assert.equal(session.checkRequested, true);
  assert.equal(session.tipAmount, 1);
  assert.equal(session.billTotal, 8.5);
  assert.equal(session.paymentMethod, 'knet');
});

test('public bill request rejects non-fixed tip values', async () => {
  const request = fixture({ tipAmount: 3.75, paymentMethod: 'cash' });

  assert.equal(await request.run(), true);
  assert.equal(request.response.status, 400);
  assert.equal(request.response.payload.code, 'INVALID_TIP_AMOUNT');
  assert.equal(request.writtenTables, undefined);
});

test('public waiter call marks table for the POS table poll', async () => {
  const request = fixture({ note: 'Need assistance' }, 'call-waiter');

  assert.equal(await request.run(), true);
  assert.equal(request.response.status, 200);
  const table = request.writtenTables[0];
  assert.equal(table.status, 'waiter_call');
  assert.equal(table.activeSession.waiterRequested, true);
  assert.equal(table.activeSession.waiterNote, 'Need assistance');
});
