'use strict';

function categoryNameOf(entry) {
  return String(
    entry?.name_ar ||
      entry?.nameAr ||
      entry?.name ||
      entry?.category_name ||
      entry?.categoryName ||
      '',
  ).trim();
}

function normalizeMenuCategory(raw = {}, restaurantId, existing = {}) {
  const nameAr = String(
    raw.name_ar ?? raw.nameAr ?? raw.name ?? existing.name_ar ?? existing.name ?? '',
  ).trim();
  const nameEn = String(
    raw.name_en ?? raw.nameEn ?? existing.name_en ?? existing.nameEn ?? '',
  ).trim();
  const id =
    String(raw.id || existing.id || '').trim() ||
    `cat_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  const sortOrder = Number(
    raw.sort_order ?? raw.sortOrder ?? existing.sort_order ?? existing.sortOrder ?? 0,
  );
  const now = new Date().toISOString();
  return {
    id,
    restaurant_id: String(restaurantId),
    restaurantId: String(restaurantId),
    name: nameAr || nameEn || 'قسم',
    name_ar: nameAr || nameEn || 'قسم',
    nameAr: nameAr || nameEn || 'قسم',
    name_en: nameEn,
    nameEn,
    sort_order: Number.isFinite(sortOrder) ? sortOrder : 0,
    sortOrder: Number.isFinite(sortOrder) ? sortOrder : 0,
    is_active: raw.is_active === false || raw.isActive === false ? false : true,
    isActive: raw.is_active === false || raw.isActive === false ? false : true,
    createdAt: existing.createdAt || raw.createdAt || now,
    updatedAt: now,
  };
}

function publicMenuCategory(category) {
  return {
    id: category.id,
    restaurantId: category.restaurant_id || category.restaurantId,
    restaurant_id: category.restaurant_id || category.restaurantId,
    name: category.name_ar || category.name,
    name_ar: category.name_ar || category.name,
    nameAr: category.name_ar || category.name,
    name_en: category.name_en || '',
    nameEn: category.name_en || '',
    sort_order: Number(category.sort_order ?? category.sortOrder ?? 0) || 0,
    sortOrder: Number(category.sort_order ?? category.sortOrder ?? 0) || 0,
    is_active: category.is_active !== false && category.isActive !== false,
    isActive: category.is_active !== false && category.isActive !== false,
  };
}

function sortCategories(list) {
  return [...(Array.isArray(list) ? list : [])].sort((a, b) => {
    const order =
      (Number(a.sort_order ?? a.sortOrder ?? 0) || 0) -
      (Number(b.sort_order ?? b.sortOrder ?? 0) || 0);
    if (order !== 0) return order;
    return categoryNameOf(a).localeCompare(categoryNameOf(b), 'ar');
  });
}

/** Map of category display name → rank (lower first). */
function buildCategoryRankMap(categories) {
  const ranks = new Map();
  const sorted = sortCategories(categories);
  sorted.forEach((category, index) => {
    const name = categoryNameOf(category);
    if (!name) return;
    ranks.set(name, index);
    ranks.set(name.toLowerCase(), index);
  });
  return ranks;
}

/**
 * Ensure every distinct item category_name has a category row.
 * Returns { categories, created }.
 */
function syncCategoriesFromItemNames(existingCategories, restaurantId, itemCategoryNames) {
  const list = sortCategories(
    (Array.isArray(existingCategories) ? existingCategories : []).filter(
      (entry) =>
        String(entry.restaurant_id || entry.restaurantId) === String(restaurantId),
    ),
  );
  const byName = new Map();
  for (const entry of list) {
    const name = categoryNameOf(entry);
    if (name) byName.set(name.toLowerCase(), entry);
  }

  let maxOrder = list.reduce(
    (max, entry) => Math.max(max, Number(entry.sort_order ?? entry.sortOrder ?? 0) || 0),
    -1,
  );
  let created = 0;
  const names = [];
  const seen = new Set();
  for (const raw of itemCategoryNames || []) {
    const name = String(raw || '').trim();
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    names.push(name);
  }

  for (const name of names) {
    const key = name.toLowerCase();
    if (byName.has(key)) continue;
    maxOrder += 1;
    const row = normalizeMenuCategory(
      { name_ar: name, name: name, sort_order: maxOrder },
      restaurantId,
    );
    list.push(row);
    byName.set(key, row);
    created += 1;
  }

  return { categories: sortCategories(list), created };
}

function applyCategoryReorder(categories, restaurantId, orderedIds) {
  const scoped = (Array.isArray(categories) ? categories : []).filter(
    (entry) =>
      String(entry.restaurant_id || entry.restaurantId) === String(restaurantId),
  );
  const others = (Array.isArray(categories) ? categories : []).filter(
    (entry) =>
      String(entry.restaurant_id || entry.restaurantId) !== String(restaurantId),
  );
  const byId = new Map(scoped.map((entry) => [String(entry.id), entry]));
  const next = [];
  const ids = Array.isArray(orderedIds) ? orderedIds.map(String) : [];
  ids.forEach((id, index) => {
    const existing = byId.get(id);
    if (!existing) return;
    next.push(
      normalizeMenuCategory(
        { ...existing, sort_order: index, sortOrder: index },
        restaurantId,
        existing,
      ),
    );
    byId.delete(id);
  });
  for (const leftover of byId.values()) {
    next.push(
      normalizeMenuCategory(
        {
          ...leftover,
          sort_order: next.length,
          sortOrder: next.length,
        },
        restaurantId,
        leftover,
      ),
    );
  }
  return [...others, ...sortCategories(next)];
}

module.exports = {
  categoryNameOf,
  normalizeMenuCategory,
  publicMenuCategory,
  sortCategories,
  buildCategoryRankMap,
  syncCategoriesFromItemNames,
  applyCategoryReorder,
};
