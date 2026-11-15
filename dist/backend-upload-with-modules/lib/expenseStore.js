const { randomUUID } = require('crypto');
const { ensureRestaurantId } = require('./tenantStore');

const EXPENSE_CATEGORIES = [
  'suppliers',
  'salaries',
  'rent',
  'utilities',
  'maintenance',
  'other',
];

function normalizeCategory(raw) {
  const value = String(raw || '').trim().toLowerCase();
  const aliases = {
    supplier: 'suppliers',
    موردون: 'suppliers',
    الموردون: 'suppliers',
    salary: 'salaries',
    رواتب: 'salaries',
    الرواتب: 'salaries',
    إيجار: 'rent',
    الايجار: 'rent',
    الإيجار: 'rent',
    خدمات: 'utilities',
    الخدمات: 'utilities',
    صيانة: 'maintenance',
    الصيانة: 'maintenance',
    أخرى: 'other',
    اخرى: 'other',
  };
  const mapped = aliases[value] || value;
  return EXPENSE_CATEGORIES.includes(mapped) ? mapped : 'other';
}

function parseAmount(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Number(n.toFixed(3));
}

function parseExpenseDate(raw) {
  const value = String(raw || '').trim();
  if (!value) return new Date().toISOString().slice(0, 10);
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return new Date().toISOString().slice(0, 10);
  }
  return parsed.toISOString().slice(0, 10);
}

function normalizeExpense(raw = {}, restaurantId) {
  const amount = parseAmount(raw.amount);
  const createdAt =
    raw.createdAt || raw.created_at || new Date().toISOString();
  const updatedAt = raw.updatedAt || raw.updated_at || createdAt;
  return ensureRestaurantId(
    {
      id: String(raw.id || `exp_${randomUUID()}`),
      title: String(raw.title || raw.name || '').trim().slice(0, 160),
      category: normalizeCategory(raw.category),
      amount: amount ?? 0,
      date: parseExpenseDate(raw.date || raw.expenseDate || raw.expense_date),
      notes: String(raw.notes || raw.note || '').trim().slice(0, 1000),
      createdAt,
      updatedAt,
    },
    restaurantId || raw.restaurant_id || raw.restaurantId,
  );
}

function createExpenseRecord(body, restaurantId) {
  const amount = parseAmount(body.amount);
  if (amount == null) {
    const error = new Error('amount must be a positive number');
    error.code = 'INVALID_AMOUNT';
    throw error;
  }
  const title = String(body.title || body.name || '').trim();
  if (!title) {
    const error = new Error('title is required');
    error.code = 'INVALID_TITLE';
    throw error;
  }
  return normalizeExpense(
    {
      ...body,
      title,
      amount,
    },
    restaurantId,
  );
}

module.exports = {
  EXPENSE_CATEGORIES,
  normalizeCategory,
  normalizeExpense,
  createExpenseRecord,
};
