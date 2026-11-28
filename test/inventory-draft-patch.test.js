'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  DOC_STATUS,
  isDocClosed,
} = require('../lib/inventory/constants');
const {
  attachTenant,
  mutateInventory,
  scopeTenant,
  saveBlob,
  INVENTORY_DOC_ID,
} = require('../lib/inventory/inventoryRepository');
const {
  createProductionRecord,
  closeProduction,
  normalizeProductionLines,
} = require('../lib/inventory/productionService');
const { createTransferRecord } = require('../lib/inventory/transferService');
const { createWasteDocument } = require('../lib/inventory/wasteTransactionService');
const { createCountSession } = require('../lib/inventory/inventoryCountService');
const { createPurchaseRecord } = require('../lib/inventory/purchasingService');
const { normalizePurchaseLine } = require('../lib/inventory/uomConversion');
const { isDocDraft } = require('../lib/inventory/constants');
const {
  handleInventoryFoodicsRoutes,
  patchDraftDoc,
} = require('../lib/inventoryFoodicsRoutes');

function emptyLedger() {
  return {
    locations: [],
    items: [],
    moves: [],
    recipes: [],
    packagingProfiles: [],
    purchases: [],
    transfers: [],
    productions: [],
    wasteDocuments: [],
    inventoryCounts: [],
    jobs: [],
  };
}

function mockDataStore() {
  let doc = null;
  return {
    readNamedDoc: async (id, fallback) => {
      if (id === INVENTORY_DOC_ID && doc) return doc;
      return fallback ?? emptyLedger();
    },
    writeNamedDoc: async (id, data) => {
      if (id === INVENTORY_DOC_ID) doc = data;
    },
    _get: () => doc,
  };
}

async function seedLedger(dataStore, patch) {
  const base = emptyLedger();
  await saveBlob(dataStore, { ...base, ...patch });
}

function sendJson(res, statusCode, body) {
  res.statusCode = statusCode;
  res.body = body;
}

function mockRes() {
  return { statusCode: 0, body: null, setHeader() {} };
}

async function invokeFoodicsPatch({ path, body, dataStore, tenantId }) {
  const res = mockRes();
  const req = { method: 'PATCH', headers: { 'content-type': 'application/json' } };
  const url = new URL(`http://local${path}`);
  await handleInventoryFoodicsRoutes(req, res, url, {
    sendJson,
    parseJson: JSON.parse,
    readBody: async () => JSON.stringify(body),
    dataStore,
    tenantId,
    branchId: tenantId,
    auth: { role: 'owner', staffId: 'tester' },
    rejectCashier: () => false,
    readItems: async () => [],
    readOrders: async () => [],
  });
  return res;
}

function itemsMap(blob, tenantId) {
  return new Map(
    scopeTenant(blob.items, tenantId).map((row) => [String(row.id), row]),
  );
}

test('normalizeProductionLines builds multi-line payload', () => {
  const lines = normalizeProductionLines({
    lines: [
      { prepItemId: 'p1', outputQtyInRecipeUom: 2 },
      { prepItemId: 'p2', qty: 3 },
    ],
  });
  assert.equal(lines.length, 2);
  assert.deepEqual(lines[0], { prepItemId: 'p1', outputQtyInRecipeUom: 2 });
  assert.deepEqual(lines[1], { prepItemId: 'p2', outputQtyInRecipeUom: 3 });
});

test('createProductionRecord stores multiple PREP lines in one draft', () => {
  const tenantId = 'r1';
  const doc = createProductionRecord(
    {
      lines: [
        { prepItemId: 'prepA', outputQtyInRecipeUom: 4 },
        { prepItemId: 'prepB', outputQtyInRecipeUom: 1.5 },
      ],
      notes: 'batch',
    },
    tenantId,
    tenantId,
  );
  assert.equal(doc.status, DOC_STATUS.DRAFT);
  assert.equal(doc.lines.length, 2);
  assert.equal(doc.prepItemId, undefined);
});

