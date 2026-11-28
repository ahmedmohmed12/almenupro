'use strict';

const { ensureRestaurantId } = require('./tenantStore');

const TABLE_STATUSES = [
  'available',
  'occupied',
  'reserved',
  'awaiting_check',
  'waiter_call',
];

function normalizeFeatures(raw = {}) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const hasTableKey = Object.prototype.hasOwnProperty.call(source, 'tableManagement') ||
    Object.prototype.hasOwnProperty.call(source, 'table_management');
  const hasKitchenKey =
    Object.prototype.hasOwnProperty.call(source, 'kitchenManagement') ||
    Object.prototype.hasOwnProperty.call(source, 'kitchen_management');
  const hasDeliveryKey =
    Object.prototype.hasOwnProperty.call(source, 'deliveryManagement') ||
    Object.prototype.hasOwnProperty.call(source, 'delivery_management') ||
    Object.prototype.hasOwnProperty.call(source, 'menuProDelivery');
  const hasInventoryKey =
    Object.prototype.hasOwnProperty.call(source, 'inventoryEnabled') ||
    Object.prototype.hasOwnProperty.call(source, 'inventory_enabled') ||
    Object.prototype.hasOwnProperty.call(source, 'inventoryManagement') ||
    Object.prototype.hasOwnProperty.call(source, 'inventory_management');
  return {
    tableManagement: hasTableKey
      ? source.tableManagement === true || source.table_management === true
      : false,
    kitchenManagement: hasKitchenKey
      ? source.kitchenManagement === true || source.kitchen_management === true
      : true,
    deliveryManagement: hasDeliveryKey
      ? source.deliveryManagement === true ||
        source.delivery_management === true ||
        source.menuProDelivery === true
      : false,
    inventoryEnabled: hasInventoryKey
      ? source.inventoryEnabled === true ||
        source.inventory_enabled === true ||
        source.inventoryManagement === true ||
        source.inventory_management === true
      : false,
  };
}

function subscriptionAllowsFeatures(restaurant) {
  const status = String(
    restaurant?.subscriptionStatus || restaurant?.subscription_status || 'active',
  )
    .trim()
    .toLowerCase();
  return status === 'active' || status === 'trial';
}

function isTableManagementEnabled(restaurant) {
  return (
    subscriptionAllowsFeatures(restaurant) &&
    normalizeFeatures(restaurant?.features).tableManagement
  );
}

function isKitchenManagementEnabled(restaurant) {
  return (
    subscriptionAllowsFeatures(restaurant) &&
    normalizeFeatures(restaurant?.features).kitchenManagement
  );
}

function isDeliveryManagementEnabled(restaurant) {
  return (
    subscriptionAllowsFeatures(restaurant) &&
    normalizeFeatures(restaurant?.features).deliveryManagement
  );
}

function isInventoryEnabled(restaurant) {
  return (
    subscriptionAllowsFeatures(restaurant) &&
    normalizeFeatures(restaurant?.features).inventoryEnabled
  );
}

function normalizeTableStatus(raw) {
  const value = String(raw || 'available').trim().toLowerCase().replace(/-/g, '_');
  if (value === 'awaitingcheck' || value === 'pending_bill' || value === 'check_requested') {
    return 'awaiting_check';
  }
  if (value === 'waitercall' || value === 'waiter_requested' || value === 'call_waiter') {
    return 'waiter_call';
  }
  return TABLE_STATUSES.includes(value) ? value : 'available';
}

