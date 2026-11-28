'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  isDocClosed,
  isDocDraft,
  DOC_STATUS,
  TRANSFER_STAGE,
} = require('../lib/inventory/constants');
const { ingredientApplies, explodeMenuItemToRequirements } = require('../lib/inventory/recipeExplosion');
const { flattenOrderRequirements, mapSalesChannel } = require('../lib/inventory/recipeEngine');
const { reportInventoryLevels } = require('../lib/inventory/inventoryReports');
const { createInventoryItem } = require('../lib/inventory/inventoryModels');
const {
  createTransferRecord,
  sendTransfer,
  receiveTransfer,
} = require('../lib/inventory/transferService');
const { attachTenant, mutateInventory } = require('../lib/inventory/inventoryRepository');

function mockDataStore(initial) {
  let doc = initial;
  return {
    readNamedDoc: async () => doc,
    writeNamedDoc: async (_, data) => {
      doc = data;
    },
    _get: () => doc,
  };
}

test('document status helpers', () => {
  assert.equal(isDocDraft(DOC_STATUS.DRAFT), true);
  assert.equal(isDocDraft('CLOSED'), false);
  assert.equal(isDocClosed(DOC_STATUS.CLOSED), true);
  assert.equal(isDocClosed('APPROVED'), true);
});

test('ingredientApplies respects channel packaging flags', () => {
  assert.equal(ingredientApplies({ applicableOrderTypes: 'ALL' }, 'DELIVERY'), true);
  assert.equal(
    ingredientApplies({ applicableOrderTypes: ['DELIVERY', 'AGGREGATOR'] }, 'DINE_IN'),
    false,
  );
  assert.equal(
    ingredientApplies({ applicableOrderTypes: ['DELIVERY'] }, 'DELIVERY'),
    true,
  );
});

test('flattenOrderRequirements skips DINE_IN-only packaging on delivery', () => {
  const tenantId = 't1';
  const boxId = 'box';
  const recipes = [
    attachTenant(
      {
        id: 'rec1',
        menuItemId: 'burger',
        ingredients: [
          { itemId: 'beef', qtyInRecipeUom: 1, applicableOrderTypes: 'ALL' },
          {
            itemId: boxId,
            qtyInRecipeUom: 1,
            applicableOrderTypes: ['DELIVERY', 'TAKEAWAY'],
          },
        ],
      },
      tenantId,
    ),
  ];
  const items = [
    attachTenant(
      { id: 'beef', itemType: 'RAW', avgCost: 1, currentQty: 100 },
      tenantId,
    ),
    attachTenant(
      { id: boxId, itemType: 'RAW', avgCost: 0.1, currentQty: 100 },
      tenantId,
    ),
  ];
  const order = {
    restaurantId: tenantId,
    orderType: 'delivery',
    items: [{ menuItemId: 'burger', quantity: 2 }],
  };
  const out = flattenOrderRequirements({
    order,
    recipes,
    packagingProfiles: [],
    itemsById: new Map(items.map((row) => [String(row.id), row])),
    tenantId,
  });
  const byId = Object.fromEntries(out.requirements.map((r) => [r.itemId, r.qtyInRecipeUom]));
  assert.equal(byId.beef, 2);
  assert.equal(byId[boxId], 2);
});

test('explodeMenuItemToRequirements omits dine-in-only lines on takeaway', () => {
  const tenantId = 't1';
  const needs = explodeMenuItemToRequirements({
    menuItemId: 'm1',
    qty: 1,
    channel: 'TAKEAWAY',
    tenantId,
    recipes: [
      attachTenant(
        {
          menuItemId: 'm1',
          ingredients: [
            { itemId: 'a', qtyInRecipeUom: 1, applicableOrderTypes: 'ALL' },
            { itemId: 'b', qtyInRecipeUom: 5, applicableOrderTypes: ['DINE_IN'] },
          ],
        },
        tenantId,
      ),
    ],
    items: [attachTenant({ id: 'a' }, tenantId), attachTenant({ id: 'b' }, tenantId)],
  });
  assert.deepEqual(needs, [{ itemId: 'a', qtyInRecipeUom: 1 }]);
});

test('inventory levels report exposes branch thresholds', () => {
  const tenantId = 'r1';
  const blob = {
    items: [
      attachTenant(
        {
          id: 'inv1',
          name: 'طماطم',
          branchId: 'r1',
          currentQty: 5,
          avgCost: 2,
          branchLevels: [{ branchId: 'r1', minLevel: 10, parLevel: 20, maxLevel: 50 }],
        },
        tenantId,
      ),
    ],
    moves: [],
  };
  const rows = reportInventoryLevels(blob, tenantId, 'r1');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].stockStatus, 'LOW');
  assert.equal(rows[0].minLevel, 10);
});

test('transfer request -> send -> receive closes document', async () => {
  const tenantId = 'shop-a';
  const dataStore = mockDataStore({
    locations: [],
    items: [
      attachTenant(
        {
          id: 'flour',
          name: 'دقيق',
          itemType: 'RAW',
          currentQty: 100,
          avgCost: 0.5,
          branchId: tenantId,
        },
        tenantId,
      ),
    ],
    moves: [],
    recipes: [],
    packagingProfiles: [],
    purchases: [],
    transfers: [],
    productions: [],
    wasteDocuments: [],
    inventoryCounts: [],
    jobs: [],
  });

  const trf = createTransferRecord(
    {
      fromBranchId: tenantId,
      toBranchId: tenantId,
      lines: [{ itemId: 'flour', qtyInRecipeUom: 10 }],
    },
    tenantId,
  );
  await mutateInventory(dataStore, tenantId, async (blob) => {
    blob.transfers = [trf];
    return blob;
  });

  const sent = await sendTransfer(dataStore, {
    tenantId,
    transferId: trf.id,
    createdBy: 'tester',
  });
  assert.equal(sent.stage, TRANSFER_STAGE.SENT);

  const received = await receiveTransfer(dataStore, {
    tenantId,
    transferId: trf.id,
    createdBy: 'tester',
  });
  assert.equal(received.stage, TRANSFER_STAGE.RECEIVED);
  assert.equal(isDocClosed(received.status), true);
});

test('mapSalesChannel reads aggregator sources', () => {
  assert.equal(mapSalesChannel({ orderSource: 'talabat', orderType: 'delivery' }), 'AGGREGATOR');
});