'use strict';

const APPROVAL_TYPES = Object.freeze({
  VOID_SENT_ITEM: 'VOID_SENT_ITEM',
  CLOSE_SHIFT_PENDING_ORDERS: 'CLOSE_SHIFT_PENDING_ORDERS',
});

const APPROVAL_STATUSES = Object.freeze({
  PENDING: 'PENDING',
  APPROVED: 'APPROVED',
  REJECTED: 'REJECTED',
  EXPIRED: 'EXPIRED',
});

const APPROVER_ROLES = new Set(['manager', 'shift_supervisor', 'pos_admin']);

const DEFAULT_TTL_MS = 30 * 60 * 1000;

function nowIso() {
  return new Date().toISOString();
}

function normalizeApprovalRequest(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    id: String(row.id || ''),
    restaurantId: String(row.restaurantId || row.restaurant_id || ''),
    restaurantSlug: String(row.restaurantSlug || row.restaurant_slug || ''),
    shiftId: String(row.shiftId || row.shift_id || ''),
    type: String(row.type || '').toUpperCase(),
    status: String(row.status || APPROVAL_STATUSES.PENDING).toUpperCase(),
    requestedById: String(row.requestedById || row.requested_by_id || ''),
    requestedByName: String(row.requestedByName || row.requested_by_name || ''),
    reason: String(row.reason || '').trim(),
    payload: row.payload && typeof row.payload === 'object' ? row.payload : {},
    reviewedById: String(row.reviewedById || row.reviewed_by_id || '').trim() || null,
    reviewedByName: String(row.reviewedByName || row.reviewed_by_name || '').trim() || null,
    reviewNote: String(row.reviewNote || row.review_note || '').trim() || null,
    createdAt: row.createdAt || row.created_at || nowIso(),
    reviewedAt: row.reviewedAt || row.reviewed_at || null,
    consumedAt: row.consumedAt || row.consumed_at || null,
    expiresAt: row.expiresAt || row.expires_at || null,
  };
}

function approvalRoleCanReview(roleId, isRestaurantAdmin) {
  if (isRestaurantAdmin) return true;
  const role = String(roleId || '').trim().toLowerCase();
  return APPROVER_ROLES.has(role);
}

function expireStalePending(request) {
  const normalized = normalizeApprovalRequest(request);
  if (!normalized) return null;
  if (normalized.status !== APPROVAL_STATUSES.PENDING) return normalized;
  const expiresAt = normalized.expiresAt
    ? Date.parse(normalized.expiresAt)
    : Date.parse(normalized.createdAt) + DEFAULT_TTL_MS;
  if (Number.isFinite(expiresAt) && Date.now() > expiresAt) {
    return {
      ...normalized,
      status: APPROVAL_STATUSES.EXPIRED,
    };
  }
  return normalized;
}

function buildPendingSummaryPayload(summary) {
  return {
    total: Number(summary?.total || 0),
    pickup: Number(summary?.pickup || 0),
    dineIn: Number(summary?.dineIn || summary?.dine_in || 0),
    online: Number(summary?.online || 0),
    orderIds: Array.isArray(summary?.orderIds) ? summary.orderIds : [],
    orders: Array.isArray(summary?.orders) ? summary.orders : [],
  };
}

function createApprovalRequestRecord({
  id,
  restaurantId,
  restaurantSlug,
  shiftId,
  type,
  requestedById,
  requestedByName,
  reason,
  payload,
}) {
  const normalizedType = String(type || '').toUpperCase();
  if (!Object.values(APPROVAL_TYPES).includes(normalizedType)) {
    const error = new Error('Invalid approval type');
    error.statusCode = 400;
    throw error;
  }
  const trimmedReason = String(reason || '').trim();
  if (trimmedReason.length < 3) {
    const error = new Error('سبب الطلب مطلوب');
    error.statusCode = 400;
    throw error;
  }
  const createdAt = nowIso();
  const expiresAt = new Date(Date.parse(createdAt) + DEFAULT_TTL_MS).toISOString();
  return normalizeApprovalRequest({
    id,
    restaurantId,
    restaurantSlug,
    shiftId: String(shiftId || '').trim(),
    type: normalizedType,
    status: APPROVAL_STATUSES.PENDING,
    requestedById,
    requestedByName,
    reason: trimmedReason,
    payload: payload || {},
    createdAt,
    expiresAt,
  });
}

