const { containsArabic, itemNeedsBilingualMigration, migrateMenuItem } = require('./bilingualMenu');
const {
  ensureAutoTranslatedBilingual,
  ensureAutoTranslatedCategory,
  normalizeBilingualFields,
} = require('./autoTranslate');

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function itemNeedsAutoTranslation(item) {
  if (itemNeedsBilingualMigration(item)) return true;

  const fields = normalizeBilingualFields(item);
  const categoryName = String(item.category_name ?? item.categoryName ?? '').trim();
  const categoryEn = String(item.category_name_en ?? item.categoryNameEn ?? '').trim();

  if (fields.name_ar && fields.name_en && containsArabic(fields.name_en)) return true;
  if (fields.name_en && !fields.name_ar) return true;
  if (fields.description_en && !fields.description_ar) return true;
  if (categoryName && !categoryEn) return true;

  return false;
}

async function autoTranslateMenuItem(item) {
  const category = await ensureAutoTranslatedCategory(item, item);
  const bilingual = await ensureAutoTranslatedBilingual({ ...item, ...category });
  return migrateMenuItem({ ...item, ...category, ...bilingual });
}

async function autoTranslateMenuItems(items, options = {}) {
  const delayMs = options.delayMs ?? 250;
  const onProgress = options.onProgress;

  if (!Array.isArray(items)) {
    return { items: [], updated: 0, scanned: 0 };
  }

  let updated = 0;
  const migrated = [];

  for (let index = 0; index < items.length; index += 1) {
    const item = items[index];
    const needsTranslation = itemNeedsAutoTranslation(item);

    if (needsTranslation) {
      const next = await autoTranslateMenuItem(item);
      const changed =
        JSON.stringify(normalizeBilingualFields(next)) !==
        JSON.stringify(normalizeBilingualFields(item));
      if (changed) updated += 1;
      migrated.push(next);
      if (onProgress) onProgress(index + 1, items.length, item.id, true);
      if (delayMs > 0 && index < items.length - 1) {
        await sleep(delayMs);
      }
    } else {
      migrated.push(migrateMenuItem(item));
      if (onProgress) onProgress(index + 1, items.length, item.id, false);
    }
  }

  return { items: migrated, updated, scanned: items.length };
}

function normalizeMenuItemForApi(item) {
  return migrateMenuItem(item);
}

function normalizeMenuItemsForApi(items) {
  if (!Array.isArray(items)) return [];
  return items.map((item) => normalizeMenuItemForApi(item));
}

module.exports = {
  itemNeedsAutoTranslation,
  autoTranslateMenuItem,
  autoTranslateMenuItems,
  normalizeMenuItemForApi,
  normalizeMenuItemsForApi,
};
