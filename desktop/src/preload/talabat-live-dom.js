'use strict';

const {
  talabatRowShouldScan,
  talabatStatusRank,
} = require('../services/talabat-history-dom');

const ROW_SELECTOR = [
  "[role='row'][data-id]",
  "[role='row'][data-rowindex]",
  'tbody tr',
  "[data-testid='order-card']",
  "[data-testid='order-history-row']",
].join(', ');

const ROOT_SELECTORS = [
  "[data-testid='orders-grid-holder']",
  "[data-testid='live-orders']",
  "[data-testid='orders-list']",
  "[role='grid']",
  'table',
  "[data-testid='order-history']",
];

function talabatListRoot(documentRef) {
  for (const selector of ROOT_SELECTORS) {
    const node = documentRef.querySelector(selector);
    if (node) return node;
  }
  return null;
}

function rowsFromAddedNodes(nodes, limit = 15) {
  const rows = [];
  const seen = new Set();
  for (const node of nodes || []) {
    if (!node || node.nodeType !== 1) continue;
    const candidates = [];
    if (typeof node.matches === 'function' && node.matches(ROW_SELECTOR)) {
      candidates.push(node);
    }
    if (typeof node.querySelectorAll === 'function') {
      candidates.push(...node.querySelectorAll(ROW_SELECTOR));
    }
    for (const row of candidates) {
      if (seen.has(row)) continue;
      seen.add(row);
      rows.push(row);
      if (rows.length >= limit) return rows;
    }
  }
  return rows;
}

function rowsFromMutationRecords(records, limit = 15) {
  const added = [];
  for (const record of records || []) {
    if (record?.type && record.type !== 'childList') continue;
    added.push(...(record.addedNodes || []));
  }
  return rowsFromAddedNodes(added, limit);
}

/**
 * Watches the Talabat order table and emits a new row as soon as it is inserted.
 * Network capture stays primary: an id already in the 24-hour cache is not opened.
 */
