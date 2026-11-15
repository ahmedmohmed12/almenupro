'use strict';

const EVENT_KEYS = [
  'created_at',
  'accepted_at',
  'driver_assigned_at',
  'picked_up_at',
  'on_the_way_at',
  'delivered_at',
];

function toIso(value) {
  if (!value) return null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString();
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function uniqueEvents(events) {
  const seen = new Set();
  const list = [];
  for (const event of events) {
    const status = String(event?.status || '').trim();
    const timestamp = toIso(event?.timestamp || event?.at || event?.createdAt);
    if (!status || !timestamp || seen.has(status)) continue;
    seen.add(status);
    list.push({ status, timestamp });
  }
  list.sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp));
  return list;
}

function normalizeTimeline(order = {}) {
  const created = toIso(order.created_at || order.createdAt) || new Date().toISOString();
  const named = {};
  let events = [];
  const raw = order.status_timeline || order.statusTimeline;

  if (Array.isArray(raw)) {
    events = uniqueEvents(raw);
  } else if (raw && typeof raw === 'object') {
    for (const key of EVENT_KEYS) {
      const timestamp = toIso(raw[key]);
      if (timestamp) named[key] = timestamp;
    }
    if (Array.isArray(raw.events)) {
      events = uniqueEvents(raw.events);
    }
  }

  for (const key of EVENT_KEYS) {
    const timestamp = toIso(order[key]);
    if (timestamp) named[key] = named[key] || timestamp;
  }
  for (const event of events) {
    if (EVENT_KEYS.includes(event.status) && !named[event.status]) {
      named[event.status] = event.timestamp;
    }
  }

  named.created_at = named.created_at || created;
  events = uniqueEvents([
    { status: 'created_at', timestamp: named.created_at },
    ...Object.entries(named).map(([status, timestamp]) => ({ status, timestamp })),
    ...events,
  ]);

  return { ...named, events };
}

function stampTimeline(order, status, at) {
  const key = String(status || '').trim();
  if (!key) return order;
  const now = toIso(at) || new Date().toISOString();
  const current = normalizeTimeline(order);
  if (!current[key] && EVENT_KEYS.includes(key)) {
    current[key] = now;
  }
  if (!current.events.some((event) => event.status === key)) {
    current.events.push({ status: key, timestamp: current[key] || now });
    current.events = uniqueEvents(current.events);
  }
  const { events, ...named } = current;
  return {
    ...order,
    created_at: named.created_at,
    accepted_at: named.accepted_at || null,
    driver_assigned_at: named.driver_assigned_at || null,
    picked_up_at: named.picked_up_at || null,
    on_the_way_at: named.on_the_way_at || null,
    delivered_at: named.delivered_at || null,
    status_timeline: { ...named, events },
  };
}

function stampFromOrderStatus(order, nextStatus, at) {
  const status = String(nextStatus || '').trim().toLowerCase().replace(/-/g, '_');
  let next = stampTimeline(order, 'created_at', order.createdAt || order.created_at || at);
  if (
    status === 'confirmed' ||
    status === 'auto_accepted' ||
    status === 'autoaccepted'
  ) {
    next = stampTimeline(next, 'accepted_at', at);
  }
  if (status === 'delivered') {
    next = stampTimeline(next, 'delivered_at', at);
  }
  return next;
}

module.exports = {
  EVENT_KEYS,
  normalizeTimeline,
  stampTimeline,
  stampFromOrderStatus,
};
