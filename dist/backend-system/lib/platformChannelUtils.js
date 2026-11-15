const LEGACY_LABELS = {
  pos: 'محلي / POS',
  menu: 'المنيو / الموقع',
  whatsapp: 'WhatsApp',
  web: 'الموقع المباشر',
  direct: 'الموقع المباشر',
  talabat: 'Talabat',
  keeta: 'Keeta',
  jahez: 'Jahez',
  other_platform: 'منصة أخرى',
  other: 'منصة أخرى',
};

function sanitizePlatformKey(raw) {
  const value = String(raw ?? 'pos').trim().toLowerCase();
  if (!value) return 'pos';

  const sanitized = value
    .replace(/\s+/g, '_')
    .replace(/[^a-z0-9_-]/g, '')
    .slice(0, 64);

  return sanitized || 'pos';
}

function resolvePlatformKey(raw) {
  const sanitized = sanitizePlatformKey(raw);
  if (sanitized.includes('talabat')) return 'talabat';
  if (sanitized.includes('keeta')) return 'keeta';
  if (sanitized.includes('jahez')) return 'jahez';
  return sanitized;
}

function humanizePlatformKey(key) {
  const resolved = resolvePlatformKey(key);
  if (LEGACY_LABELS[resolved]) return LEGACY_LABELS[resolved];

  return resolved
    .split('_')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function parseColor(raw) {
  if (raw == null || raw === '') return null;
  const text = String(raw).trim();
  if (text.startsWith('#')) return text;
  return null;
}

function resolvePlatformMeta(platformKey, salesPlatforms = []) {
  const id = resolvePlatformKey(platformKey);

  for (const row of salesPlatforms || []) {
    const rowId = String(row.id || row.key || '')
      .trim()
      .toLowerCase();
    if (rowId === id) {
      return {
        id,
        name: row.name || row.label || humanizePlatformKey(id),
        labelAr: row.name || row.label || humanizePlatformKey(id),
        color: parseColor(row.color ?? row.colorArgb ?? row.color_argb),
        commissionPercent:
          Number(row.commissionPercent ?? row.commission_percent) || 0,
      };
    }
  }

  return {
    id,
    name: humanizePlatformKey(id),
    labelAr: humanizePlatformKey(id),
    color: null,
    commissionPercent: null,
  };
}

function enrichPlatformRows(platforms, salesPlatforms) {
  return (platforms || []).map((row) => {
    const meta = resolvePlatformMeta(row.platform, salesPlatforms);
    return {
      ...row,
      platform: meta.id,
      name: meta.name,
      labelAr: meta.labelAr,
      color: meta.color,
    };
  });
}

function enrichChannelRows(channels, salesPlatforms) {
  return (channels || []).map((row) => {
    const meta = resolvePlatformMeta(row.channel || row.platform, salesPlatforms);
    return {
      ...row,
      channel: meta.id,
      name: meta.name,
      labelAr: meta.labelAr,
      color: meta.color,
    };
  });
}

module.exports = {
  sanitizePlatformKey,
  resolvePlatformKey,
  humanizePlatformKey,
  resolvePlatformMeta,
  enrichPlatformRows,
  enrichChannelRows,
  LEGACY_LABELS,
};
