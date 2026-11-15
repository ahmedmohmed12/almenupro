'use strict';

const { orderDateKey } = require('./kuwaitBusinessDay');

function idSet(values) {
  return new Set(
    (Array.isArray(values) ? values : [])
      .map((value) => String(value || '').trim())
      .filter(Boolean),
  );
}

function diffPlatformOrderIds(liveOrderIds, localOrderIds) {
  const live = idSet(liveOrderIds);
  const local = idSet(localOrderIds);
  return {
    missing: [...live].filter((id) => !local.has(id)),
    extra: [...local].filter((id) => !live.has(id)),
  };
}

function platformOf(order) {
  return String(order?.orderSource || order?.order_source || order?.platform || '')
    .trim()
    .toLowerCase();
}

function externalIdOf(order) {
  return String(order?.externalOrderId || order?.external_order_id || '').trim();
}

function applyPlatformDayPurge(orders, { restaurantId, platform, liveOrderIds, now = new Date() }) {
  const today = orderDateKey(now);
  const channel = String(platform || '').trim().toLowerCase();
  const live = idSet(liveOrderIds);
  const seenLive = new Set();
  const kept = [];
  let purged = 0;
  for (const order of orders || []) {
    const owner = String(order.restaurantId || order.restaurant_id || '');
    if (restaurantId && owner !== String(restaurantId)) {
      kept.push(order);
      continue;
    }
    const source = platformOf(order);
    const samePlatform =
      source.includes(channel) || (channel === 'keeta' && source.includes('keta'));
    const created = order.createdAt || order.created_at;
    const isToday = Boolean(created) && orderDateKey(created) === today;
    if (!samePlatform || !isToday) {
      kept.push(order);
      continue;
    }
    const externalId = externalIdOf(order);
    const duplicate = Boolean(externalId) && seenLive.has(externalId);
    const absent = !externalId || !live.has(externalId);
    if (absent || duplicate) {
      purged += 1;
      continue;
    }
    seenLive.add(externalId);
    kept.push(order);
  }
  return { orders: kept, purged };
}

module.exports = {
  applyPlatformDayPurge,
  diffPlatformOrderIds,
};
