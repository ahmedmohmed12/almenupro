const PERMISSION_KEYS = {
  POS_ACCESS: 'pos_access',
  PROCESS_ORDERS: 'process_orders',
  PRINT_INVOICE: 'print_invoice',
  OPEN_CASH_DRAWER: 'open_cash_drawer',
  OVERRIDE_PRICES: 'override_prices',
  APPLY_MANUAL_DISCOUNT: 'apply_manual_discount',
  APPLY_DISCOUNTS: 'apply_discounts',
  VOID_ORDERS: 'void_orders',
  PROCESS_REFUNDS: 'process_refunds',
  VIEW_DAILY_SALES: 'view_daily_sales',
  VIEW_SHIFT_REPORTS: 'view_shift_reports',
  VIEW_REPORTS: 'view_reports',
  MANAGE_MENU: 'manage_menu',
  MANAGE_SETTINGS: 'manage_settings',
  MANAGE_STAFF: 'manage_staff',
  CLOSE_SHIFT: 'close_shift',
  MANAGER_OVERRIDE: 'manager_override',
};

const PERMISSION_CATALOG = [
  { key: PERMISSION_KEYS.POS_ACCESS, category: 'pos' },
  { key: PERMISSION_KEYS.PROCESS_ORDERS, category: 'pos' },
  { key: PERMISSION_KEYS.PRINT_INVOICE, category: 'pos' },
  { key: PERMISSION_KEYS.OPEN_CASH_DRAWER, category: 'pos' },
  { key: PERMISSION_KEYS.OVERRIDE_PRICES, category: 'pos' },
  { key: PERMISSION_KEYS.APPLY_MANUAL_DISCOUNT, category: 'pos' },
  { key: PERMISSION_KEYS.APPLY_DISCOUNTS, category: 'pos' },
  { key: PERMISSION_KEYS.CLOSE_SHIFT, category: 'pos' },
  { key: PERMISSION_KEYS.VOID_ORDERS, category: 'orders' },
  { key: PERMISSION_KEYS.PROCESS_REFUNDS, category: 'orders' },
  { key: PERMISSION_KEYS.MANAGE_STAFF, category: 'staff' },
  { key: PERMISSION_KEYS.VIEW_REPORTS, category: 'system' },
  { key: PERMISSION_KEYS.VIEW_DAILY_SALES, category: 'system' },
  { key: PERMISSION_KEYS.VIEW_SHIFT_REPORTS, category: 'system' },
  { key: PERMISSION_KEYS.MANAGE_MENU, category: 'system' },
  { key: PERMISSION_KEYS.MANAGE_SETTINGS, category: 'system' },
  { key: PERMISSION_KEYS.MANAGER_OVERRIDE, category: 'system' },
];

const ALL_PERMISSION_KEYS = PERMISSION_CATALOG.map((entry) => entry.key);

function fullAccessPermissions(enabled = true) {
  return Object.fromEntries(ALL_PERMISSION_KEYS.map((key) => [key, enabled]));
}

function ensureRolePermissions(role) {
  const permissions = { ...(role.permissions || {}) };
  for (const key of ALL_PERMISSION_KEYS) {
    if (permissions[key] === undefined) {
      permissions[key] = false;
    }
  }
  return { ...role, permissions };
}

function permissionAllowed(permissions, permissionKey) {
  if (!permissions || !permissionKey) return false;
  if (permissions[permissionKey] === true) return true;
  if (permissionKey === PERMISSION_KEYS.APPLY_MANUAL_DISCOUNT) {
    return permissions[PERMISSION_KEYS.APPLY_DISCOUNTS] === true;
  }
  if (permissionKey === PERMISSION_KEYS.VIEW_REPORTS) {
    return (
      permissions[PERMISSION_KEYS.VIEW_SHIFT_REPORTS] === true ||
      permissions[PERMISSION_KEYS.VIEW_DAILY_SALES] === true
    );
  }
  return false;
}

