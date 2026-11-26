function normalizeSalesPlatformsList(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((row) => {
      const id = String(row?.id || row?.key || '')
        .trim()
        .toLowerCase()
        .replace(/\s+/g, '_');
      const name = String(row?.name || row?.label || '').trim();
      if (!id || !name) return null;
      const commission = Number(
        row?.commissionPercent ?? row?.commission_percent ?? 0,
      );
      return {
        id,
        name,
        commissionPercent: Math.round((Number.isFinite(commission) ? commission : 0) * 1000) / 1000,
        color: row?.color || row?.colorArgb || row?.color_argb || '#475569',
        isBuiltIn: row?.isBuiltIn === true || row?.is_built_in === true,
      };
    })
    .filter(Boolean);
}

module.exports = { normalizeSalesPlatformsList };