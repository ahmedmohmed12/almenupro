'use strict';

const { ensureRestaurantId } = require('../tenantStore');
const { LOCATION_KIND, newId } = require('./constants');

const INVENTORY_DOC_ID = 'inventory_ledger';

const defaultTenantState = () => ({
  locations: [],
  items: [],
  moves: [],
  recipes: [],
  packagingProfiles: [],
  purchases: [],
  jobs: [],
});

let memoryBlob = null;
const locks = new Map();

async function withTenantLock(tenantId, fn) {
  const key = String(tenantId || 'default');
  const prev = locks.get(key) || Promise.resolve();
  let release;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  locks.set(
    key,
    prev.then(() => gate),
  );
  await prev;
  try {
    return await fn();
  } finally {
    release();
    if (locks.get(key) === gate) {
      locks.delete(key);
    }
  }
}

function normalizeBlob(raw) {
  const base = defaultTenantState();
  if (!raw || typeof raw !== 'object') return base;
  for (const key of Object.keys(base)) {
    base[key] = Array.isArray(raw[key]) ? raw[key] : [];
  }
  return base;
}

function getReadWrite(dataStore) {
  return {
    read: () => dataStore.readNamedDoc(INVENTORY_DOC_ID, defaultTenantState()),
    write: (data) => dataStore.writeNamedDoc(INVENTORY_DOC_ID, data),
  };
}

async function loadBlob(dataStore) {
  if (memoryBlob) return memoryBlob;
  const { read } = getReadWrite(dataStore);
  memoryBlob = normalizeBlob(await read());
  return memoryBlob;
}

async function saveBlob(dataStore, blob) {
  memoryBlob = normalizeBlob(blob);
  const { write } = getReadWrite(dataStore);
  await write(memoryBlob);
  return memoryBlob;
}

function scopeTenant(rows, tenantId) {
  const id = String(tenantId);
  return (Array.isArray(rows) ? rows : []).filter(
    (row) =>
      String(row.tenantId || row.tenant_id || row.restaurantId || row.restaurant_id) === id,
  );
}

function defaultLocations(tenantId, branchId) {
  const bid = String(branchId || tenantId);
  const defs = [
    { kind: LOCATION_KIND.BRANCH_STOCK, name: 'مخزن الفرع', physical: true },
    { kind: LOCATION_KIND.KITCHEN_PREP, name: 'تحضير المطبخ', physical: true },
    { kind: LOCATION_KIND.VENDOR, name: 'مورد', physical: false },
    { kind: LOCATION_KIND.CUSTOMER, name: 'عميل', physical: false },
    { kind: LOCATION_KIND.WASTE, name: 'هدر', physical: false },
    { kind: LOCATION_KIND.ADJUSTMENT, name: 'تسوية', physical: false },
    { kind: LOCATION_KIND.IN_TRANSIT, name: 'قيد النقل', physical: false },
  ];
  return defs.map((entry) => ({
    id: newId('loc'),
    tenantId,
    branchId: entry.physical ? bid : null,
    kind: entry.kind,
    name: entry.name,
    physical: entry.physical,
    createdAt: new Date().toISOString(),
  }));
}

function ensureLocationsInBlob(blob, tenantId, branchId) {
  let locations = scopeTenant(blob.locations, tenantId);
  const bid = String(branchId || tenantId);
  const physical = locations.filter((loc) => loc.physical && String(loc.branchId) === bid);
  if (physical.length < 2) {
    const seeded = defaultLocations(tenantId, bid);
    const existingKinds = new Set(
      locations.map((l) => `${l.branchId || 'sys'}:${l.kind}`),
    );
    for (const loc of seeded) {
      const key = `${loc.branchId || 'sys'}:${loc.kind}`;
      if (!existingKinds.has(key)) {
        locations.push(loc);
        existingKinds.add(key);
      }
    }
    const other = blob.locations.filter(
      (row) => String(row.tenantId || row.restaurantId) !== String(tenantId),
    );
    blob.locations = [...other, ...locations];
  }
  return locations;
}

async function ensureLocations(dataStore, tenantId, branchId) {
  return mutateInventory(dataStore, tenantId, async (blob) => {
    ensureLocationsInBlob(blob, tenantId, branchId);
    return blob;
  }).then(() => loadBlob(dataStore).then((b) => scopeTenant(b.locations, tenantId)));
}

function findLocation(locations, { kind, branchId }) {
  return locations.find(
    (loc) =>
      loc.kind === kind &&
      (loc.physical ? String(loc.branchId) === String(branchId) : !loc.physical),
  );
}

async function mutateInventory(dataStore, tenantId, mutator) {
  return withTenantLock(tenantId, async () => {
    const blob = await loadBlob(dataStore);
    const out = await mutator(blob, tenantId);
    const next = out && typeof out === 'object' && out.blob ? out.blob : out;
    await saveBlob(dataStore, next);
    return out && typeof out === 'object' && Object.prototype.hasOwnProperty.call(out, 'result')
      ? out.result
      : next;
  });
}

function attachTenant(row, tenantId) {
  return ensureRestaurantId({
    ...row,
    tenantId,
    restaurantId: tenantId,
  });
}

module.exports = {
  INVENTORY_DOC_ID,
  loadBlob,
  saveBlob,
  mutateInventory,
  scopeTenant,
  ensureLocations,
  ensureLocationsInBlob,
  findLocation,
  attachTenant,
  withTenantLock,
};