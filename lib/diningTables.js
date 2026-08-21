'use strict';

const { ensureRestaurantId } = require('./tenantStore');

const TABLE_STATUSES = ['available', 'occupied', 'reserved'];

function normalizeFeatures(raw = {}) {
  const source = raw && typeof raw === 'object' ? raw : {};
  return {
    tableManagement:
      source.tableManagement === true || source.table_management === true,
  };
}

function isTableManagementEnabled(restaurant) {
  return normalizeFeatures(restaurant?.features).tableManagement;
}

function normalizeTableStatus(raw) {
  const value = String(raw || 'available').trim().toLowerCase();
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

function createOpenSession({ staffId, staffName, cartItems = [], notes = '' }) {
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
    updatedAt: new Date().toISOString(),
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
  normalizeTableStatus,
  createTableRecord,
  updateTableRecord,
  createOpenSession,
  sanitizeTablePublic,
  sortTables,
};