function payloadMatchesVoidContext(payload, context) {
  const orderId = String(context?.entityId || context?.orderId || '').trim();
  const payloadOrderId = String(payload?.orderId || payload?.order_id || '').trim();
  if (orderId && payloadOrderId && orderId !== payloadOrderId) return false;
  const cartItemId = String(
    context?.cartItemId || context?.itemId || context?.lineId || '',
  ).trim();
  const payloadItemId = String(
    payload?.cartItemId || payload?.itemId || payload?.lineId || '',
  ).trim();
  if (cartItemId && payloadItemId && cartItemId !== payloadItemId) return false;
  return true;
}

function payloadMatchesShiftCloseContext(payload, context) {
  const shiftId = String(context?.shiftId || '').trim();
  const payloadShiftId = String(payload?.shiftId || payload?.shift_id || '').trim();
  if (shiftId && payloadShiftId && shiftId !== payloadShiftId) return false;
  return true;
}

function validateApprovedForUse(request, { restaurantId, type, context }) {
  const row = expireStalePending(request);
  if (!row) {
    return { ok: false, code: 'APPROVAL_NOT_FOUND', error: 'طلب الموافقة غير موجود' };
  }
  if (row.status === APPROVAL_STATUSES.EXPIRED) {
    return { ok: false, code: 'APPROVAL_EXPIRED', error: 'انتهت صلاحية طلب الموافقة' };
  }
  if (row.status !== APPROVAL_STATUSES.APPROVED) {
    return { ok: false, code: 'APPROVAL_NOT_APPROVED', error: 'طلب الموافقة غير معتمد بعد' };
  }
  if (row.consumedAt) {
    return { ok: false, code: 'APPROVAL_ALREADY_USED', error: 'تم استخدام طلب الموافقة مسبقاً' };
  }
  if (String(row.restaurantId) !== String(restaurantId)) {
    return { ok: false, code: 'APPROVAL_SCOPE_MISMATCH', error: 'طلب الموافقة لا ينتمي لهذا الفرع' };
  }
  const normalizedType = String(type || '').toUpperCase();
  if (row.type !== normalizedType) {
    return { ok: false, code: 'APPROVAL_TYPE_MISMATCH', error: 'نوع طلب الموافقة غير متطابق' };
  }
  if (normalizedType === APPROVAL_TYPES.VOID_SENT_ITEM) {
    if (!payloadMatchesVoidContext(row.payload, context || {})) {
      return {
        ok: false,
        code: 'APPROVAL_CONTEXT_MISMATCH',
        error: 'طلب الموافقة لا يطابق الطلب/الصنف الحالي',
      };
    }
  }
  if (normalizedType === APPROVAL_TYPES.CLOSE_SHIFT_PENDING_ORDERS) {
    if (!payloadMatchesShiftCloseContext(row.payload, context || {})) {
      return {
        ok: false,
        code: 'APPROVAL_CONTEXT_MISMATCH',
        error: 'طلب الموافقة لا يطابق الوردية الحالية',
      };
    }
  }
  return {
    ok: true,
    request: row,
    authorizedBy: {
      staffId: row.reviewedById,
      staffName: row.reviewedByName,
      roleId: row.payload?.reviewedRoleId || null,
      source: 'remote_approval',
    },
    reason: row.reason,
  };
}

async function resolveRemoteApproval({
  approvalRequestId,
  restaurantId,
  type,
  context,
  readApprovalRequests,
  writeApprovalRequests,
  consume = true,
}) {
  const id = String(approvalRequestId || '').trim();
  if (!id) return { ok: false };

  const rows = await readApprovalRequests();
  const index = rows.findIndex((entry) => String(entry.id) === id);
  if (index === -1) {
    return { ok: false, code: 'APPROVAL_NOT_FOUND', error: 'طلب الموافقة غير موجود' };
  }

  const validation = validateApprovedForUse(rows[index], { restaurantId, type, context });
  if (!validation.ok) return validation;

  if (consume) {
    rows[index] = {
      ...normalizeApprovalRequest(rows[index]),
      consumedAt: nowIso(),
    };
    await writeApprovalRequests(rows);
  }

  return validation;
}

module.exports = {
  APPROVAL_TYPES,
  APPROVAL_STATUSES,
  APPROVER_ROLES,
  DEFAULT_TTL_MS,
  normalizeApprovalRequest,
  approvalRoleCanReview,
  expireStalePending,
  buildPendingSummaryPayload,
  createApprovalRequestRecord,
  validateApprovedForUse,
  resolveRemoteApproval,
};