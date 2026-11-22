'use strict';

const {
  normalizePosRoles,
  findRoleById,
  permissionAllowed,
  PERMISSION_KEYS,
} = require('./posPermissions');
const { resolveStaffPermissions, verifyManagerOverride } = require('./staffUsers');
const { buildAuditEvent } = require('./auditLog');
const { isRestaurantAdmin, isCashier } = require('./adminAuth');

const KITCHEN_VOID_REASONS = [
  'customer_request',
  'entry_mistake',
  'preparation_delay',
  'out_of_stock',
  'kitchen_unable',
  'other',
];

function parsePosSettings(settings = {}) {
  return {
    posRoles: normalizePosRoles(settings.posRoles || settings.pos_roles),
  };
}

function isItemSentToKitchen(item) {
  if (!item || typeof item !== 'object') return false;
  return item.isSentToKitchen === true || item.is_sent_to_kitchen === true;
}

function normalizeKitchenLine(item) {
  const quantity = Math.max(1, Number(item.quantity) || 1);
  const unitPrice = Number(item.unitPrice ?? item.unit_price ?? item.price) || 0;
  return {
    ...item,
    id: String(item.id || '').trim(),
    menuItemId: String(
      item.menuItemId ?? item.menu_item_id ?? item.menuItem?.id ?? '',
    ),
    name: String(item.name || item.menuItem?.name || 'صنف').trim() || 'صنف',
    unitPrice,
    quantity,
    selectedOptions: Array.isArray(item.selectedOptions)
      ? item.selectedOptions
      : [],
    specialNotes: String(item.specialNotes ?? item.special_notes ?? '').trim(),
    isSentToKitchen: isItemSentToKitchen(item),
    is_sent_to_kitchen: isItemSentToKitchen(item),
    sentToKitchenAt:
      item.sentToKitchenAt || item.sent_to_kitchen_at || null,
    sent_to_kitchen_at:
      item.sent_to_kitchen_at || item.sentToKitchenAt || null,
    lineTotal:
      Number(item.lineTotal ?? item.line_total ?? unitPrice * quantity) ||
      unitPrice * quantity,
  };
}

function mergeKitchenSentFromPrevious(previousItems, nextItems) {
  const prev = (Array.isArray(previousItems) ? previousItems : []).map(normalizeKitchenLine);
  const prevByKey = new Map(prev.map((line) => [lineIdKey(line), line]));
  return (Array.isArray(nextItems) ? nextItems : []).map((raw) => {
    const line = normalizeKitchenLine(raw);
    const before = prevByKey.get(lineIdKey(line));
    if (!before?.isSentToKitchen || line.isSentToKitchen) {
      return line;
    }
    const sentAt = before.sentToKitchenAt || before.sent_to_kitchen_at || null;
    return {
      ...line,
      isSentToKitchen: true,
      is_sent_to_kitchen: true,
      sentToKitchenAt: sentAt,
      sent_to_kitchen_at: sentAt,
    };
  });
}

function stampKitchenSent(items, { sentAt, onlyUnsent = true } = {}) {
  const ts = sentAt || new Date().toISOString();
  return (Array.isArray(items) ? items : []).map((raw) => {
    const item = normalizeKitchenLine(raw);
    if (onlyUnsent && item.isSentToKitchen) {
      return item;
    }
    return {
      ...item,
      isSentToKitchen: true,
      is_sent_to_kitchen: true,
      sentToKitchenAt: ts,
      sent_to_kitchen_at: ts,
    };
  });
}

function lineIdKey(item) {
  const id = String(item.id || '').trim();
  if (id) return `id:${id}`;
  return `menu:${item.menuItemId}:${item.name}:${JSON.stringify(item.selectedOptions || [])}`;
}

function optionsSignature(options) {
  return JSON.stringify(
    (Array.isArray(options) ? options : []).map((entry) => ({
      g: entry.group,
      n: entry.name,
      p: Number(entry.price) || 0,
    })),
  );
}

function itemContentChanged(previous, next) {
  if (String(previous.menuItemId) !== String(next.menuItemId)) return true;
  if (String(previous.name) !== String(next.name)) return true;
  if (Math.abs(Number(previous.unitPrice) - Number(next.unitPrice)) > 0.0005) {
    return true;
  }
  if (optionsSignature(previous.selectedOptions) !== optionsSignature(next.selectedOptions)) {
    return true;
  }
  if (String(previous.specialNotes || '') !== String(next.specialNotes || '')) {
    return true;
  }
  return false;
}