test('closeProduction closes one draft with multiple PREP outputs', async () => {
  const tenantId = 'shop';
  const dataStore = mockDataStore();
  await seedLedger(dataStore, {
    items: [
      attachTenant(
        {
          id: 'flour',
          itemType: 'RAW',
          currentQty: 200,
          avgCost: 0.25,
          branchId: tenantId,
        },
        tenantId,
      ),
      attachTenant(
        {
          id: 'prepA',
          itemType: 'PREP',
          currentQty: 0,
          avgCost: 0,
          branchId: tenantId,
        },
        tenantId,
      ),
      attachTenant(
        {
          id: 'prepB',
          itemType: 'PREP',
          currentQty: 0,
          avgCost: 0,
          branchId: tenantId,
        },
        tenantId,
      ),
    ],
    recipes: [
      attachTenant(
        {
          prepItemId: 'prepA',
          expectedYieldQty: 1,
          ingredients: [{ itemId: 'flour', qtyInRecipeUom: 2 }],
        },
        tenantId,
      ),
      attachTenant(
        {
          prepItemId: 'prepB',
          expectedYieldQty: 1,
          ingredients: [{ itemId: 'flour', qtyInRecipeUom: 3 }],
        },
        tenantId,
      ),
    ],
  });

  const draft = createProductionRecord(
    {
      lines: [
        { prepItemId: 'prepA', outputQtyInRecipeUom: 5 },
        { prepItemId: 'prepB', outputQtyInRecipeUom: 2 },
      ],
    },
    tenantId,
    tenantId,
  );
  await mutateInventory(dataStore, tenantId, async (blob) => {
    blob.productions = [draft];
    return blob;
  });

  const closed = await closeProduction(dataStore, {
    tenantId,
    branchId: tenantId,
    productionId: draft.id,
    createdBy: 'tester',
  });
  assert.equal(isDocClosed(closed.status), true);
  assert.equal(closed.lines.length, 2);
  assert.equal(closed.lineSummaries.length, 2);

  const blob = dataStore._get();
  const items = scopeTenant(blob.items, tenantId);
  const prepA = items.find((row) => row.id === 'prepA');
  const prepB = items.find((row) => row.id === 'prepB');
  assert.equal(prepA.currentQty, 5);
  assert.equal(prepB.currentQty, 2);
});

