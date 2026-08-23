const {
  EXPENSE_CATEGORIES,
  normalizeExpense,
  createExpenseRecord,
} = require('./expenseStore');

async function handleExpenseRoutes(req, res, url, deps) {
  const {
    readBody,
    sendJson,
    authError,
    requireAuth,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readExpenses,
    writeExpenses,
    rejectCashier,
  } = deps;

  if (!url.pathname.startsWith('/api/expenses')) {
    return false;
  }

  const auth = requireAuth(req, res);
  if (!auth) return true;
  if (rejectCashier?.(auth, res, 'Cashiers cannot manage expenses')) return true;

  const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
    allowPublicDefault: false,
  });
  if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
    return true;
  }

  if (url.pathname === '/api/expenses' && req.method === 'GET') {
    const category = String(url.searchParams.get('category') || '').trim().toLowerCase();
    const from = String(url.searchParams.get('from') || '').trim();
    const to = String(url.searchParams.get('to') || '').trim();
    let expenses = filterByRestaurant(await readExpenses(), restaurantId).map((row) =>
      normalizeExpense(row, restaurantId),
    );
    if (category && EXPENSE_CATEGORIES.includes(category)) {
      expenses = expenses.filter((row) => row.category === category);
    }
    if (from) {
      expenses = expenses.filter((row) => String(row.date) >= from);
    }
    if (to) {
      expenses = expenses.filter((row) => String(row.date) <= to);
    }
    expenses.sort((a, b) => String(b.date).localeCompare(String(a.date)));
    sendJson(res, 200, {
      expenses,
      categories: EXPENSE_CATEGORIES,
    });
    return true;
  }

  if (url.pathname === '/api/expenses' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const expenses = await readExpenses();
      const record = createExpenseRecord(body, restaurantId);
      expenses.unshift(record);
      await writeExpenses(expenses);
      sendJson(res, 201, record);
    } catch (error) {
      sendJson(res, error.code ? 400 : 400, {
        error: error.message || 'Invalid expense',
      });
    }
    return true;
  }

  const match = url.pathname.match(/^\/api\/expenses\/([^/]+)$/);
  if (match && req.method === 'PATCH') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const expenseId = decodeURIComponent(match[1]);
      const expenses = await readExpenses();
      const index = expenses.findIndex(
        (row) =>
          String(row.id) === expenseId &&
          String(row.restaurant_id || row.restaurantId) === String(restaurantId),
      );
      if (index < 0) {
        sendJson(res, 404, { error: 'Expense not found' });
        return true;
      }
      const next = normalizeExpense(
        {
          ...expenses[index],
          ...body,
          id: expenses[index].id,
          createdAt: expenses[index].createdAt,
          updatedAt: new Date().toISOString(),
        },
        restaurantId,
      );
      if (!next.title) {
        sendJson(res, 400, { error: 'title is required' });
        return true;
      }
      if (!(next.amount > 0)) {
        sendJson(res, 400, { error: 'amount must be a positive number' });
        return true;
      }
      expenses[index] = next;
      await writeExpenses(expenses);
      sendJson(res, 200, next);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid expense' });
    }
    return true;
  }

  if (match && req.method === 'DELETE') {
    const expenseId = decodeURIComponent(match[1]);
    const expenses = await readExpenses();
    const next = expenses.filter(
      (row) =>
        !(
          String(row.id) === expenseId &&
          String(row.restaurant_id || row.restaurantId) === String(restaurantId)
        ),
    );
    if (next.length === expenses.length) {
      sendJson(res, 404, { error: 'Expense not found' });
      return true;
    }
    await writeExpenses(next);
    sendJson(res, 200, { ok: true });
    return true;
  }

  sendJson(res, 405, { error: 'Method not allowed' });
  return true;
}

module.exports = { handleExpenseRoutes, EXPENSE_CATEGORIES };