function detectKitchenLockViolations(previousItems, nextItems) {
  const prev = (Array.isArray(previousItems) ? previousItems : []).map(
    normalizeKitchenLine,
  );
  const next = (Array.isArray(nextItems) ? nextItems : []).map(normalizeKitchenLine);
  const nextByKey = new Map();
  for (const line of next) {
    nextByKey.set(lineIdKey(line), line);
  }

  const violations = [];
  for (const before of prev) {
    if (!before.isSentToKitchen) continue;
    const after = nextByKey.get(lineIdKey(before)) || null;
    if (!after) {
      violations.push({
        type: 'remove',
        itemId: before.id,
        menuItemId: before.menuItemId,
        name: before.name,
        quantityBefore: before.quantity,
        quantityAfter: 0,
        unitPrice: before.unitPrice,
      });
      continue;
    }
    if (after.quantity < before.quantity) {
      violations.push({
        type: 'reduce',
        itemId: before.id,
        menuItemId: before.menuItemId,
        name: before.name,
        quantityBefore: before.quantity,
        quantityAfter: after.quantity,
        unitPrice: before.unitPrice,
      });
    }
    if (itemContentChanged(before, after)) {
      violations.push({
        type: 'modify',
        itemId: before.id,
        menuItemId: before.menuItemId,
        name: before.name,
        quantityBefore: before.quantity,
        quantityAfter: after.quantity,
        unitPrice: before.unitPrice,
      });
    }
  }
  return violations;
}

function performerFromBody(body, staffUsers) {
  const performedById = String(
    body.performedById || body.performed_by_id || body.cashierId || body.cashier_id || '',
  ).trim();
  if (!performedById) return null;
  return (staffUsers || []).find((entry) => String(entry.id) === performedById) || null;
}

function staffBypassesKitchenLock({ auth, performer, permissions, posRoles }) {
  if (!auth) return false;
  if (isRestaurantAdmin(auth) || !isCashier(auth)) return true;
  const roleId = String(
    performer?.roleId || performer?.role_id || auth.staffRoleId || auth.roleId || '',
  ).trim();
  if (roleId === 'shift_supervisor' || roleId === 'pos_admin') {
    return true;
  }
  const role = findRoleById(posRoles, roleId);
  const merged = resolveStaffPermissions(performer || { roleId }, posRoles);
  if (permissionAllowed(merged, PERMISSION_KEYS.VOID_ORDERS)) return true;
  if (permissionAllowed(merged, PERMISSION_KEYS.MANAGER_OVERRIDE)) return true;
  if (role?.id === 'shift_supervisor' || role?.id === 'pos_admin') return true;
  return false;
}

function buildKitchenVoidAudit({
  restaurantId,
  context,
  violations,
  performedBy,
  authorizedBy,
  reason,
}) {
  return buildAuditEvent({
    restaurantId,
    action: 'kitchen_line_void',
    entityType: context.entityType || 'order',
    entityId: context.entityId || '',
    performedById: performedBy?.id || 'cashier',
    performedByName: performedBy?.name || 'Cashier',
    authorizedById: authorizedBy?.staffId || authorizedBy?.id || null,
    authorizedByName: authorizedBy?.staffName || authorizedBy?.name || null,
    metadata: {
      orderType: context.orderType || null,
      reason: String(reason || '').slice(0, 300),
      violations,
      notifyKitchen: true,
    },
  });
}

function stampOrderKitchenVoidNotice(order, violations) {
  if (!order || !violations?.length) return order;
  const now = new Date().toISOString();
  return {
    ...order,
    kitchenVoidAt: now,
    kitchen_void_at: now,
    kitchenVoidRevision:
      (Number(order.kitchenVoidRevision || order.kitchen_void_revision || 0) || 0) + 1,
    kitchen_void_revision:
      (Number(order.kitchenVoidRevision || order.kitchen_void_revision || 0) || 0) + 1,
    updatedAt: now,
  };
}

