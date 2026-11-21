'use strict';

const { isPendingPaymentOrder, normalizePaymentStatus } = require('./orderPaymentStatus');
const { verifyManagerOverride } = require('./staffUsers');

function orderBelongsToShift(order, shiftId) {
  const sid = String(shiftId || '').trim();
  if (!sid) return false;
  const primary = String(order.shiftId || order.shift_id || '').trim();
  const held = String(order.heldShiftId || order.held_shift_id || '').trim();
  return primary === sid || held === sid;
}

function isPosWalkInSource(order) {
  if (order.createdFromPos === true || order.created_from_pos === true) return true;
  const source = String(order.orderSource || order.order_source || '').toLowerCase();
  return source.startsWith('pos') || source.includes('dine');
}

function isUnsettledPosPayment(order) {
  const lifecycle = String(order.status || '').toLowerCase();
  if (lifecycle === 'cancelled' || lifecycle === 'canceled') return false;
  const payment = normalizePaymentStatus(order.paymentStatus || order.payment_status);
  if (payment === 'paid') return false;
  if (payment === 'pending_payment') return true;
  const type = String(order.orderType || order.order_type || '').toLowerCase();
  const inProgress = new Set([
    'pending',
    'confirmed',
    'preparing',
    'ready',
    'inkitchen',
    'in_kitchen',
  ]);
  if ((type.includes('pickup') || type.includes('dine') || type === 'takeaway') && inProgress.has(lifecycle)) {
    return isPosWalkInSource(order);
  }
  return false;
}

function isPendingOnlineMenuOrder(order) {
  const lifecycle = String(order.status || '').toLowerCase();
  if (lifecycle !== 'pending') return false;
  if (order.isDemo === true || order.is_demo === true) return false;
  if (order.createdFromPos === true || order.created_from_pos === true) return false;
  const source = String(order.orderSource || order.order_source || '').toLowerCase();
  if (source.startsWith('pos')) return false;
  return true;
}

function classifyBlockingPendingOrder(order) {
  const type = String(order.orderType || order.order_type || '').toLowerCase();
  if (isPendingPaymentOrder(order)) {
    if (type.includes('dine')) return 'dine_in';
    return 'pickup';
  }
  if (type.includes('dine') && isUnsettledPosPayment(order)) return 'dine_in';
  if ((type.includes('pickup') || type === 'takeaway') && isUnsettledPosPayment(order)) {
    return 'pickup';
  }
  if (isPendingOnlineMenuOrder(order)) return 'online';
  return null;
}

function summarizeShiftPendingOrders(orders, shiftId) {
  const rows = [];
  for (const order of orders || []) {
    if (!orderBelongsToShift(order, shiftId)) continue;
    const kind = classifyBlockingPendingOrder(order);
    if (!kind) continue;
    rows.push({
      id: String(order.id || ''),
      kind,
      invoiceNumber: String(order.invoiceNumber || order.invoice_number || order.id || ''),
      customerName: String(order.customerName || order.customer_name || '').trim(),
      orderType: order.orderType || order.order_type || null,
      status: order.status || null,
    });
  }
  return {
    total: rows.length,
    pickup: rows.filter((row) => row.kind === 'pickup').length,
    dineIn: rows.filter((row) => row.kind === 'dine_in').length,
    online: rows.filter((row) => row.kind === 'online').length,
    orderIds: rows.map((row) => row.id),
    orders: rows,
  };
}

function shiftCloseGuardRoleCanBypass({ auth, body, isCashier, isRestaurantAdmin }) {
  if (isRestaurantAdmin(auth) || !isCashier(auth)) return true;
  const roleId = String(
    body.roleId ||
      body.role_id ||
      auth.staffRoleId ||
      auth.roleId ||
      auth.role ||
      '',
  )
    .trim()
    .toLowerCase();
  return roleId === 'shift_supervisor' || roleId === 'pos_admin' || roleId === 'manager';
}

