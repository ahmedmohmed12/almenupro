'use strict';

const { isKuwaitToday } = require('../../../lib/kuwaitBusinessDay');
const { syncTopHistoryOrders } = require('./history-sync');

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function scrollTarget(container) {
  if (!container || typeof container !== 'object') return null;
  const nested = container.querySelectorAll ? container.querySelectorAll('*') : [];
  const candidates = [container, ...Array.from(nested)].filter(Boolean);
  return (
    candidates
      .filter(
        (node) =>
          Number(node.scrollHeight) > Number(node.clientHeight) + 20 &&
          Number(node.clientHeight) > 0,
      )
      .sort(
        (left, right) =>
          Number(right.scrollHeight) - Number(left.scrollHeight),
      )[0] || null
  );
}

function scrollParents(node) {
  const chain = [];
  let current = node;
  while (current) {
    chain.push(current);
    current = current.parentElement || null;
  }
  return chain;
}

function readHistoryRows(adapter, limit) {
  const reader =
    typeof adapter?.readLiveOrderRows === 'function'
      ? adapter.readLiveOrderRows.bind(adapter)
      : adapter?.historyRows?.bind(adapter);
  if (!reader) return [];
  try {
    return reader(limit) || [];
  } catch (error) {
    console.warn(
      `[${adapter.platform || 'platform'}] history read failed: ${String(
        error?.message || error,
      ).slice(0, 200)}`,
    );
    return [];
  }
}

function readExternalOrderId(adapter, row) {
  try {
    return adapter.externalOrderId(row);
  } catch (error) {
    console.warn(
      `[${adapter.platform || 'platform'}] order id selector failed: ${String(
        error?.message || error,
      ).slice(0, 200)}`,
    );
    return '';
  }
}

function rowCreatedAt(adapter, row) {
  if (typeof adapter.providerCreatedAt !== 'function') return '';
  return adapter.providerCreatedAt(row) || '';
}

function nextHistoryButton(adapter) {
  const doc = adapter?.document;
  if (!doc?.querySelectorAll) return null;
  return (
    Array.from(
      doc.querySelectorAll(
        "button, a, [role='button'], [data-testid*='next' i], [aria-label*='next' i]",
      ),
    ).find((element) => {
      if (element.disabled || element.getAttribute?.('aria-disabled') === 'true') {
        return false;
      }
      const text = String(element.textContent || '').replace(/\s+/g, ' ').trim();
      const label = String(element.getAttribute?.('aria-label') || '');
      if (text.length > 40 && label.length > 40) return false;
      return (
        /^(next|load more|more|التالي|المزيد|الصفحة التالية)$/i.test(text) ||
        /next|load more|التالي|go to next/i.test(`${text} ${label}`)
      );
    }) || null
  );
}

function clickNextHistoryPage(adapter) {
  const button = nextHistoryButton(adapter);
  if (typeof button?.click !== 'function') return false;
  button.click();
  return true;
}

function scrollHistory(adapter) {
  const doc = adapter?.document;
  const sample = readHistoryRows(adapter, 1)[0];
  const roots = [
    adapter.historyContainer?.(),
    ...scrollParents(sample),
    doc?.scrollingElement,
    doc?.documentElement,
  ].filter(Boolean);
  const seen = new Set();
  let moved = false;
  for (const root of roots) {
    if (seen.has(root)) continue;
    seen.add(root);
    const scroller = scrollTarget(root);
    if (!scroller || seen.has(scroller)) continue;
    seen.add(scroller);
    const before = Number(scroller.scrollTop) || 0;
    const max = Math.max(
      0,
      Number(scroller.scrollHeight) - Number(scroller.clientHeight),
    );
    if (max <= before + 2) continue;
    const step = Math.max(Number(scroller.clientHeight) * 0.85, 640);
    scroller.scrollTop = Math.min(before + step, max);
    scroller.dispatchEvent?.(new Event('scroll', { bubbles: true }));
    if (typeof WheelEvent === 'function') {
      scroller.dispatchEvent?.(
        new WheelEvent('wheel', { deltaY: step, bubbles: true }),
      );
    }
    if ((Number(scroller.scrollTop) || 0) !== before) moved = true;
  }
  return moved;
}

async function collectTodayOrderIds(adapter, { maxOrders, maxRounds, settleMs }) {
  if (typeof adapter.prepareHistoryScan === 'function') {
    await adapter.prepareHistoryScan({ wait, scroll: scrollHistory });
  }
  const ids = [];
  const seen = new Set();
  let idleRounds = 0;
  let reachedOlderDay = false;

  for (let warm = 0; warm < 8; warm += 1) {
    const moved = scrollHistory(adapter);
    await wait(settleMs);
    if (!moved && readHistoryRows(adapter, 1).length) break;
  }
  const top = scrollTarget(adapter.historyContainer?.()) || adapter.document?.scrollingElement;
  if (top) top.scrollTop = 0;

  for (let round = 0; round < maxRounds && ids.length < maxOrders; round += 1) {
    let fresh = 0;
    for (const row of readHistoryRows(adapter, maxOrders)) {
      const id = readExternalOrderId(adapter, row);
      if (!id || seen.has(id)) continue;
      const created = rowCreatedAt(adapter, row);
      if (created && !isKuwaitToday(created)) {
        reachedOlderDay = true;
        break;
      }
      seen.add(id);
      ids.push(id);
      fresh += 1;
      if (ids.length >= maxOrders) break;
    }
    if (reachedOlderDay) break;
    if (fresh === 0) idleRounds += 1;
    else idleRounds = 0;
    if (idleRounds >= 3) break;
    const paged = clickNextHistoryPage(adapter);
    const moved = scrollHistory(adapter, settleMs);
    await wait(paged ? Math.max(settleMs, 400) : settleMs);
    if (!moved && !paged) idleRounds += 1;
  }
  return {
    ids,
    complete:
      ids.length > 0 &&
      ids.length < maxOrders &&
      (reachedOlderDay || idleRounds >= 3) &&
      !nextHistoryButton(adapter),
    reachedOlderDay,
  };
}

