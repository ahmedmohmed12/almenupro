'use strict';

const PLATFORM_NAMES = {
  keeta: 'كيتا',
  talabat: 'طلبات',
  jahez: 'جاهز',
};

function platformDisplayName(provider) {
  return PLATFORM_NAMES[provider] || String(provider || '');
}

function shortOrderLabel(provider, orderId) {
  const digits = String(orderId || '').replace(/\D/g, '');
  if (!digits) return '';
  if (provider === 'keeta' && digits.length > 4) return digits.slice(-4);
  return digits;
}

function autoIngestNotice(provider, { synced = 0, orderId = '' } = {}) {
  const name = platformDisplayName(provider);
  const count = Number(synced) || 0;
  if (count > 1) return `تم جلب ${count} طلبات جديدة تلقائياً من ${name}`;
  const label = shortOrderLabel(provider, orderId);
  return `تم جلب طلب جديد تلقائياً من ${name}${label ? ` #${label}` : ''}`;
}

function platformRow(provider, payload = {}) {
  const ingestedIds = Array.isArray(payload.ingestedIds) ? payload.ingestedIds : [];
  return {
    provider,
    checked: Number(payload.checked) || 0,
    synced: Number(payload.synced ?? payload.ingested) || 0,
    failed: Number(payload.failed) || 0,
    customersUpdated: Number(payload.customersUpdated) || 0,
    purged: Number(payload.purged) || 0,
    unread: Boolean(payload.unread),
    alert: String(payload.alert || ''),
    error: payload.error ? String(payload.error).slice(0, 300) : '',
    orderId: String(payload.orderId || ingestedIds[0] || ''),
    background: Boolean(payload.background),
  };
}

function summarizePlatformSync(results) {
  const total = (key) =>
    results.reduce((sum, row) => sum + (Number(row[key]) || 0), 0);
  return {
    ok: true,
    platforms: results.length,
    checked: total('checked'),
    synced: total('synced'),
    failed: total('failed'),
    customersUpdated: total('customersUpdated'),
    purged: total('purged'),
    details: results.map((row) => ({
      provider: row.provider,
      checked: row.checked,
      synced: row.synced,
      purged: row.purged,
      unread: Boolean(row.unread),
      alert: row.alert || '',
      error: row.error || '',
    })),
  };
}

async function runIsolatedPlatformSync({
  providers,
  runProvider,
  onPlatformResult,
  logger = console,
}) {
  const names = Array.isArray(providers) ? providers : [];
  const results = await Promise.all(
    names.map(async (provider) => {
      try {
        const payload = await runProvider(provider);
        const row = platformRow(provider, payload);
        if (typeof onPlatformResult === 'function') onPlatformResult(row);
        return row;
      } catch (error) {
        const row = platformRow(provider, {
          failed: 1,
          unread: true,
          error: error?.message || error,
        });
        logger.warn(
          `[Sync] ${provider} failed independently: ${row.error}`,
        );
        if (typeof onPlatformResult === 'function') onPlatformResult(row);
        return row;
      }
    }),
  );
  return summarizePlatformSync(results);
}

module.exports = {
  autoIngestNotice,
  platformDisplayName,
  platformRow,
  runIsolatedPlatformSync,
  shortOrderLabel,
  summarizePlatformSync,
};
