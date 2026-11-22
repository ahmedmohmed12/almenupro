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

const HR_MANAGED_POS_ROLES = new Set(['cashier', 'shift_supervisor', 'driver', 'pos_admin']);

function isKitchenStaffRole(roleId) {
  return String(roleId || '').trim().toLowerCase() === 'kitchen';
}

function isHrManagedPosRole(roleId) {
  const role = String(roleId || '').trim().toLowerCase();
  if (isKitchenStaffRole(role)) return false;
  return HR_MANAGED_POS_ROLES.has(role) || role === 'cashier';
}

function sanitizeStaffPublic(entry) {
  const restaurantId = entry.restaurantId || entry.restaurant_id || '';
  const employeeId = String(entry.employeeId || entry.employee_id || '').trim() || null;
  return {
    id: entry.id,
    restaurantId,
    restaurant_id: restaurantId,
    restaurantName: entry.restaurantName || '',
    name: entry.name,
    roleId: entry.roleId || entry.role_id,
    employeeId,
    employee_id: employeeId,
    kitchenId: entry.kitchenId || entry.kitchen_id || null,
    kitchen_id: entry.kitchenId || entry.kitchen_id || null,
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
    restaurant_id: scopedRestaurantId,
    name: String(raw.name || '').trim(),
    roleId: String(raw.roleId || raw.role_id || 'cashier').trim(),
    kitchenId: String(raw.kitchenId || raw.kitchen_id || '').trim() || null,
    kitchen_id: String(raw.kitchenId || raw.kitchen_id || '').trim() || null,
    pinHash: pin ? hashPin(pin, scopedRestaurantId) : String(existingHash),
    employeeId: String(raw.employeeId || raw.employee_id || '').trim() || null,
    employee_id: String(raw.employeeId || raw.employee_id || '').trim() || null,
    isActive: raw.isActive !== false && raw.is_active !== false,
    createdAt: raw.createdAt || now,
    updatedAt: now,
  };
}

function assertHrPosStaffProvisioning(body = {}, record, { provisionSource = '' } = {}) {
  if (isKitchenStaffRole(record.roleId) || record.kitchenId || record.kitchen_id) {
    return record;
  }
  const source = String(
    provisionSource ||
      body.provisionSource ||
      body.provision_source ||
      body.source ||
      '',
  )
    .trim()
    .toLowerCase();
  if (source !== 'hr') {
    throw new Error(
      'إنشاء/تعيين الكاشير مسموح فقط من شؤون الموظفين (Staff / HR)',
    );
  }
  const employeeId = String(
    body.employeeId || body.employee_id || record.employeeId || '',
  ).trim();
  if (!employeeId) {
    throw new Error('ربط employeeId مطلوب لتعيين كاشير POS');
  }
  record.employeeId = employeeId;
  record.employee_id = employeeId;
  record.roleId = 'cashier';
  record.role_id = 'cashier';
  return record;
}

function createStaffRecord(body = {}, restaurantId, opts = {}) {
  const record = normalizeStaffUser(body, restaurantId);
  if (!record.name) {
    throw new Error('Staff name is required');
  }
  if (!record.pinHash) {
    throw new Error('Staff PIN is required');
  }
  if (isKitchenStaffRole(record.roleId) || record.kitchenId) {
    return record;
  }
  return assertHrPosStaffProvisioning(body, record, opts);
}

function updateStaffRecord(existing, body = {}, opts = {}) {
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
      employeeId:
        body.employeeId != null || body.employee_id != null
          ? body.employeeId || body.employee_id
          : existing.employeeId || existing.employee_id,
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
  const roleChanged = body.roleId != null || body.role_id != null;
  const employeeChanged = body.employeeId != null || body.employee_id != null;
  const hrProvision =
    String(
      opts.provisionSource ||
        body.provisionSource ||
        body.provision_source ||
        '',
    )
      .trim()
      .toLowerCase() === 'hr';
  if (hrProvision && (roleChanged || employeeChanged || !next.employeeId)) {
    if (isHrManagedPosRole(next.roleId) && !isKitchenStaffRole(next.roleId)) {
      return assertHrPosStaffProvisioning(body, next, opts);
    }
  }
  if (
    roleChanged &&
    isHrManagedPosRole(next.roleId) &&
    !isKitchenStaffRole(next.roleId) &&
    !next.employeeId
  ) {
    throw new Error('employeeId مطلوب لتعيين دور الكاشير');
  }
  return next;
}

function findStaffByPin(staffUsers, restaurantId, pin, roles = []) {
  const hash = hashPin(pin, restaurantId);
  return (staffUsers || []).find(
    (entry) =>
      String(entry.restaurantId || entry.restaurant_id) === String(restaurantId) &&
      entry.isActive !== false &&
      String(entry.roleId || entry.role_id || '').toLowerCase() !== 'kitchen' &&
      !entry.kitchenId &&
      !entry.kitchen_id &&
      String(entry.pinHash || entry.pin_hash) === hash,
  );
}

function findStaffByNameAndPin(staffUsers, restaurantId, cashierName, pin) {
  const name = String(cashierName || '').trim().toLowerCase();
  if (!name) return findStaffByPin(staffUsers, restaurantId, pin);
  const hash = hashPin(pin, restaurantId);
  return (staffUsers || []).find(
    (entry) =>
      String(entry.restaurantId || entry.restaurant_id) === String(restaurantId) &&
      entry.isActive !== false &&
      String(entry.name || '').trim().toLowerCase() === name &&
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
  isHrManagedPosRole,
  isKitchenStaffRole,
  assertHrPosStaffProvisioning,
  createStaffRecord,
  updateStaffRecord,
  findStaffByPin,
  findStaffByNameAndPin,
  resolveStaffPermissions,
  canStaffPerform,
  verifyManagerOverride,
  PERMISSION_KEYS,
};
