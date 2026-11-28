'use strict';

const LOCATION_KIND = {
  BRANCH_STOCK: 'BRANCH_STOCK',
  KITCHEN_PREP: 'KITCHEN_PREP',
  VENDOR: 'VENDOR',
  CUSTOMER: 'CUSTOMER',
  WASTE: 'WASTE',
  ADJUSTMENT: 'ADJUSTMENT',
  IN_TRANSIT: 'IN_TRANSIT',
};

const PHYSICAL_KINDS = new Set([LOCATION_KIND.BRANCH_STOCK, LOCATION_KIND.KITCHEN_PREP]);

const ITEM_TYPE = {
  RAW: 'RAW',
  PREP: 'PREP',
};

const MOVE_REFERENCE = {
  PURCHASE: 'PURCHASE',
  POS_ORDER: 'POS_ORDER',
  PREP_PRODUCTION: 'PREP_PRODUCTION',
  TRANSFER: 'TRANSFER',
  WASTE: 'WASTE',
  STOCKTAKE_ADJ: 'STOCKTAKE_ADJ',
  REVERSAL: 'REVERSAL',
};

const SALES_CHANNEL = {
  DINE_IN: 'DINE_IN',
  TAKEAWAY: 'TAKEAWAY',
  DELIVERY: 'DELIVERY',
  AGGREGATOR: 'AGGREGATOR',
};

const DOC_STATUS = {
  DRAFT: 'DRAFT',
  CLOSED: 'CLOSED',
  CANCELLED: 'CANCELLED',
};

/** @deprecated use DOC_STATUS — kept for legacy purchase rows */
const PURCHASE_STATUS = {
  DRAFT: 'DRAFT',
  APPROVED: 'APPROVED',
  CLOSED: 'CLOSED',
  CANCELLED: 'CANCELLED',
};

const TRANSFER_STAGE = {
  /** Foodics: REQUESTED */
  REQUEST: 'REQUEST',
  REQUESTED: 'REQUEST',
  /** Foodics: IN_TRANSIT (stock left branch, not yet received) */
  SENT: 'SENT',
  IN_TRANSIT: 'SENT',
  RECEIVED: 'RECEIVED',
};

const APPLICABLE_ORDER_TYPES = ['ALL', 'DINE_IN', 'TAKEAWAY', 'DELIVERY', 'AGGREGATOR'];

const WASTE_REASON_CODES = [
  'SPOILAGE',
  'EXPIRED',
  'PREPARATION_ERROR',
  'CUSTOMER_RETURN',
  'OVERPRODUCTION',
  'OTHER',
];

function isDocClosed(status) {
  const s = String(status || '').toUpperCase();
  return s === DOC_STATUS.CLOSED || s === 'APPROVED' || s === 'CLOSED';
}

function isDocDraft(status) {
  return String(status || '').toUpperCase() === DOC_STATUS.DRAFT;
}

const JOB_STATUS = {
  PENDING: 'PENDING',
  RUNNING: 'RUNNING',
  DONE: 'DONE',
  FAILED: 'FAILED',
};

/** Round money/qty for KWD (3 decimals) with optional extra precision for avg cost. */
function roundQty(value, decimals = 5) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  const factor = 10 ** decimals;
  return Math.round(n * factor) / factor;
}

function roundMoneyKwd(value) {
  return roundQty(value, 5);
}

function newId(prefix) {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

module.exports = {
  LOCATION_KIND,
  PHYSICAL_KINDS,
  ITEM_TYPE,
  MOVE_REFERENCE,
  SALES_CHANNEL,
  DOC_STATUS,
  PURCHASE_STATUS,
  TRANSFER_STAGE,
  APPLICABLE_ORDER_TYPES,
  WASTE_REASON_CODES,
  JOB_STATUS,
  isDocClosed,
  isDocDraft,
  roundQty,
  roundMoneyKwd,
  newId,
};