async function enforceShiftClosePendingGuard({
  shift,
  orders,
  body,
  auth,
  staffUsers,
  roles,
  restaurantRecord,
  isCashier,
  isRestaurantAdmin,
  deps,
}) {
  const summary = summarizeShiftPendingOrders(orders, shift.id);
  if (summary.total === 0) {
    return { ok: true, summary, cleared: true };
  }

  const reason = String(
    body.pendingCloseReason ||
      body.pending_close_reason ||
      body.forceCloseReason ||
      body.force_close_reason ||
      '',
  ).trim();

  const canBypass = shiftCloseGuardRoleCanBypass({
    auth,
    body,
    isCashier,
    isRestaurantAdmin,
  });

  if (canBypass) {
    if (!reason) {
      return {
        ok: false,
        status: 409,
        code: 'PENDING_CLOSE_REASON_REQUIRED',
        error: 'أدخل سبب إغلاق الوردية مع وجود طلبات معلّقة',
        summary,
      };
    }
    return {
      ok: true,
      summary,
      cleared: false,
      bypassRole: true,
      reason,
    };
  }

  const approvalRequestId = String(
    body.approvalRequestId || body.approval_request_id || '',
  ).trim();
  if (
    approvalRequestId &&
    deps &&
    typeof deps.resolveRemoteApproval === 'function'
  ) {
    const remote = await deps.resolveRemoteApproval({
      approvalRequestId,
      restaurantId: shift.restaurantId || shift.restaurant_id,
      type: 'CLOSE_SHIFT_PENDING_ORDERS',
      context: { shiftId: shift.id, summary },
      consume: true,
    });
    if (remote.ok) {
      const remoteReason = String(remote.reason || reason || '').trim();
      if (!remoteReason) {
        return {
          ok: false,
          status: 400,
          code: 'PENDING_CLOSE_REASON_REQUIRED',
          error: 'أدخل سبب إغلاق الوردية مع الطلبات المعلّقة',
          summary,
        };
      }
      return {
        ok: true,
        summary,
        cleared: false,
        override: remote.authorizedBy,
        reason: remoteReason,
        remoteApprovalId: approvalRequestId,
      };
    }
    if (remote.code && remote.code !== 'APPROVAL_NOT_FOUND') {
      return {
        ok: false,
        status: remote.code === 'APPROVAL_NOT_APPROVED' ? 409 : 403,
        code: remote.code,
        error: remote.error,
        summary,
      };
    }
  }

  const pin = String(body.managerPin || body.manager_pin || body.pin || '').trim();
  const override = verifyManagerOverride({
    staffUsers,
    restaurantId: shift.restaurantId || shift.restaurant_id,
    pin,
    roles,
    restaurantRecord,
  });

  if (!override.authorized) {
    return {
      ok: false,
      status: 403,
      code: 'PENDING_ORDERS_APPROVAL_REQUIRED',
      error: 'لا يمكن إغلاق الوردية مع طلبات معلّقة دون موافقة مشرف أو مدير',
      summary,
    };
  }

  const approverRole = String(override.roleId || '').toLowerCase();
  const allowedApprover =
    approverRole === 'shift_supervisor' ||
    approverRole === 'pos_admin' ||
    approverRole === 'manager' ||
    override.source === 'restaurant_admin';

  if (!allowedApprover) {
    return {
      ok: false,
      status: 403,
      code: 'PENDING_ORDERS_APPROVAL_REQUIRED',
      error: 'يجب إدخال PIN لمشرف وردية أو مدير POS',
      summary,
    };
  }

  if (!reason) {
    return {
      ok: false,
      status: 400,
      code: 'PENDING_CLOSE_REASON_REQUIRED',
      error: 'أدخل سبب إغلاق الوردية مع الطلبات المعلّقة',
      summary,
    };
  }

  return {
    ok: true,
    summary,
    cleared: false,
    override,
    reason,
  };
}

module.exports = {
  orderBelongsToShift,
  summarizeShiftPendingOrders,
  enforceShiftClosePendingGuard,
  classifyBlockingPendingOrder,
};