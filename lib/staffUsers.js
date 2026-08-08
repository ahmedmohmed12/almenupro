const crypto = require('crypto');
const {
  normalizePosRoles,
  findRoleById,
  staffHasPermission,
  PERMISSION_KEYS,
} = require('./posPermissions');

function hashPin(pin, restaurantId = '') {
  return crypto
    .createHash('sha256')
    .update(`${String(restaurantId)}:${String(pin || '').trim()}`)
    .digest('hex');
}

function verifyPin(pin, pinHash, restaurantId = '') {
  if (!pinHash) return false;
  return hashPin(pin, restaurantId) === String(pinHash);
}

function sanitizeStaffPublic(entry) {
  return {
    id: entry.id,
    restaurantId: entry.restaurantId || entry.restaurant_id,
    name: entry.name,
    roleId: entry.roleId || entry.role_id,
    isActive: entry.isActive !== false,
    createdAt: entry.createdAt || null,
    updatedAt: entry.updatedAt || null,
  };
}

function normalizeStaffUser(raw, restaurantId) {
  const id =
    String(raw.id || '').trim() ||
    `staff_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
  const scopedRestaurantId =
    raw.restaurantId || raw.restaurant_id || restaurantId || '';
  const pin = String(raw.pin || raw.pinCode || raw.pin_code || '').trim();
  const existingHash = raw.pinHash || raw.pin_hash || '';
  const now = new Date().toISOString();

  return {
    id,
    restaurantId: scopedRestaurantId,
    name: String(raw.name || '').trim(),
    roleId: String(raw.roleId || raw.role_id || 'cashier').trim(),
    pinHash: pin ? hashPin(pin, scopedRestaurantId) : String(existingHash),
    isActive: raw.isActive !== false && raw.is_active !== false,
    createdAt: raw.createdAt || now,
    updatedAt: now,
  };
}

function createStaffRecord(body = {}, restaurantId) {
  const record = normalizeStaffUser(body, restaurantId);
  if (!record.name) {
    throw new Error('Staff name is required');
  }
  if (!record.pinHash) {
    throw new Error('Staff PIN is required');
  }
  return record;
}

function updateStaffRecord(existing, body = {}) {
  if (!existing?.id) {
    throw new Error('Staff user not found');
  }
  const pinProvided =
    body.pin != null ||
    body.pinCode != null ||
    body.pin_code != null;
  const next = normalizeStaffUser(
    {
      ...existing,
      ...body,
      id: existing.id,
      restaurantId: existing.restaurantId || existing.restaurant_id,
      pinHash: pinProvided ? undefined : existing.pinHash || existing.pin_hash,
      createdAt: existing.createdAt,
    },
    existing.restaurantId || existing.restaurant_id,
  );
  if (!next.name) {
    throw new Error('Staff name is required');
  }
  if (!next.pinHash) {
    throw new Error('Staff PIN is required');
  }
  return next;
}

function findStaffByPin(staffUsers, restaurantId, pin, roles = []) {
  const hash = hashPin(pin, restaurantId);
  return (staffUsers || []).find(
    (entry) =>
      String(entry.restaurantId || entry.restaurant_id) === String(restaurantId) &&
      entry.isActive !== false &&
      String(entry.pinHash || entry.pin_hash) === hash,
  );
}

function resolveStaffPermissions(staff, roles) {
  const role = findRoleById(roles, staff?.roleId || staff?.role_id);
  return role?.permissions || {};
}

function canStaffPerform(staff, roles, permissionKey) {
  return staffHasPermission(staff, roles, permissionKey);
}

function verifyManagerOverride({
  staffUsers,
  restaurantId,
  pin,
  roles,
  restaurantRecord,
}) {
  const staff = findStaffByPin(staffUsers, restaurantId, pin, roles);
  if (
    staff &&
    canStaffPerform(staff, roles, PERMISSION_KEYS.MANAGER_OVERRIDE)
  ) {
    return {
      authorized: true,
      staffId: staff.id,
      staffName: staff.name,
      roleId: staff.roleId || staff.role_id,
      source: 'staff',
    };
  }

  if (
    restaurantRecord &&
    String(pin || '') === String(restaurantRecord.adminPassword || '')
  ) {
    return {
      authorized: true,
      staffId: 'restaurant_admin',
      staffName: restaurantRecord.name || 'Restaurant Admin',
      roleId: 'pos_admin',
      source: 'restaurant_admin',
    };
  }

  return { authorized: false };
}

module.exports = {
  hashPin,
  verifyPin,
  sanitizeStaffPublic,
  normalizeStaffUser,
  createStaffRecord,
  updateStaffRecord,
  findStaffByPin,
  resolveStaffPermissions,
  canStaffPerform,
  verifyManagerOverride,
  PERMISSION_KEYS,
};
