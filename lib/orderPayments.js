'use strict';

const { money } = require('./platformOrderFinance');

const CASH_LINE = /^(cash|كاش)$/i;
const KNET_LINE = /^(k-?net|knet|كي\s*نت)$/i;
const CASH_ANY = /\bcash\b|\bcod\b|كاش(?!ير)|نقدي/i;
const KNET_ANY = /k[\s-]?net|كي\s*نت/i;

function normalizeLineMethod(raw) {
  const text = String(raw || '').replace(/\s+/g, ' ').trim();
  if (!text) return '';
  if (CASH_LINE.test(text) || CASH_ANY.test(text)) return 'cash';
  if (KNET_LINE.test(text) || KNET_ANY.test(text)) return 'knet';
  return '';
}

function normalizePaymentsArray(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const row of raw) {
    if (!row || typeof row !== 'object') continue;
    const method = normalizeLineMethod(row.method ?? row.payment_method ?? row.type);
    const amount = money(row.amount ?? row.value, NaN);
    if (!method || !Number.isFinite(amount)) continue;
    out.push({ method, amount });
  }
  return out;
}

function orderTotalPrice(order) {
  return money(order?.totalPrice ?? order?.total_price ?? 0, 0);
}

function paymentsOfOrder(order) {
  const embedded = normalizePaymentsArray(order?.payments);
  if (embedded.length > 0) return embedded;
  const method = String(order?.paymentMethod ?? order?.payment_method ?? '').trim();
  if (!method) return [];
  const line = normalizeLineMethod(method);
  if (!line) return [];
  const total = orderTotalPrice(order);
  if (!(total > 0)) return [];
  return [{ method: line, amount: total }];
}

function isSplitCashKnetOrder(order) {
  const lines = paymentsOfOrder(order);
  if (lines.length < 2) return false;
  const hasCash = lines.some((row) => row.method === 'cash' && row.amount > 0);
  const hasKnet = lines.some((row) => row.method === 'knet' && row.amount > 0);
  return hasCash && hasKnet;
}

function legacyPaymentMethodLabel(payments) {
  if (!Array.isArray(payments) || payments.length === 0) return '';
  const hasCash = payments.some((row) => row.method === 'cash' && row.amount > 0);
  const hasKnet = payments.some((row) => row.method === 'knet' && row.amount > 0);
  if (hasCash && hasKnet) return 'كاش + كي نت';
  if (hasCash) return 'كاش';
  if (hasKnet) return 'K-Net';
  return '';
}

function validatePaymentsForTotal(payments, totalPrice) {
  const total = money(totalPrice, NaN);
  if (!Number.isFinite(total) || total < 0) {
    return { ok: false, error: 'إجمالي الطلب غير صالح', code: 'INVALID_TOTAL' };
  }
  if (!Array.isArray(payments) || payments.length === 0) {
    return { ok: false, error: 'تفاصيل الدفع مطلوبة', code: 'PAYMENTS_REQUIRED' };
  }
  let cash = 0;
  let knet = 0;
  for (const row of payments) {
    const amount = money(row.amount, NaN);
    if (!Number.isFinite(amount) || amount <= 0) {
      return {
        ok: false,
        error: 'مبالغ الدفع يجب أن تكون أكبر من صفر',
        code: 'INVALID_PAYMENT_AMOUNT',
      };
    }
    if (row.method === 'cash') cash += amount;
    else if (row.method === 'knet') knet += amount;
    else {
      return {
        ok: false,
        error: 'تقسيم الدفع مسموح بين كاش وكي نت فقط',
        code: 'UNSUPPORTED_SPLIT_METHOD',
      };
    }
  }
  const sum = money(cash + knet, NaN);
  if (Math.abs(sum - total) > 0.0005) {
    return {
      ok: false,
      error: 'مجموع كاش + كي نت يجب أن يساوي إجمالي الفاتورة',
      code: 'PAYMENT_TOTAL_MISMATCH',
      expectedTotal: total,
      actualTotal: sum,
    };
  }
  const isSplit = cash > 0 && knet > 0;
  if (isSplit && payments.length < 2) {
    return { ok: false, error: 'تفاصيل التقسيم غير مكتملة', code: 'INCOMPLETE_SPLIT' };
  }
  return { ok: true, payments, cashPortion: money(cash), knetPortion: money(knet) };
}