function createTableRecord(body = {}, restaurantId) {
  const number = String(body.number || body.tableNumber || body.table_number || '').trim();
  const zone = String(body.zone || body.section || 'الصالة الرئيسية').trim();
  const capacity = Math.max(1, Number(body.capacity || body.seats || 2) || 2);
  const name = String(body.name || '').trim() || (number ? `طاولة ${number}` : '');

  if (!number) {
    throw new Error('رقم الطاولة مطلوب');
  }

  const now = new Date().toISOString();
  return ensureRestaurantId(
    {
      id: `tbl_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      number,
      name,
      zone,
      capacity,
      status: normalizeTableStatus(body.status),
      sortOrder: Number(body.sortOrder ?? body.sort_order ?? 0) || 0,
      activeSession: null,
      createdAt: now,
      updatedAt: now,
    },
    restaurantId,
  );
}

function updateTableRecord(existing, body = {}) {
  if (!existing) throw new Error('الطاولة غير موجودة');
  const number = String(
    body.number ?? body.tableNumber ?? body.table_number ?? existing.number ?? '',
  ).trim();
  if (!number) throw new Error('رقم الطاولة مطلوب');

  return {
    ...existing,
    number,
    name: String(body.name ?? existing.name ?? '').trim() || `طاولة ${number}`,
    zone: String(body.zone ?? body.section ?? existing.zone ?? 'الصالة الرئيسية').trim(),
    capacity: Math.max(
      1,
      Number(body.capacity ?? body.seats ?? existing.capacity ?? 2) || 2,
    ),
    status:
      body.status != null
        ? normalizeTableStatus(body.status)
        : normalizeTableStatus(existing.status),
    sortOrder: Number(body.sortOrder ?? body.sort_order ?? existing.sortOrder ?? 0) || 0,
    updatedAt: new Date().toISOString(),
  };
}

function sessionHasItems(session) {
  const items = session?.cartItems || session?.items || [];
  return Array.isArray(items) && items.length > 0;
}

function statusFromActiveSession(session, fallback = 'available') {
  if (!session) return 'available';
  if (session.checkRequested === true || session.check_requested === true) {
    return 'awaiting_check';
  }
  if (session.waiterRequested === true || session.waiter_requested === true) {
    return 'waiter_call';
  }
  if (sessionHasItems(session)) return 'occupied';
  return fallback === 'reserved' ? 'reserved' : 'available';
}

function createOpenSession({ staffId, staffName, cartItems, notes } = {}) {
  return {
    id: `tsess_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
    openedAt: new Date().toISOString(),
    openedById: String(staffId || '').trim() || null,
    openedByName: String(staffName || '').trim() || 'كاشير',
    cartItems: Array.isArray(cartItems) ? cartItems : [],
    notes: String(notes || '').trim(),
    customerName: '',
    phone: '',
    kitchenOrderIds: [],
    currentOrderNumber: '',
    checkRequested: false,
    checkRequestedAt: null,
    tipAmount: 0,
    paymentMethod: '',
    billTotal: 0,
    waiterRequested: false,
    waiterNote: '',
    waiterRequestedAt: null,
    updatedAt: new Date().toISOString(),
  };
}

function ensureActiveSession(table, extras = {}) {
  if (table?.activeSession) return { ...table.activeSession, ...extras };
  return createOpenSession({
    staffId: extras.staffId || 'qr-guest',
    staffName: extras.staffName || 'زبون QR',
    cartItems: extras.cartItems || [],
    notes: extras.notes || '',
  });
}

function findRestaurantTableIndex(tables, restaurantId, tableKey) {
  const rid = String(restaurantId || '');
  const key = String(tableKey || '').trim();
  const keyLower = key.toLowerCase();
  return (tables || []).findIndex((table) => {
    if (String(table.restaurant_id || table.restaurantId) !== rid) return false;
    return (
      String(table.id) === key ||
      String(table.number) === key ||
      String(table.number || '').toLowerCase() === keyLower
    );
  });
}

function applyGuestOrderToTable(tables, {
  restaurantId,
  tableId,
  items,
  customerName,
  phone,
  orderId,
} = {}) {
  const index = findRestaurantTableIndex(tables, restaurantId, tableId);
  if (index < 0) return { tables, changed: false, table: null };
  const table = tables[index];
  if (
    normalizeTableStatus(table.status) === 'awaiting_check' ||
    table.activeSession?.checkRequested === true
  ) {
    return { tables, changed: false, table, locked: true };
  }
  const session = ensureActiveSession(table, {
    staffId: 'qr-guest',
    staffName: 'زبون QR',
  });
  const incoming = Array.isArray(items) ? items : [];
  const nextSession = {
    ...session,
    cartItems: [...(session.cartItems || []), ...incoming],
    customerName: String(customerName || session.customerName || '').trim(),
    phone: String(phone || session.phone || '').trim(),
    kitchenOrderIds: [...(session.kitchenOrderIds || []), orderId].filter(Boolean),
    currentOrderNumber: String(orderId || session.currentOrderNumber || '').trim(),
    updatedAt: new Date().toISOString(),
  };
  const nextTables = [...tables];
  nextTables[index] = {
    ...table,
    status: statusFromActiveSession(nextSession),
    activeSession: nextSession,
    updatedAt: new Date().toISOString(),
  };
  return { tables: nextTables, changed: true, table: nextTables[index] };
}

function sanitizeTableCustomer(table) {
  if (!table) return null;
  const session = table.activeSession || null;
  return {
    id: table.id,
    restaurantId: table.restaurant_id || table.restaurantId,
    number: table.number,
    name: table.name,
    zone: table.zone,
    capacity: table.capacity,
    status: normalizeTableStatus(table.status),
    waiterRequested: session?.waiterRequested === true,
    waiterNote: String(session?.waiterNote || ''),
    checkRequested: session?.checkRequested === true,
    activeSession: session
      ? {
          id: session.id,
          openedAt: session.openedAt || null,
          cartItems: Array.isArray(session.cartItems) ? session.cartItems : [],
          currentOrderNumber: String(session.currentOrderNumber || ''),
          checkRequested: session.checkRequested === true,
          checkRequestedAt: session.checkRequestedAt || null,
          tipAmount: Math.max(0, Number(session.tipAmount) || 0),
          paymentMethod: String(session.paymentMethod || ''),
          billTotal: Math.max(0, Number(session.billTotal) || 0),
          waiterRequested: session.waiterRequested === true,
          waiterNote: String(session.waiterNote || ''),
          updatedAt: session.updatedAt || null,
        }
      : null,
    hasActiveSession: Boolean(session),
    updatedAt: table.updatedAt,
  };
}

function sanitizeTablePublic(table) {
  if (!table) return null;
  return {
    id: table.id,
    restaurantId: table.restaurant_id || table.restaurantId,
    number: table.number,
    name: table.name,
    zone: table.zone,
    capacity: table.capacity,
    status: normalizeTableStatus(table.status),
    sortOrder: table.sortOrder || 0,
    activeSession: table.activeSession || null,
    createdAt: table.createdAt,
    updatedAt: table.updatedAt,
  };
}

function sortTables(tables) {
  return [...(tables || [])].sort((a, b) => {
    const zoneCmp = String(a.zone || '').localeCompare(String(b.zone || ''), 'ar');
    if (zoneCmp !== 0) return zoneCmp;
    const orderCmp = (Number(a.sortOrder) || 0) - (Number(b.sortOrder) || 0);
    if (orderCmp !== 0) return orderCmp;
    return String(a.number || '').localeCompare(String(b.number || ''), 'ar', {
      numeric: true,
    });
  });
}

module.exports = {
  TABLE_STATUSES,
  normalizeFeatures,
  isTableManagementEnabled,
  isKitchenManagementEnabled,
  isDeliveryManagementEnabled,
  isInventoryEnabled,
  normalizeTableStatus,
  createTableRecord,
  updateTableRecord,
  createOpenSession,
  ensureActiveSession,
  findRestaurantTableIndex,
  applyGuestOrderToTable,
  sessionHasItems,
  statusFromActiveSession,
  sanitizeTablePublic,
  sanitizeTableCustomer,
  sortTables,
};