async function missingOrderIds(ipc, ids) {
  const missing = [];
  for (let index = 0; index < ids.length; index += 200) {
    const chunk = ids.slice(index, index + 200);
    const result = await ipc.invoke('scraper:check-order-ids', chunk);
    const reported = Array.isArray(result?.missing) ? result.missing : [];
    missing.push(...reported);
  }
  return missing;
}

function describeHistoryDom(adapter) {
  const doc = adapter?.document;
  const href = String(doc?.location?.href || '');
  const path = String(doc?.location?.pathname || '');
  const title = String(doc?.title || '');
  const text = String(doc?.body?.innerText || doc?.body?.textContent || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 1600);
  const rows = readHistoryRows(adapter, 80);
  const ids = [];
  for (const row of rows) {
    const id = readExternalOrderId(adapter, row);
    if (id && !ids.includes(id)) ids.push(id);
  }
  const blob = `${href} ${path} ${title} ${text}`;
  const loginWall =
    /login|sign-?in|تسجيل الدخول|restaurant-login/i.test(blob) &&
    ids.length === 0;
  const historyPage =
    /orders\/history|order_history|past-orders|الطلبات السابقة|سجل الطلبات|تاريخ الطلبات/i.test(
      blob,
    );
  return {
    href,
    path,
    title,
    loginWall,
    historyPage,
    rowCount: rows.length,
    ids,
  };
}

async function reconcileKuwaitToday({
  adapter,
  ipc,
  maxOrders = 500,
  maxRounds = 30,
  settleMs = 180,
  onProgress,
  onDiagnostic,
}) {
  const started = describeHistoryDom(adapter);
  if (typeof onDiagnostic === 'function') onDiagnostic(started);
  const harvest = await collectTodayOrderIds(adapter, {
    maxOrders,
    maxRounds,
    settleMs,
  });
  const ids = harvest.ids;
  const report = (ingested) => {
    if (typeof onProgress === 'function') {
      onProgress({ checked: ids.length, ingested });
    }
  };
  report(0);
  const finished = describeHistoryDom(adapter);
  finished.ids = ids.length ? ids : finished.ids;
  if (typeof onDiagnostic === 'function') onDiagnostic(finished);
  if (!ids.length) {
    return {
      checked: 0,
      ingested: 0,
      skipped: 0,
      failed: 0,
      customersUpdated: 0,
      actions: {},
      unread: true,
      historyPage: finished.historyPage,
      loginWall: finished.loginWall,
      scanReliable: false,
    };
  }

  const missing = await missingOrderIds(ipc, ids);
  const summary = {
    checked: ids.length,
    ingested: 0,
    skipped: ids.length - missing.length,
    failed: 0,
    customersUpdated: 0,
    actions: {},
    liveOrderIds: ids,
    ingestedIds: [],
    scanReliable: Boolean(harvest.complete) && ids.length > 0,
  };
  if (!missing.length) return summary;

  const pending = new Set(missing);
  const scroller = scrollTarget(adapter.historyContainer?.());
  if (scroller) scroller.scrollTop = 0;
  await wait(160);

  let idleRounds = 0;
  for (let round = 0; round < maxRounds && pending.size; round += 1) {
    const visibleIds = new Set(
      readHistoryRows(adapter, maxOrders)
        .map((row) => readExternalOrderId(adapter, row))
        .filter((id) => pending.has(id)),
    );
    if (!visibleIds.size) {
      idleRounds += 1;
    } else {
      idleRounds = 0;
      const batchAdapter = Object.create(adapter);
      batchAdapter.historyRows = (limit) =>
        readHistoryRows(adapter, maxOrders)
          .filter((row) => visibleIds.has(readExternalOrderId(adapter, row)))
          .slice(0, Math.max(1, Number(limit) || visibleIds.size));
      const batch = await syncTopHistoryOrders({
        adapter: batchAdapter,
        ipc,
        limit: visibleIds.size,
        onlyMissing: true,
        kuwaitTodayOnly: true,
        orderChannel: 'scraper:reconcile-orders',
        onProgress: (partial) => report(summary.ingested + (partial.ingested || 0)),
      });
      summary.ingested += batch.ingested;
      summary.failed += batch.failed;
      summary.customersUpdated += batch.customersUpdated || 0;
      if (Array.isArray(batch.ingestedIds)) summary.ingestedIds.push(...batch.ingestedIds);
      for (const [action, count] of Object.entries(batch.actions || {})) {
        summary.actions[action] = (summary.actions[action] || 0) + count;
      }
      for (const id of visibleIds) pending.delete(id);
      report(summary.ingested);
      if (batch.stopReason) {
        summary.stopReason = batch.stopReason;
        break;
      }
    }
    if (idleRounds >= 2) break;
    const moved = scrollHistory(adapter);
    await wait(settleMs);
    if (!moved) idleRounds += 1;
  }
  return summary;
}

module.exports = {
  collectTodayOrderIds,
  describeHistoryDom,
  missingOrderIds,
  reconcileKuwaitToday,
  scrollTarget,
};