function attachTalabatLiveDom({
  documentRef,
  getAdapter,
  ipc,
  isBusy = () => false,
  waitForDetail,
  waitForDetailClosed,
  MutationObserverImpl,
}) {
  const Observer = MutationObserverImpl || MutationObserver;
  const sessionStartedAt = new Date();
  const queue = [];
  const queued = new Set();
  const claimed = new Set();
  const attempts = new Map();
  let listObserver = null;
  let shellObserver = null;
  let listRoot = null;
  let draining = false;
  let stopped = false;

  function adapter() {
    return getAdapter();
  }

  function enqueue(row, front) {
    const current = adapter();
    const text = String(row?.textContent || '');
    if (!talabatRowShouldScan(text, sessionStartedAt)) return false;
    const orderId = current?.externalOrderId(row) || '';
    if (!orderId || claimed.has(orderId) || queued.has(orderId)) return false;
    queued.add(orderId);
    const entry = { orderId, row, rank: talabatStatusRank(text) };
    if (front && entry.rank < 4) {
      queue.unshift(entry);
      return true;
    }
    const index = queue.findIndex((item) => item.rank > entry.rank);
    if (index === -1) queue.push(entry);
    else queue.splice(index, 0, entry);
    return true;
  }

  function findConnectedRow(orderId) {
    const root = talabatListRoot(documentRef) || documentRef;
    const rows = root.querySelectorAll ? root.querySelectorAll(ROW_SELECTOR) : [];
    for (const row of rows) {
      if (adapter()?.externalOrderId(row) === orderId) return row;
    }
    return null;
  }

  async function readOrder(entry) {
    const current = adapter();
    const row = entry.row?.isConnected === false
      ? findConnectedRow(entry.orderId)
      : entry.row || findConnectedRow(entry.orderId);
    if (!current || !row) {
      ipc.send('scraper:parse-miss', {
        provider: 'talabat',
        reason: 'missing-order-id',
        externalOrderId: entry.orderId,
        mode: 'mutation',
        itemSelector: current?.selectors?.item || '',
        itemCount: 0,
      });
      return null;
    }
    let order = current.parseOrder(row, entry.orderId);
    if (order?.items?.length) return order;
    if (typeof row.click !== 'function' || typeof waitForDetail !== 'function') {
      ipc.send('scraper:parse-miss', {
        provider: 'talabat',
        reason: 'missing-items',
        externalOrderId: entry.orderId,
        mode: 'mutation',
        itemSelector: current.selectors?.item || '',
        itemCount: 0,
      });
      return null;
    }
    // Step: the list row only has the id. Open it and read the invoice body.
    row.click();
    const detail = await waitForDetail(current, 8000, entry.orderId);
    if (typeof current.prepareOrderDetail === 'function') {
      await current.prepareOrderDetail(detail);
    }
    order = current.parseOrder(detail, entry.orderId);
    current.detailCloseButton()?.click();
    if (typeof waitForDetailClosed === 'function') await waitForDetailClosed(current);
    if (!order?.items?.length) {
      ipc.send('scraper:parse-miss', {
        provider: 'talabat',
        reason: 'missing-items',
        externalOrderId: entry.orderId,
        mode: 'mutation',
        itemSelector: current.selectors?.item || '',
        itemCount: 0,
      });
      return null;
    }
    return order;
  }

  async function drain() {
    if (draining || stopped) return;
    if (isBusy()) {
      setTimeout(() => void drain(), 1000);
      return;
    }
    draining = true;
    try {
      while (queue.length && !stopped && !isBusy()) {
        const entry = queue.shift();
        queued.delete(entry.orderId);
        let allowed = true;
        try {
          // Step: network capture wins. Skip an id the 24-hour cache already holds.
          const result = await ipc.invoke('orders:unprocessed', [entry.orderId]);
          const fresh = new Set(Array.isArray(result?.ids) ? result.ids : []);
          allowed = fresh.has(entry.orderId);
        } catch {
          allowed = true;
        }
        if (!allowed) {
          claimed.add(entry.orderId);
          ipc.send('scraper:cache-skip', {
            provider: 'talabat',
            source: 'mutation',
            ids: [entry.orderId],
          });
          continue;
        }
        ipc.send('scraper:parse-miss', {
          provider: 'talabat',
          reason: 'observed-row',
          externalOrderId: entry.orderId,
          mode: 'mutation',
          itemSelector: adapter()?.selectors?.item || '',
          itemCount: 0,
        });
        try {
          const order = await readOrder(entry);
          if (!order) {
            const count = (attempts.get(entry.orderId) || 0) + 1;
            attempts.set(entry.orderId, count);
            if (count >= 2) claimed.add(entry.orderId);
            continue;
          }
          claimed.add(entry.orderId);
          ipc.send('scraper:orders', [order]);
        } catch (error) {
          ipc.send('scraper:parse-miss', {
            provider: 'talabat',
            reason: 'selector-mismatch',
            externalOrderId: entry.orderId,
            mode: 'mutation',
            itemSelector: adapter()?.selectors?.item || '',
            itemCount: 0,
          });
          ipc.send('scraper:error', {
            provider: 'talabat',
            message: `Live row ${entry.orderId}: ${String(error?.message || error).slice(0, 300)}`,
          });
        }
      }
    } finally {
      draining = false;
      if (queue.length && !stopped) void drain();
    }
  }

  function onListMutation(records) {
    // Step: a new row or card was inserted, including recent and accepted tabs.
    const rows = rowsFromMutationRecords(records);
    let added = false;
    for (const row of rows) {
      if (enqueue(row, true)) added = true;
    }
    if (added) void drain();
  }

  function rebind() {
    if (stopped) return;
    const nextRoot = talabatListRoot(documentRef) || documentRef.body;
    if (!nextRoot) return;
    // Step: keep the same observer while the table node is still on the page.
    if (listObserver && listRoot === nextRoot && nextRoot.isConnected !== false) return;
    listRoot = nextRoot;
    listObserver ||= new Observer(onListMutation);
    listObserver.disconnect();
    listObserver.observe(nextRoot, { childList: true, subtree: true });
    if (!shellObserver && documentRef.body) {
      // Step: SPA tab changes replace the table. Re-attach when that node goes away.
      shellObserver = new Observer(() => {
        if (!listRoot || listRoot.isConnected === false) rebind();
      });
      shellObserver.observe(documentRef.body, { childList: true, subtree: true });
    }
    const visible = nextRoot.querySelectorAll
      ? Array.from(nextRoot.querySelectorAll(ROW_SELECTOR)).slice(0, 8)
      : [];
    let added = false;
    for (const row of visible) {
      if (enqueue(row, false)) added = true;
    }
    if (added) void drain();
  }

  function disconnect() {
    stopped = true;
    listObserver?.disconnect();
    shellObserver?.disconnect();
    queue.length = 0;
    queued.clear();
  }

  rebind();
  return { rebind, disconnect };
}

module.exports = {
  attachTalabatLiveDom,
  rowsFromMutationRecords,
  talabatListRoot,
  ROW_SELECTOR,
};
