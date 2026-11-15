'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  cleanCustomerAddress,
  cleanCustomerName,
  cleanCustomerPhone,
  customerDetailsFieldsAreVisible,
  expandTalabatCustomerDetails,
  extractTalabatCustomerDetails,
  extractTalabatPaymentMethod,
  talabatCreatedAt,
  waitForTalabatCustomerDetails,
  TalabatAdapter,
} = require('../src/adapters/talabat-adapter');
const { createAdapter } = require('../src/adapters/registry');
const selectors = require('../src/selectors/talabat.json');

test('Talabat parses numeric, named, and today provider timestamps', () => {
  assert.equal(
    talabatCreatedAt({ textContent: '07/10/2026 9:15 AM' }),
    '2026-10-07T06:15:00.000Z',
  );
  assert.equal(
    talabatCreatedAt({ textContent: '7 Oct 2026 9:15 PM' }),
    '2026-10-07T18:15:00.000Z',
  );
  assert.match(
    talabatCreatedAt({ textContent: 'Today 09:15' }),
    /T06:15:00\.000Z$/,
  );
});

class FakeNode {
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

test('TalabatAdapter normalizes an order from selector-driven DOM', () => {
  const item = new FakeNode();
  item.one.set(selectors.itemName, new FakeNode('Chicken Burger'));
  item.one.set(selectors.itemQuantity, new FakeNode('2x'));
  item.one.set(selectors.itemPrice, new FakeNode('KWD 1.750'));
  item.many.set(selectors.itemOptions, [new FakeNode('Cheese +0.250')]);

  const order = new FakeNode('', { 'data-order-id': 'TB-42' });
  order.one.set(selectors.customerName, new FakeNode('  Ada   Ali '));
  order.one.set(selectors.phone, new FakeNode('+965 5555'));
  order.one.set(selectors.address, new FakeNode('Kuwait City'));
  order.one.set(selectors.subtotal, new FakeNode('3.500'));
  order.one.set(selectors.total, new FakeNode('4.000'));
  order.one.set(selectors.paymentMethod, new FakeNode('Card'));
  order.one.set(selectors.deliveryType, new FakeNode('Delivery'));
  order.one.set(
    selectors.createdAt,
    new FakeNode('', { datetime: '2026-10-05T09:00:00Z' }),
  );
  order.many.set(selectors.item, [item]);

  const document = new FakeNode();
  document.many.set(selectors.order, [order]);

  const result = new TalabatAdapter(document).scan();
  assert.equal(result.length, 1);
  assert.equal(result[0].externalOrderId, 'TB-42');
  assert.equal(result[0].customerName, 'Ada Ali');
  assert.deepEqual(result[0].items[0], {
    name: 'Chicken Burger',
    quantity: 2,
    unitPrice: 1.75,
    lineTotal: 3.5,
    options: [{ name: 'Cheese +0.250', price: 0.25 }],
  });
});

test('registry supports Keta naming while normalizing platform to keeta', () => {
  const document = new FakeNode();
  const adapter = createAdapter('keta', document);
  assert.equal(adapter.platform, 'keeta');
});

test('observer keeps the document body attached for SPA history-table rendering', () => {
  const document = new FakeNode();
  document.body = new FakeNode();
  const historyTable = new FakeNode();
  document.one.set(selectors.observationModes[1].root, historyTable);

  const roots = new TalabatAdapter(document).observationRoots();

  assert.equal(roots.includes(historyTable), true);
  assert.equal(roots.includes(document.body), true);
});

test('Talabat adapter parses production drawer product text', () => {
  const product = new FakeNode('2×Vegetable Maqluba KWD 6.500 expand_more');
  const item = new TalabatAdapter(new FakeNode()).parseItem(product);

  assert.deepEqual(item, {
    name: 'Vegetable Maqluba',
    quantity: 2,
    unitPrice: 3.25,
    lineTotal: 6.5,
    options: [],
  });
});

test('Keeta adapter extracts the stable long order id from a history row', () => {
  const adapter = createAdapter('keeta', new FakeNode());
  const row = new FakeNode(
    '5444143823849023 #9023; Today, 22:32 (GMT+3)',
  );

  assert.equal(adapter.externalOrderId(row), '5444143823849023');
});

test('Talabat customer details section yields name, address, and phone', () => {
  const leaf = (text) => ({ textContent: text, children: [] });
  const heading = leaf('Customer details');
  const leaves = [
    heading,
    leaf('person'),
    leaf('Aisha Mohmd'),
    leaf('location_on'),
    leaf('103, العدواني, Farwaniya'),
    leaf('phone'),
    leaf('+96566839309'),
  ];
  const section = {
    textContent: leaves.map((node) => node.textContent).join(' '),
    children: leaves,
    parentElement: null,
    querySelectorAll: () => leaves,
  };
  heading.parentElement = section;
  const root = { querySelectorAll: () => [heading] };

  assert.deepEqual(extractTalabatCustomerDetails(root), {
    customerName: 'Aisha Mohmd',
    phone: '+96566839309',
    address: '103, العدواني, Farwaniya',
  });
});

test('Talabat expands a collapsed customer section before parsing Arabic details', async () => {
  const leaf = (text) => ({ textContent: text, children: [] });
  const heading = leaf('Customer details');
  const leaves = [
    heading,
    leaf('person'),
    leaf('عبدالهادي الرجعان'),
    leaf('location_on'),
    leaf('3,4,Farwaniya'),
    leaf('phone'),
    leaf('+96557775768'),
  ];
  let expanded = false;
  const toggle = {
    textContent: 'Customer details',
    children: [heading],
    parentElement: null,
    tagName: 'BUTTON',
    getAttribute(name) {
      return name === 'aria-expanded' ? String(expanded) : null;
    },
    click() {
      expanded = true;
    },
    querySelectorAll() {
      return expanded ? leaves : [heading];
    },
  };
  heading.parentElement = toggle;
  const root = { querySelectorAll: () => [heading] };

  assert.equal(await expandTalabatCustomerDetails(root, 0), true);
  assert.equal(expanded, true);
  assert.deepEqual(extractTalabatCustomerDetails(root), {
    customerName: 'عبدالهادي الرجعان',
    phone: '+96557775768',
    address: '3,4,Farwaniya',
  });
});

test('Talabat clicks a sibling chevron when the customer header itself is not clickable', async () => {
  const leaf = (text, hidden = false) => ({
    textContent: text,
    children: [],
    hidden,
  });
  const heading = leaf('Customer details');
  const name = leaf('FAHAD العتيبي', true);
  const address = leaf('1,37,Farwaniya', true);
  const phone = leaf('+96597114711', true);
  const leaves = [heading, name, address, phone];
  let clicked = false;
  const arrowButton = {
    click() {
      clicked = true;
      name.hidden = false;
      address.hidden = false;
      phone.hidden = false;
    },
    getAttribute() {
      return null;
    },
  };
  const headerRow = {
    parentElement: null,
    querySelector(selector) {
      return selector.includes('button') ? arrowButton : null;
    },
    querySelectorAll() {
      return leaves;
    },
  };
  heading.parentElement = headerRow;
  const root = { querySelectorAll: () => [heading] };

  assert.equal(customerDetailsFieldsAreVisible(root), false);
  assert.equal(await expandTalabatCustomerDetails(root, 0), true);
  assert.equal(clicked, true);
  assert.equal(customerDetailsFieldsAreVisible(root), true);
  assert.deepEqual(extractTalabatCustomerDetails(root), {
    customerName: 'FAHAD العتيبي',
    phone: '+96597114711',
    address: '1,37,Farwaniya',
  });
});

test('Talabat preserves Cash for settlement and only maps explicit gateways to Prepaid', () => {
  const { preferPaymentMethod } = require('../src/adapters/talabat-adapter');
  const rootWith = (value) => ({
    textContent: value,
    querySelectorAll: () => [{ textContent: value, children: [] }],
  });

  assert.equal(extractTalabatPaymentMethod(rootWith('Cash on delivery')), 'Cash');
  assert.equal(extractTalabatPaymentMethod(rootWith('Payment: Cash')), 'Cash');
  assert.equal(extractTalabatPaymentMethod(rootWith('Collect Cash')), 'Cash');
  assert.equal(extractTalabatPaymentMethod(rootWith('كاش')), 'Cash');
  assert.equal(extractTalabatPaymentMethod(rootWith('كاشير وردية المساء')), '');
  assert.equal(extractTalabatPaymentMethod(rootWith('KNET')), 'KNET');
  assert.equal(extractTalabatPaymentMethod(rootWith('Online payment')), 'Prepaid');
  assert.equal(extractTalabatPaymentMethod(rootWith('Credit Card')), 'Prepaid');
  assert.equal(extractTalabatPaymentMethod(rootWith('مدفوع مسبقاً')), 'Prepaid');
  // Bare order-status "Paid" must NOT invent Prepaid.
  assert.equal(extractTalabatPaymentMethod(rootWith('Paid')), '');
  // Explicit Cash + stray paid text still settles as Cash.
  assert.equal(
    extractTalabatPaymentMethod(rootWith('Payment: Cash · Paid online')),
    'Cash',
  );
  assert.equal(preferPaymentMethod('Cash', 'Prepaid'), 'Cash');
  assert.equal(preferPaymentMethod('Prepaid', 'Cash on delivery'), 'Cash');
});

test('Talabat waits for customer fields that render after the item invoice', async () => {
  const leaf = (text, hidden = false) => ({
    textContent: text,
    children: [],
    hidden,
  });
  const heading = leaf('Customer details');
  const name = leaf('انور سعد', true);
  const address = leaf('١٢٦ منزل ١٥, Farwaniya', true);
  const phone = leaf('+96599964080', true);
  const section = {
    textContent: 'Customer details',
    children: [heading],
    parentElement: null,
    getAttribute(name) {
      return name === 'aria-expanded' ? 'true' : null;
    },
    querySelectorAll() {
      return [heading, name, address, phone];
    },
  };
  heading.parentElement = section;
  const root = { querySelectorAll: () => [heading] };
  setTimeout(() => {
    name.hidden = false;
    address.hidden = false;
    phone.hidden = false;
  }, 10);

  assert.deepEqual(
    await waitForTalabatCustomerDetails(root, {
      timeoutMs: 100,
      pollMs: 5,
    }),
    {
      customerName: 'انور سعد',
      phone: '+96599964080',
      address: '١٢٦ منزل ١٥, Farwaniya',
    },
  );
});

test('Talabat parses customer fields portal-rendered as header siblings', () => {
  const leaf = (text) => ({ textContent: text, children: [] });
  const heading = leaf('Customer details');
  const name = leaf('انور سعد');
  const address = leaf('١٢٦ منزل ١٥,Farwaniya');
  const phone = leaf('+96599964080');
  const timeline = leaf('Order timeline');
  const header = {
    textContent: 'Customer details',
    children: [heading],
    parentElement: null,
    querySelectorAll: () => [heading],
  };
  heading.parentElement = header;
  const root = {
    querySelectorAll: () => [header, heading, name, address, phone, timeline],
  };

  assert.deepEqual(extractTalabatCustomerDetails(root), {
    customerName: 'انور سعد',
    phone: '+96599964080',
    address: '١٢٦ منزل ١٥,Farwaniya',
  });
});

test('Talabat removes Material icon ligatures joined to customer values', () => {
  assert.equal(cleanCustomerName('personانوار سعد'), 'انوار سعد');
  assert.equal(cleanCustomerPhone('phone+96599964080'), '+96599964080');
  assert.equal(
    cleanCustomerAddress('location_on٩١٦,منزل ١٥,Farwaniya'),
    '٩١٦,منزل ١٥,Farwaniya',
  );
});
