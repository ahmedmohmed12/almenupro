'use strict';

const { isKuwaitToday } = require('../../../lib/kuwaitBusinessDay');

function customerNameForCrm(name) {
  const cleaned = String(name || '').replace(/\s+/g, ' ').trim();
  if (
    !cleaned ||
    /^\*+$/.test(cleaned) ||
    /\*{2,}/.test(cleaned) ||
    /^(unknown|customer|n\/a|na|null|undefined|عميل|بدون اسم)$/i.test(cleaned)
  ) {
    return 'عميل منصات';
  }
  return cleaned;
}

function withCustomerProfile(order) {
  return {
    ...order,
    customerName: customerNameForCrm(order?.customerName),
    phone: String(order?.phone || '').trim(),
    address: String(order?.address || '').trim(),
  };
}

function rowIsKuwaitToday(adapter, row) {
  if (typeof adapter.providerCreatedAt !== 'function') return true;
  const created = adapter.providerCreatedAt(row);
  if (!created) return true;
  return isKuwaitToday(created);
}

function detailIsReady(adapter, detail, expectedExternalOrderId) {
  if (!detail) return false;
  if (!adapter.selectors?.item || typeof adapter.text !== 'function') return true;
  const expected = String(expectedExternalOrderId || '').split('|').pop();
  const invoice = adapter.text(detail, 'invoiceNumber');
  const hasInvoiceSelector = Boolean(adapter.selectors.invoiceNumber);
  const matchesOrder =
    !hasInvoiceSelector ||
    !expected ||
    invoice === expected ||
    invoice === expectedExternalOrderId;
  if (adapter.platform === 'keeta') {
    return matchesOrder;
  }
  return (
    matchesOrder &&
    detail.querySelectorAll(adapter.selectors.item).length > 0
  );
}

function waitForDetail(adapter, timeoutMs = 8000, expectedExternalOrderId = '') {
  const immediate = adapter.detailRoot();
  if (detailIsReady(adapter, immediate, expectedExternalOrderId)) {
    return Promise.resolve(immediate);
  }
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      observer.disconnect();
      reject(new Error('Order invoice detail did not open before timeout'));
    }, timeoutMs);
    const observer = new MutationObserver(() => {
      const detail = adapter.detailRoot();
      if (!detailIsReady(adapter, detail, expectedExternalOrderId)) return;
      clearTimeout(timeout);
      observer.disconnect();
      resolve(detail);
    });
    observer.observe(adapter.document.body || adapter.document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: true,
    });
  });
}

function waitForDetailClosed(adapter, timeoutMs = 2000) {
  if (!adapter.detailRoot()) return Promise.resolve();
  if (typeof MutationObserver === 'undefined') return Promise.resolve();
  return new Promise((resolve) => {
    let observer;
    const finish = () => {
      clearTimeout(timeout);
      observer?.disconnect();
      resolve();
    };
    const timeout = setTimeout(finish, timeoutMs);
    observer = new MutationObserver(() => {
      if (!adapter.detailRoot()) finish();
    });
    observer.observe(adapter.document.body || adapter.document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
    });
  });
}

