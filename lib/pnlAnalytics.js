const { isCancelledStatus } = require('./topItemsAnalytics');

function restaurantIdOf(row) {
  return String(row.restaurant_id || row.restaurantId || '');
}

function orderTotal(order) {
  return Number(order.totalPrice ?? order.total_price) || 0;
}

function orderNet(order) {
  const total = orderTotal(order);
  const commission =
    Number(order.platformCommission ?? order.platform_commission) || 0;
  if (commission > 0) return Math.max(0, total - commission);
  return total;
}

function dayKeyFromMs(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

function expenseDay(expense) {
  const raw = expense.date || expense.createdAt || expense.created_at;
  const parsed = raw ? new Date(raw) : null;
  if (parsed && !Number.isNaN(parsed.getTime())) {
    return parsed.toISOString().slice(0, 10);
  }
  return new Date().toISOString().slice(0, 10);
}

function computeProfitAndLoss(orders, expenses, restaurantId, options = {}) {
  const days = Math.max(1, Number(options.days) || 30);
  const now = Date.now();
  const cutoff = now - days * 24 * 60 * 60 * 1000;

  const scopedOrders = (orders || []).filter((order) => {
    if (restaurantIdOf(order) !== restaurantId) return false;
    if (isCancelledStatus(order.status)) return false;
    const created = Date.parse(order.createdAt || order.created_at || 0);
    return Number.isFinite(created) && created >= cutoff;
  });

  const scopedExpenses = (expenses || []).filter((expense) => {
    if (restaurantIdOf(expense) !== restaurantId) return false;
    const day = expenseDay(expense);
    const ms = Date.parse(`${day}T00:00:00.000Z`);
    return Number.isFinite(ms) && ms >= cutoff;
  });

  let grossRevenue = 0;
  let netRevenue = 0;
  let commission = 0;
  const revenueByDay = new Map();

  for (const order of scopedOrders) {
    const gross = orderTotal(order);
    const net = orderNet(order);
    const comm =
      Number(order.platformCommission ?? order.platform_commission) || 0;
    grossRevenue += gross;
    netRevenue += net;
    commission += comm;
    const created = Date.parse(order.createdAt || order.created_at || 0);
    const key = dayKeyFromMs(created);
    const row = revenueByDay.get(key) || { revenue: 0, orders: 0 };
    row.revenue += net;
    row.orders += 1;
    revenueByDay.set(key, row);
  }

  let totalExpenses = 0;
  const byCategory = new Map();
  const expenseByDay = new Map();
  for (const expense of scopedExpenses) {
    const amount = Number(expense.amount) || 0;
    totalExpenses += amount;
    const category = String(expense.category || 'other');
    byCategory.set(category, (byCategory.get(category) || 0) + amount);
    const key = expenseDay(expense);
    expenseByDay.set(key, (expenseByDay.get(key) || 0) + amount);
  }

  const series = [];
  for (let i = days - 1; i >= 0; i -= 1) {
    const key = dayKeyFromMs(now - i * 24 * 60 * 60 * 1000);
    const revenue = Number((revenueByDay.get(key)?.revenue || 0).toFixed(3));
    const expense = Number((expenseByDay.get(key) || 0).toFixed(3));
    series.push({
      date: key,
      revenue,
      expenses: expense,
      net: Number((revenue - expense).toFixed(3)),
      orders: revenueByDay.get(key)?.orders || 0,
    });
  }

  const netProfit = Number((netRevenue - totalExpenses).toFixed(3));
  const marginPercent =
    netRevenue > 0 ? Number(((netProfit / netRevenue) * 100).toFixed(1)) : 0;
  const expenseRatio =
    netRevenue > 0
      ? Number(((totalExpenses / netRevenue) * 100).toFixed(1))
      : totalExpenses > 0
        ? 100
        : 0;

  let health = 'no_data';
  if (netRevenue > 0 || totalExpenses > 0) {
    if (netProfit > 0) health = 'profit';
    else if (netProfit === 0) health = 'breakeven';
    else health = 'loss';
  }

  const categories = [...byCategory.entries()]
    .map(([category, amount]) => ({
      category,
      amount: Number(amount.toFixed(3)),
      sharePercent:
        totalExpenses > 0
          ? Number(((amount / totalExpenses) * 100).toFixed(1))
          : 0,
    }))
    .sort((a, b) => b.amount - a.amount);

  return {
    days,
    summary: {
      orders: scopedOrders.length,
      grossRevenue: Number(grossRevenue.toFixed(3)),
      netRevenue: Number(netRevenue.toFixed(3)),
      commission: Number(commission.toFixed(3)),
      totalExpenses: Number(totalExpenses.toFixed(3)),
      netProfit,
      marginPercent,
      expenseRatio,
      health,
    },
    categories,
    series,
  };
}

module.exports = { computeProfitAndLoss };