function mergePaymentsRows(rows) {
  const cash = rows
    .filter((row) => row.method === 'cash')
    .reduce((sum, row) => sum + row.amount, 0);
  const knet = rows
    .filter((row) => row.method === 'knet')
    .reduce((sum, row) => sum + row.amount, 0);
  const merged = [];
  if (cash > 0) merged.push({ method: 'cash', amount: money(cash) });
  if (knet > 0) merged.push({ method: 'knet', amount: money(knet) });
  return merged;
}

function applyOrderPaymentsFromBody(order, body = {}) {
  const total = orderTotalPrice(order);
  const incoming = normalizePaymentsArray(body.payments);
  if (incoming.length > 0) {
    const merged = mergePaymentsRows(incoming);
    const check = validatePaymentsForTotal(merged, total);
    if (!check.ok) return check;
    const label = legacyPaymentMethodLabel(check.payments);
    return {
      ok: true,
      order: {
        ...order,
        payments: check.payments,
        paymentMethod: label || order.paymentMethod,
        payment_method: label || order.payment_method,
      },
    };
  }

  const singleMethod = String(
    body.paymentMethod ?? body.payment_method ?? order.paymentMethod ?? '',
  ).trim();
  const line = normalizeLineMethod(singleMethod);
  if (line && total > 0) {
    const payments = [{ method: line, amount: money(total) }];
    const label = legacyPaymentMethodLabel(payments);
    return {
      ok: true,
      order: {
        ...order,
        payments,
        paymentMethod: label || singleMethod,
        payment_method: label || singleMethod,
      },
    };
  }

  return { ok: true, order };
}

function resolvePaidPaymentPayload(body, order) {
  const total = orderTotalPrice(order);
  const incoming = normalizePaymentsArray(body.payments);
  if (incoming.length > 0) {
    const merged = mergePaymentsRows(incoming);
    const check = validatePaymentsForTotal(merged, total);
    if (!check.ok) return check;
    const label = legacyPaymentMethodLabel(check.payments);
    return {
      ok: true,
      paymentMethod: label,
      payment_method: label,
      payments: check.payments,
      cashPortion: check.cashPortion,
      knetPortion: check.knetPortion,
    };
  }

  const { normalizeCashierSettlementMethod } = require('./platformOrderFinance');
  const paymentMethod = normalizeCashierSettlementMethod(
    body.paymentMethod || body.payment_method || '',
  );
  if (!paymentMethod) {
    return { ok: false, error: 'طريقة الدفع مطلوبة', code: 'PAYMENT_METHOD_REQUIRED' };
  }
  const method = paymentMethod === 'Cash' ? 'cash' : 'knet';
  const payments = [{ method, amount: money(total) }];
  const label = legacyPaymentMethodLabel(payments);
  return {
    ok: true,
    paymentMethod: label || paymentMethod,
    payment_method: label || paymentMethod,
    payments,
    cashPortion: method === 'cash' ? money(total) : 0,
    knetPortion: method === 'knet' ? money(total) : 0,
  };
}

function shiftPaymentBreakdown(order) {
  const lines = paymentsOfOrder(order);
  if (lines.length > 0) {
    let cash = 0;
    let knet = 0;
    for (const row of lines) {
      if (row.method === 'cash') cash += row.amount;
      else if (row.method === 'knet') knet += row.amount;
    }
    return { cash: money(cash), knet: money(knet) };
  }
  const total = orderTotalPrice(order);
  const method = String(order?.paymentMethod ?? order?.payment_method ?? '');
  if (CASH_ANY.test(method)) return { cash: total, knet: 0 };
  if (KNET_ANY.test(method)) return { cash: 0, knet: total };
  return { cash: 0, knet: 0 };
}

module.exports = {
  applyOrderPaymentsFromBody,
  isSplitCashKnetOrder,
  legacyPaymentMethodLabel,
  mergePaymentsRows,
  normalizeLineMethod,
  normalizePaymentsArray,
  paymentsOfOrder,
  resolvePaidPaymentPayload,
  shiftPaymentBreakdown,
  validatePaymentsForTotal,
};