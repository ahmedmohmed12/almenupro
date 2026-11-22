'use strict';

const { randomUUID } = require('crypto');
const { normalizeKitchenLine } = require('./kitchenDispatchLock');

const APPROVAL_STATUSES = Object.freeze({
  PENDING: 'PENDING',
  APPROVED: 'APPROVED',
  REJECTED: 'REJECTED',
});

function nowIso() {
  return new Date().toISOString();
}

function money(value) {
  return Number(Number(value || 0).toFixed(3));
}

function normalizeKitchenVoidLiability(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    id: String(row.id || ''),
    restaurantId: String(row.restaurantId || row.restaurant_id || ''),
    shiftId: String(row.shiftId || row.shift_id || ''),
    orderId: String(row.orderId || row.order_id || ''),
    entityType: String(row.entityType || row.entity_type || 'order'),
    entityId: String(row.entityId || row.entity_id || ''),
    cashierId: String(row.cashierId || row.cashier_id || ''),
    cashierName: String(row.cashierName || row.cashier_name || ''),
    itemId: String(row.itemId || row.item_id || ''),
    menuItemId: String(row.menuItemId || row.menu_item_id || ''),
    itemName: String(row.itemName || row.item_name || ''),
    violationType: String(row.violationType || row.violation_type || ''),
    quantityBefore: Number(row.quantityBefore ?? row.quantity_before ?? 0) || 0,
    quantityAfter: Number(row.quantityAfter ?? row.quantity_after ?? 0) || 0,
    quantityRemoved: Number(row.quantityRemoved ?? row.quantity_removed ?? 0) || 0,
    unitPrice: money(row.unitPrice ?? row.unit_price ?? 0),
    amount: money(row.amount ?? 0),
    sentToKitchenAt: row.sentToKitchenAt || row.sent_to_kitchen_at || null,
    voidedAt: row.voidedAt || row.voided_at || nowIso(),
    elapsedMinutes:
      row.elapsedMinutes == null && row.elapsed_minutes == null
        ? null
        : Number(row.elapsedMinutes ?? row.elapsed_minutes ?? 0),
    reason: String(row.reason || '').trim(),
    approvalStatus: String(
      row.approvalStatus || row.approval_status || APPROVAL_STATUSES.PENDING,
    ).toUpperCase(),
    reviewedById: String(row.reviewedById || row.reviewed_by_id || '').trim() || null,
    reviewedByName: String(row.reviewedByName || row.reviewed_by_name || '').trim() || null,
    reviewNote: String(row.reviewNote || row.review_note || '').trim() || null,
    reviewedAt: row.reviewedAt || row.reviewed_at || null,
    createdAt: row.createdAt || row.created_at || nowIso(),
    employeeId: String(row.employeeId || row.employee_id || '').trim() || null,
    employee_id: String(row.employeeId || row.employee_id || '').trim() || null,
    payrollDeductedAt: row.payrollDeductedAt || row.payroll_deducted_at || null,
    payroll_deducted_at: row.payrollDeductedAt || row.payroll_deducted_at || null,
    payrollDeductedMonth:
      row.payrollDeductedMonth == null && row.payroll_deducted_month == null
        ? null
        : Number(row.payrollDeductedMonth ?? row.payroll_deducted_month ?? 0) || null,
    payrollDeductedYear:
      row.payrollDeductedYear == null && row.payroll_deducted_year == null
        ? null
        : Number(row.payrollDeductedYear ?? row.payroll_deducted_year ?? 0) || null,
  };
}

function resolveEmployeeIdForCashier(staffUsers, cashierId) {
  const id = String(cashierId || '').trim();
  if (!id) return null;
  const staff = (staffUsers || []).find((entry) => String(entry.id) === id);
  if (!staff) return null;
  const employeeId = String(staff.employeeId || staff.employee_id || '').trim();
  return employeeId || null;
}

function applyKitchenVoidPayrollDeductions(rows, { month, year, liabilityIds = [] } = {}) {
  const ids = new Set((liabilityIds || []).map((entry) => String(entry)));
  if (!ids.size) return { updated: 0, rows };
  const now = nowIso();
  let updated = 0;
  const next = (rows || []).map((raw) => {
    const row = normalizeKitchenVoidLiability(raw);
    if (!row || !ids.has(String(row.id))) return raw;
    if (row.approvalStatus !== APPROVAL_STATUSES.REJECTED) return raw;
    if (row.payrollDeductedAt) return raw;
    updated += 1;
    return {
      ...raw,
      ...row,
      payrollDeductedAt: now,
      payroll_deducted_at: now,
      payrollDeductedMonth: Number(month) || null,
      payroll_deducted_month: Number(month) || null,
      payrollDeductedYear: Number(year) || null,
      payroll_deducted_year: Number(year) || null,
    };
  });
  return { updated, rows: next };
}

function violationQuantityRemoved(violation) {
  const before = Number(violation.quantityBefore ?? 0) || 0;
  const after = Number(violation.quantityAfter ?? 0) || 0;
  return Math.max(0, before - after);
}