async function syncTopHistoryOrders({
  adapter,
  ipc,
  limit = 3,
  detailTimeoutMs = 8000,
  refreshExisting = false,
  onlyMissing = false,
  kuwaitTodayOnly = false,
  orderChannel = 'scraper:orders',
  onProgress,
}) {
  const rows = adapter
    .historyRows(limit)
    .filter((row) => !kuwaitTodayOnly || rowIsKuwaitToday(adapter, row));
  const entries = rows
    .map((row) => ({ row, externalOrderId: adapter.externalOrderId(row) }))
    .filter((entry) => entry.externalOrderId);
  if (!entries.length) {
    return { checked: 0, skipped: 0, ingested: 0, failed: 0, customersUpdated: 0 };
  }

  const result = await ipc.invoke(
    'scraper:check-order-ids',
    entries.map((entry) => entry.externalOrderId),
  );
  const reportedMissing = Array.isArray(result?.missing) ? result.missing : [];
  const missing = new Set(
    onlyMissing
      ? reportedMissing
      : refreshExisting && ['talabat', 'keeta'].includes(adapter.platform)
        ? entries.map((entry) => entry.externalOrderId)
        : reportedMissing,
  );
  // Network capture is primary. Skip drawers the parser already claimed,
  // including when a refresh would otherwise reopen them.
  try {
    const processed = await ipc.invoke(
      'orders:processed-ids',
      entries.map((entry) => entry.externalOrderId),
    );
    const skippedByCache = [];
    for (const orderId of Array.isArray(processed?.ids) ? processed.ids : []) {
      if (missing.delete(orderId)) skippedByCache.push(orderId);
    }
    if (skippedByCache.length) {
      ipc.send('scraper:cache-skip', {
        provider: adapter.platform,
        source: 'history',
        ids: skippedByCache,
      });
    }
  } catch {
    // A missing cache channel must not block the fallback scraper.
  }
  const summary = {
    checked: entries.length,
    skipped: entries.length - missing.size,
    ingested: 0,
    failed: 0,
    ingestedIds: [],
    customersUpdated: 0,
    ...(orderChannel === 'scraper:reconcile-orders' ? { actions: {} } : {}),
  };
  const customerPhones = new Set();
  const rememberCustomer = (order) => {
    const digits = String(order?.phone || '').replace(/\D/g, '');
    if (digits.length >= 8) customerPhones.add(digits.slice(-8));
  };

  for (const entry of entries) {
    if (!missing.has(entry.externalOrderId)) continue;
    let detailOpened = false;
    try {
      // Closing a provider drawer can re-render the history grid and detach
      // row nodes captured at the beginning of the batch. Resolve the row
      // again immediately before clicking so later invoices are not lost.
      const currentRow =
        adapter
          .historyRows(Math.max(limit, 200))
          .find(
            (row) =>
              adapter.externalOrderId(row) === entry.externalOrderId,
          ) || entry.row;
      if (typeof currentRow.click !== 'function') {
        throw new Error('Order history row is not clickable');
      }
      currentRow.click();
      const detail = await waitForDetail(
        adapter,
        adapter.platform === 'keeta'
          ? Math.max(detailTimeoutMs, 20_000)
          : detailTimeoutMs,
        entry.externalOrderId,
      );
      detailOpened = true;
      if (adapter.platform === 'keeta') {
        // Items still arrive via getOrderDtl in main.js. DOM parse fills the
        // unified POS customer/delivery fields for enrichment.
        await new Promise((resolve) => setTimeout(resolve, 1500));
        if (typeof adapter.prepareOrderDetail === 'function') {
          await adapter.prepareOrderDetail(detail);
        }
        const contact = adapter.parseOrder(detail, entry.externalOrderId);
        if (
          contact.customerName ||
          contact.phone ||
          contact.address ||
          contact.deliveryType ||
          contact.paymentMethod ||
          contact.externalOrderId
        ) {
          const profile = withCustomerProfile({
              platform: 'keeta',
              externalOrderId: entry.externalOrderId,
              invoiceNumber: contact.invoiceNumber || entry.externalOrderId,
              customerName: contact.customerName || '',
              phone: contact.phone || '',
              address: contact.address || '',
              deliveryInstructions: contact.deliveryInstructions || '',
              deliveryType: contact.deliveryType || '',
              paymentMethod: contact.paymentMethod || '',
              externalStatus: contact.externalStatus || '',
              items: Array.isArray(contact.items) ? contact.items : [],
              subtotal: Number(contact.subtotal) || 0,
              totalAmount: Number(contact.totalAmount) || 0,
              ...(contact.createdAt ? { createdAt: contact.createdAt } : {}),
            });
          if (orderChannel === 'scraper:reconcile-orders') {
            await ipc.invoke('scraper:reconcile-order', profile);
          } else {
            ipc.send(orderChannel, [profile]);
          }
          rememberCustomer(profile);
          summary.ingested += 1;
          summary.ingestedIds.push(entry.externalOrderId);
          if (typeof onProgress === 'function') onProgress(summary);
        }
        continue;
      }
      if (typeof adapter.prepareOrderDetail === 'function') {
        await adapter.prepareOrderDetail(detail);
      }
      const order = withCustomerProfile(
        adapter.parseOrder(detail, entry.externalOrderId),
      );
      if (!order.createdAt && typeof adapter.providerCreatedAt === 'function') {
        const rowCreatedAt = adapter.providerCreatedAt(currentRow);
        if (rowCreatedAt) order.createdAt = rowCreatedAt;
      }
      if (!order.items.length) {
        ipc.send('scraper:parse-miss', {
          provider: adapter.platform,
          reason: 'missing-items',
          externalOrderId: entry.externalOrderId,
          itemSelector: adapter.selectors?.item || '',
          itemCount: 0,
        });
        throw new Error(`Order ${entry.externalOrderId} has no rendered line items`);
      }
      if (orderChannel === 'scraper:reconcile-orders') {
        const reconciliation = await ipc.invoke(
          'scraper:reconcile-order',
          order,
        );
        const action = String(reconciliation?.action || 'unknown');
        const reason = String(reconciliation?.reason || '');
        const actionKey = reason ? `${action}:${reason}` : action;
        summary.actions[actionKey] = (summary.actions[actionKey] || 0) + 1;
        if (reason === 'outside_kuwait_today') {
          summary.stopReason = reason;
        }
      } else {
        ipc.send(orderChannel, [order]);
      }
      summary.ingested += 1;
      summary.ingestedIds.push(entry.externalOrderId);
      rememberCustomer(order);
      if (typeof onProgress === 'function') onProgress(summary);
      if (summary.stopReason) break;
    } catch (error) {
      summary.failed += 1;
      ipc.send('scraper:error', {
        provider: adapter.platform,
        message: `History sync ${entry.externalOrderId}: ${String(
          error.message || error,
        ).slice(0, 400)}`,
      });
    } finally {
      if (detailOpened || adapter.detailRoot()) {
        adapter.detailCloseButton()?.click();
        await waitForDetailClosed(adapter);
      }
    }
  }
  if (summary.stopReason) {
    summary.checked = summary.skipped + summary.ingested + summary.failed;
  }
  summary.customersUpdated = customerPhones.size;
  return summary;
}

module.exports = {
  detailIsReady,
  syncTopHistoryOrders,
  waitForDetail,
  waitForDetailClosed,
};