async function enforceKitchenItemMutation({
  previousItems,
  nextItems,
  body = {},
  auth,
  restaurantId,
  deps,
  context = {},
}) {
  const violations = detectKitchenLockViolations(previousItems, nextItems);
  if (violations.length === 0) {
    return { ok: true, violations, auditEvents: [] };
  }

  const settings = await deps.readSettings(restaurantId);
  const { posRoles } = parsePosSettings(settings);
  const staffUsers = deps.filterByRestaurant(
    await deps.readStaffUsers(),
    restaurantId,
  );
  const performer = performerFromBody(body, staffUsers);
  const permissions = resolveStaffPermissions(performer || {}, posRoles);

  if (staffBypassesKitchenLock({ auth, performer, permissions, posRoles })) {
    const auditEvents = [
      buildKitchenVoidAudit({
        restaurantId,
        context,
        violations,
        performedBy: performer,
        authorizedBy: {
          staffId: performer?.id,
          staffName: performer?.name,
        },
        reason: body.kitchenVoidReason || body.reason || 'supervisor_self',
      }),
    ];
    return {
      ok: true,
      violations,
      auditEvents,
      selfAuthorized: true,
      reason: body.kitchenVoidReason || body.reason || 'supervisor_self',
      performer,
    };
  }

  let reason = String(
    body.kitchenVoidReason || body.kitchen_void_reason || body.voidReason || body.reason || '',
  ).trim();
  const approvalRequestId = String(
    body.approvalRequestId || body.approval_request_id || '',
  ).trim();
  if (approvalRequestId && typeof deps.resolveRemoteApproval === 'function') {
    const remote = await deps.resolveRemoteApproval({
      approvalRequestId,
      restaurantId,
      type: 'VOID_SENT_ITEM',
      context: {
        entityId: context?.entityId,
        orderId: context?.entityId,
        cartItemId:
          body.cartItemId ||
          body.cart_item_id ||
          body.itemId ||
          body.item_id ||
          context?.cartItemId,
        itemId: body.itemId || body.item_id || context?.itemId,
      },
      consume: true,
    });
    if (remote.ok) {
      const auditEvents = [
        buildKitchenVoidAudit({
          restaurantId,
          context,
          violations,
          performedBy: performer,
          authorizedBy: remote.authorizedBy,
          reason: remote.reason || reason || 'remote_approval',
        }),
      ];
      return {
        ok: true,
        violations,
        auditEvents,
        authorizedBy: remote.authorizedBy,
        reason: remote.reason || reason,
        remoteApprovalId: approvalRequestId,
        performer,
      };
    }
    if (remote.code && remote.code !== 'APPROVAL_NOT_FOUND') {
      return {
        ok: false,
        status: remote.code === 'APPROVAL_NOT_APPROVED' ? 409 : 403,
        code: remote.code,
        error: remote.error,
        violations,
      };
    }
  }

  if (!reason) {
    return {
      ok: false,
      status: 400,
      code: 'KITCHEN_VOID_REASON_REQUIRED',
      error: 'سبب إلغاء/تعديل صنف المطبخ مطلوب',
      violations,
    };
  }

  const pin = String(body.managerPin || body.manager_pin || body.pin || '').trim();
  if (!pin) {
    const auditEvents = [
      buildKitchenVoidAudit({
        restaurantId,
        context,
        violations,
        performedBy: performer,
        authorizedBy: null,
        reason,
      }),
    ];
    return {
      ok: true,
      violations,
      auditEvents,
      reason,
      conditionalVoid: true,
      performer,
    };
  }
  const restaurants = await deps.readRestaurants();
  const restaurantRecord = (restaurants || []).find(
    (entry) => String(entry.id) === String(restaurantId),
  );
  const override = verifyManagerOverride({
    staffUsers,
    restaurantId,
    pin,
    roles: posRoles,
    restaurantRecord,
  });
  if (!override.authorized) {
    return {
      ok: false,
      status: 403,
      code: 'KITCHEN_DISPATCH_LOCK',
      error:
        'المشرف أو مدير الفرع يجب أن يفوّض إزالة/تعديل أصناف أُرسلت للمطبخ',
      violations,
    };
  }

  const auditEvents = [
    buildKitchenVoidAudit({
      restaurantId,
      context,
      violations,
      performedBy: performer,
      authorizedBy: override,
      reason,
    }),
  ];

  return {
    ok: true,
    violations,
    auditEvents,
    authorizedBy: override,
    reason,
    performer,
  };
}

module.exports = {
  KITCHEN_VOID_REASONS,
  isItemSentToKitchen,
  normalizeKitchenLine,
  stampKitchenSent,
  mergeKitchenSentFromPrevious,
  detectKitchenLockViolations,
  enforceKitchenItemMutation,
  stampOrderKitchenVoidNotice,
  staffBypassesKitchenLock,
  performerFromBody,
};