function buildLiabilitiesFromLock({
  violations,
  previousItems,
  restaurantId,
  shiftId,
  orderId,
  entityType,
  entityId,
  cashierId,
  cashierName,
  employeeId,
  reason,
  approvalStatus = APPROVAL_STATUSES.PENDING,
  reviewedBy,
}) {
  const prevById = new Map();
  for (const raw of previousItems || []) {
    const line = normalizeKitchenLine(raw);
    if (line.id) prevById.set(line.id, line);
  }

  const voidedAt = nowIso();
  const voidedMs = Date.parse(voidedAt);
  const status = String(approvalStatus || APPROVAL_STATUSES.PENDING).toUpperCase();
  const reviewed =
    status === APPROVAL_STATUSES.APPROVED || status === APPROVAL_STATUSES.REJECTED;

  return (violations || []).map((violation) => {
    const before = prevById.get(violation.itemId) || {};
    const quantityRemoved = violationQuantityRemoved(violation);
    const unitPrice = Number(violation.unitPrice ?? before.unitPrice ?? 0) || 0;
    const amount = money(quantityRemoved * unitPrice);
    const sentToKitchenAt = before.sentToKitchenAt || before.sent_to_kitchen_at || null;
    const sentMs = sentToKitchenAt ? Date.parse(sentToKitchenAt) : NaN;
    const elapsedMinutes = Number.isFinite(sentMs)
      ? Math.max(0, Math.floor((voidedMs - sentMs) / 60000))
      : null;

    return normalizeKitchenVoidLiability({
      id: `kvl_${randomUUID()}`,
      restaurantId,
      shiftId: String(shiftId || '').trim(),
      orderId: String(orderId || entityId || '').trim(),
      entityType: entityType || 'order',
      entityId: String(entityId || orderId || '').trim(),
      cashierId: String(cashierId || '').trim(),
      cashierName: String(cashierName || 'Cashier'),
      employeeId: String(employeeId || '').trim() || null,
      itemId: violation.itemId,
      menuItemId: violation.menuItemId,
      itemName: violation.name,
      violationType: violation.type,
      quantityBefore: violation.quantityBefore,
      quantityAfter: violation.quantityAfter,
      quantityRemoved,
      unitPrice,
      amount,
      sentToKitchenAt,
      voidedAt,
      elapsedMinutes,
      reason: String(reason || '').trim(),
      approvalStatus: status,
      reviewedById: reviewed ? reviewedBy?.staffId || reviewedBy?.id || null : null,
      reviewedByName: reviewed ? reviewedBy?.staffName || reviewedBy?.name || null : null,
      reviewedAt: reviewed ? nowIso() : null,
    });
  });
}

function summarizeKitchenVoidLiabilities(rows, { shiftId, cashierId } = {}) {
  const scoped = (rows || [])
    .map((row) => normalizeKitchenVoidLiability(row))
    .filter((row) => row)
    .filter((row) => !shiftId || String(row.shiftId) === String(shiftId))
    .filter((row) => !cashierId || String(row.cashierId) === String(cashierId));

  let pendingCount = 0;
  let pendingAmount = 0;
  let approvedCount = 0;
  let approvedAmount = 0;
  let rejectedCount = 0;
  let rejectedAmount = 0;

  for (const row of scoped) {
    switch (row.approvalStatus) {
      case APPROVAL_STATUSES.APPROVED:
        approvedCount += 1;
        approvedAmount += row.amount;
        break;
      case APPROVAL_STATUSES.REJECTED:
        rejectedCount += 1;
        rejectedAmount += row.amount;
        break;
      default:
        pendingCount += 1;
        pendingAmount += row.amount;
        break;
    }
  }

  return {
    pendingCount,
    pendingAmount: money(pendingAmount),
    approvedCount,
    approvedAmount: money(approvedAmount),
    rejectedCount,
    rejectedAmount: money(rejectedAmount),
    cashierVoidDebt: money(rejectedAmount),
    provisionalPendingCount: pendingCount,
    provisionalPendingAmount: money(pendingAmount),
    totalRecords: scoped.length,
  };
}

function mergeLiabilityIntoShiftSummary(summary, liabilityTotals) {
  if (!liabilityTotals) return summary;
  return {
    ...summary,
    kitchenVoidLiabilities: liabilityTotals,
    cashierVoidDebt: liabilityTotals.cashierVoidDebt,
    approvedKitchenVoidAmount: liabilityTotals.approvedAmount,
  };
}

async function appendKitchenVoidLiabilities(deps, records) {
  if (!records?.length) return records;
  if (typeof deps.readKitchenVoidLiabilities !== 'function') return records;
  const rows = await deps.readKitchenVoidLiabilities();
  rows.unshift(...records);
  if (rows.length > 10000) {
    rows.length = 10000;
  }
  await deps.writeKitchenVoidLiabilities(rows);
  return records;
}

function resolveLiabilityApprovalStatus() {
  return APPROVAL_STATUSES.PENDING;
}

function liabilityAuthorizer() {
  return null;
}

module.exports = {
  APPROVAL_STATUSES,
  normalizeKitchenVoidLiability,
  buildLiabilitiesFromLock,
  summarizeKitchenVoidLiabilities,
  mergeLiabilityIntoShiftSummary,
  appendKitchenVoidLiabilities,
  resolveLiabilityApprovalStatus,
  liabilityAuthorizer,
  resolveEmployeeIdForCashier,
  applyKitchenVoidPayrollDeductions,
};