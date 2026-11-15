'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { TalabatAdapter } = require('../src/adapters/talabat-adapter');
const { JahezAdapter } = require('../src/adapters/jahez-adapter');
const { KetaAdapter } = require('../src/adapters/keta-adapter');
const talabatSelectors = require('../src/selectors/talabat.json');
const jahezSelectors = require('../src/selectors/jahez.json');
const keetaSelectors = require('../src/selectors/keeta.json');

class FixtureNode {
  constructor(text = '', attributes = {}) {
    this.textContent = text;
    this.attributes = attributes;
    this.one = new Map();
    this.many = new Map();
  }

  querySelector(selector) {
    return this.one.get(selector) || null;
  }

  querySelectorAll(selector) {
    return this.many.get(selector) || [];
  }

  getAttribute(name) {
    return this.attributes[name] || null;
  }
}

function providerFixture(selectors, externalOrderId) {
  const item = new FixtureNode();
  item.one.set(selectors.itemName, new FixtureNode('Fixture meal'));
  item.one.set(selectors.itemQuantity, new FixtureNode('2'));
  item.one.set(selectors.itemPrice, new FixtureNode('1.250 KWD'));
  item.many.set(selectors.itemOptions, [new FixtureNode('Extra sauce 0.100')]);

  const order = new FixtureNode('', { 'data-order-id': externalOrderId });
  order.one.set(selectors.customerName, new FixtureNode('Fixture Customer'));
  order.one.set(selectors.total, new FixtureNode('2.500 KWD'));
  order.one.set(selectors.deliveryType, new FixtureNode('Delivery'));
  order.many.set(selectors.item, [item]);

  const document = new FixtureNode();
  document.many.set(selectors.order, [order]);
  return document;
}

for (const fixture of [
  ['talabat', TalabatAdapter, talabatSelectors],
  ['jahez', JahezAdapter, jahezSelectors],
  ['keeta', KetaAdapter, keetaSelectors],
]) {
  const [platform, Adapter, selectors] = fixture;
  test(`${platform} adapter parses its configurable selector fixture`, () => {
    const [order] = new Adapter(
      providerFixture(selectors, `${platform}-fixture-1`),
    ).scan();
    assert.equal(order.platform, platform);
    assert.equal(order.externalOrderId, `${platform}-fixture-1`);
    assert.equal(order.items.length, 1);
    assert.equal(order.items[0].lineTotal, 2.5);
  });
}

test('adapter merges live and top history rows with strict ID deduplication', () => {
  const [liveMode, historyMode] = talabatSelectors.observationModes;
  const liveOrder = providerFixture(
    talabatSelectors,
    'talabat-shared-1',
  ).many.get(talabatSelectors.order)[0];
  const historyOrders = [
    providerFixture(talabatSelectors, 'talabat-shared-1').many.get(
      talabatSelectors.order,
    )[0],
    ...Array.from({ length: 25 }, (_, index) =>
      providerFixture(talabatSelectors, `talabat-history-${index + 1}`).many.get(
        talabatSelectors.order,
      )[0],
    ),
  ];
  const liveContainer = new FixtureNode();
  liveContainer.many.set(liveMode.order, [liveOrder]);
  const historyContainer = new FixtureNode();
  historyContainer.many.set(historyMode.order, historyOrders);
  const document = new FixtureNode();
  document.one.set(liveMode.root, liveContainer);
  document.one.set(historyMode.root, historyContainer);

  const orders = new TalabatAdapter(document).scan();

  assert.equal(orders.length, 25);
  assert.equal(
    orders.filter((order) => order.externalOrderId === 'talabat-shared-1').length,
    1,
  );
  assert.equal(
    orders.some((order) => order.externalOrderId === 'talabat-history-25'),
    false,
  );
});