const DEFAULT_POS_ROLES = [
  {
    id: 'cashier',
    nameAr: 'كاشير',
    nameEn: 'Cashier',
    isBuiltIn: true,
    permissions: {
      [PERMISSION_KEYS.POS_ACCESS]: true,
      [PERMISSION_KEYS.PROCESS_ORDERS]: true,
      [PERMISSION_KEYS.PRINT_INVOICE]: true,
      [PERMISSION_KEYS.OPEN_CASH_DRAWER]: false,
      [PERMISSION_KEYS.OVERRIDE_PRICES]: false,
      [PERMISSION_KEYS.APPLY_MANUAL_DISCOUNT]: false,
      [PERMISSION_KEYS.APPLY_DISCOUNTS]: false,
      [PERMISSION_KEYS.VOID_ORDERS]: false,
      [PERMISSION_KEYS.PROCESS_REFUNDS]: false,
      [PERMISSION_KEYS.VIEW_DAILY_SALES]: false,
      [PERMISSION_KEYS.VIEW_SHIFT_REPORTS]: true,
      [PERMISSION_KEYS.VIEW_REPORTS]: true,
      [PERMISSION_KEYS.MANAGE_MENU]: false,
      [PERMISSION_KEYS.MANAGE_SETTINGS]: false,
      [PERMISSION_KEYS.MANAGE_STAFF]: false,
      [PERMISSION_KEYS.CLOSE_SHIFT]: true,
      [PERMISSION_KEYS.MANAGER_OVERRIDE]: false,
    },
  },
  {
    id: 'shift_supervisor',
    nameAr: 'مشرف وردية',
    nameEn: 'Shift Supervisor',
    isBuiltIn: true,
    permissions: {
      [PERMISSION_KEYS.POS_ACCESS]: true,
      [PERMISSION_KEYS.PROCESS_ORDERS]: true,
      [PERMISSION_KEYS.PRINT_INVOICE]: true,
      [PERMISSION_KEYS.OPEN_CASH_DRAWER]: true,
      [PERMISSION_KEYS.OVERRIDE_PRICES]: true,
      [PERMISSION_KEYS.APPLY_MANUAL_DISCOUNT]: true,
      [PERMISSION_KEYS.APPLY_DISCOUNTS]: true,
      [PERMISSION_KEYS.VOID_ORDERS]: true,
      [PERMISSION_KEYS.PROCESS_REFUNDS]: true,
      [PERMISSION_KEYS.VIEW_DAILY_SALES]: true,
      [PERMISSION_KEYS.VIEW_SHIFT_REPORTS]: true,
      [PERMISSION_KEYS.VIEW_REPORTS]: true,
      [PERMISSION_KEYS.MANAGE_MENU]: false,
      [PERMISSION_KEYS.MANAGE_SETTINGS]: false,
      [PERMISSION_KEYS.MANAGE_STAFF]: false,
      [PERMISSION_KEYS.CLOSE_SHIFT]: true,
      [PERMISSION_KEYS.MANAGER_OVERRIDE]: true,
    },
  },
  {
    id: 'pos_admin',
    nameAr: 'مدير POS',
    nameEn: 'POS Admin',
    isBuiltIn: true,
    permissions: fullAccessPermissions(true),
  },
];

function normalizePosRoles(raw) {
  if (!Array.isArray(raw) || raw.length === 0) {
    return DEFAULT_POS_ROLES.map((role) =>
      ensureRolePermissions({
        ...role,
        permissions: { ...role.permissions },
      }),
    );
  }

  const byId = new Map(
    DEFAULT_POS_ROLES.map((role) => [
      role.id,
      ensureRolePermissions({
        ...role,
        permissions: { ...role.permissions },
      }),
    ]),
  );

  for (const row of raw) {
    if (!row || typeof row !== 'object') continue;
    const id = String(row.id || '').trim();
    if (!id) continue;
    const base = byId.get(id) || {
      id,
      nameAr: String(row.nameAr || row.name_ar || id).trim(),
      nameEn: String(row.nameEn || row.name_en || id).trim(),
      isBuiltIn: false,
      permissions: {},
    };
    const permissions = { ...base.permissions, ...(row.permissions || {}) };
    byId.set(
      id,
      ensureRolePermissions({
        id,
        nameAr: String(row.nameAr || row.name_ar || base.nameAr || id).trim(),
        nameEn: String(row.nameEn || row.name_en || base.nameEn || id).trim(),
        isBuiltIn:
          row.isBuiltIn === true ||
          row.is_built_in === true ||
          base.isBuiltIn === true,
        permissions,
      }),
    );
  }

  const ordered = DEFAULT_POS_ROLES.map(
    (role) => byId.get(role.id) || ensureRolePermissions(role),
  );
  for (const [id, role] of byId.entries()) {
    if (!DEFAULT_POS_ROLES.some((entry) => entry.id === id)) {
      ordered.push(ensureRolePermissions(role));
    }
  }
  return ordered;
}

function findRoleById(roles, roleId) {
  const id = String(roleId || '').trim();
  return (roles || []).find((role) => String(role.id) === id) || null;
}

function roleHasPermission(role, permissionKey) {
  if (!role || !permissionKey) return false;
  return permissionAllowed(role.permissions, permissionKey);
}

function staffHasPermission(staff, roles, permissionKey) {
  if (!staff || staff.isActive === false) return false;
  const role = findRoleById(roles, staff.roleId);
  return roleHasPermission(role, permissionKey);
}

module.exports = {
  PERMISSION_KEYS,
  PERMISSION_CATALOG,
  ALL_PERMISSION_KEYS,
  DEFAULT_POS_ROLES,
  normalizePosRoles,
  ensureRolePermissions,
  permissionAllowed,
  findRoleById,
  roleHasPermission,
  staffHasPermission,
};
