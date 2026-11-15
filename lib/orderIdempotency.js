'use strict';

function offlineTxKey(order) {
  const tx = String(order?.offline_tx_id || order?.offlineTxId || '').trim();
  if (tx) return tx;
  const id = String(order?.id || '').trim();
  return id.startsWith('offline_tx_') ? id : '';
}

function findDuplicateOrder(orders, body) {
  const id = String(body?.id || '').trim();
  const tx = offlineTxKey(body);
  if (!id && !tx) return null;
  return (Array.isArray(orders) ? orders : []).find((order) => {
    const oid = String(order?.id || '');
    const otx = offlineTxKey(order);
    if (id && oid === id) return true;
    if (tx && (oid === tx || otx === tx)) return true;
    return false;
  }) || null;
}

function stampOfflineTx(order, body) {
  const tx = offlineTxKey(body) || offlineTxKey(order);
  if (!tx) return order;
  return {
    ...order,
    offline_tx_id: tx,
    offlineTxId: tx,
  };
}

function preferNewerOrder(existing, incoming) {
  const existingTs =
    Date.parse(existing.updatedAt || existing.updated_at || existing.createdAt || existing.created_at || 0) ||
    0;
  const incomingTs =
    Date.parse(incoming.updatedAt || incoming.updated_at || incoming.createdAt || incoming.created_at || 0) ||
    0;
  if (incomingTs > existingTs) {
    return stampOfflineTx(
      {
        ...existing,
        ...incoming,
        id: existing.id,
      },
      incoming,
    );
  }
  return existing;
}

module.exports = {
  offlineTxKey,
  findDuplicateOrder,
  stampOfflineTx,
  preferNewerOrder,
};