test('patchDraftDoc updates transfer lines on draft', async () => {
  const tenantId = 'r1';
  const trf = createTransferRecord(
    {
      fromBranchId: tenantId,
      toBranchId: tenantId,
      lines: [{ itemId: 'a', qtyInRecipeUom: 1 }],
    },
    tenantId,
  );
  const dataStore = mockDataStore();
  await seedLedger(dataStore, { transfers: [trf] });

  const res = mockRes();
  await patchDraftDoc({
    dataStore,
    tenantId,
    collectionKey: 'transfers',
    docId: trf.id,
    patch: {
      lines: [
        { itemId: 'a', qtyInRecipeUom: 2 },
        { itemId: 'b', qtyInRecipeUom: 5 },
      ],
    },
    res,
    sendJson,
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.lines.length, 2);
  assert.equal(res.body.lines[1].itemId, 'b');
});

test('PATCH /productions updates lines array via HTTP handler', async () => {
  const tenantId = 'r1';
  const draft = createProductionRecord(
    { lines: [{ prepItemId: 'p1', outputQtyInRecipeUom: 1 }] },
    tenantId,
    tenantId,
  );
  const dataStore = mockDataStore();
  await seedLedger(dataStore, { productions: [draft] });

  const res = await invokeFoodicsPatch({
    path: `/api/inventory/productions/${draft.id}`,
    body: {
      lines: [
        { prepItemId: 'p1', outputQtyInRecipeUom: 2 },
        { prepItemId: 'p2', outputQtyInRecipeUom: 3 },
      ],
      notes: 'updated',
    },
    dataStore,
    tenantId,
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.lines.length, 2);
  assert.equal(res.body.notes, 'updated');
  assert.equal(res.body.prepItemId, null);
});

test('patchDraftDoc rejects PATCH on closed waste document', async () => {
  const tenantId = 'r1';
  const closed = createWasteDocument(
    { lines: [{ itemId: 'w1', qty: 1, wasteReason: 'OTHER' }] },
    tenantId,
    tenantId,
  );
  closed.status = DOC_STATUS.CLOSED;
  const dataStore = mockDataStore();
  await seedLedger(dataStore, { wasteDocuments: [closed] });

  const res = mockRes();
  await patchDraftDoc({
    dataStore,
    tenantId,
    collectionKey: 'wasteDocuments',
    docId: closed.id,
    patch: { lines: [{ itemId: 'w2', qty: 2, wasteReason: 'OTHER' }] },
    res,
    sendJson,
  });
  assert.equal(res.statusCode, 409);
});

test('PATCH /counts updates blind flag and lines', async () => {
  const tenantId = 'r1';
  const session = createCountSession(
    { lines: [{ itemId: 'i1', countedQty: 10 }] },
    tenantId,
    tenantId,
  );
  const dataStore = mockDataStore();
  await seedLedger(dataStore, { inventoryCounts: [session] });

  const res = await invokeFoodicsPatch({
    path: `/api/inventory/counts/${session.id}`,
    body: {
      blindCount: true,
      lines: [
        { itemId: 'i1', countedQty: 11 },
        { itemId: 'i2', countedQty: 4 },
      ],
    },
    dataStore,
    tenantId,
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.blindCount, true);
  assert.equal(res.body.lines.length, 2);
});

test('purchase draft PATCH replaces vendor and lines (repository flow)', async () => {
  const tenantId = 'r1';
  const item = attachTenant(
    {
      id: 'sugar',
      itemType: 'RAW',
      purchaseUom: 'KG',
      recipeUom: 'G',
      purchaseToRecipeFactor: 1000,
    },
    tenantId,
  );
  const purchase = createPurchaseRecord(
    {
      vendorName: 'V1',
      lines: [{ itemId: 'sugar', qtyInPurchaseUom: 1, unitCostInPurchaseUom: 2 }],
    },
    tenantId,
    tenantId,
    itemsMap({ items: [item] }, tenantId),
  );
  assert.equal(isDocDraft(purchase.status), true);

  const dataStore = mockDataStore();
  await seedLedger(dataStore, { items: [item], purchases: [purchase] });

  const purchaseId = purchase.id;
  const body = {
    vendorName: 'V2',
    lines: [{ itemId: 'sugar', qtyInPurchaseUom: 3, unitCostInPurchaseUom: 2.5 }],
  };

  const updated = await mutateInventory(dataStore, tenantId, async (blob) => {
    const purchases = scopeTenant(blob.purchases, tenantId);
    const idx = purchases.findIndex((p) => String(p.id) === purchaseId);
    if (!isDocDraft(purchases[idx].status)) {
      const err = new Error('لا يمكن تعديل شراء مغلق');
      err.code = 409;
      throw err;
    }
    const byId = itemsMap(blob, tenantId);
    purchases[idx] = {
      ...purchases[idx],
      vendorName: body.vendorName,
      lines: body.lines.map((line) => normalizePurchaseLine(line, byId.get(String(line.itemId)))),
      updatedAt: new Date().toISOString(),
    };
    blob.purchases = [
      ...blob.purchases.filter(
        (p) => String(p.tenantId || p.restaurantId) !== String(tenantId),
      ),
      ...purchases,
    ];
    return { blob, result: purchases[idx] };
  });

  assert.equal(updated.vendorName, 'V2');
  assert.equal(updated.lines[0].qtyInPurchaseUom, 3);
});