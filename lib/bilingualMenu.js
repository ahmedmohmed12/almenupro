/**
 * Bilingual menu migration: backfills name_en / description_en (and category_name_en)
 * for legacy items that only have Arabic name/description fields.
 */

const ITEM_TRANSLATIONS = {
  1962105681: {
    name_en: 'Kinder Mini Bites',
    description_en: 'Kinder mini bites, 40 pieces in the box',
  },
  1962105679: {
    name_en: 'Mixed Mini Bites',
    description_en: 'Assorted mini bites, 40 pieces in the box',
  },
  1962105699: {
    name_en: 'Kinder Chocolate Cookies',
    description_en: '16 pieces, served with chocolate sauce',
  },
  1962105673: {
    name_en: '2 Mini Bites Boxes',
    description_en: '40 pieces per box',
  },
  1962105665: {
    name_en: 'Molten Nutella',
    description_en: '6 pieces',
  },
  1962105689: {
    name_en: 'Nutella Mini Bites',
    description_en: 'Nutella chocolate mini bites, 40 pieces in the box',
  },
  600220024: {
    name_en: 'Extra Chocolate Cookies',
    description_en:
      'Extra milk chocolate cookies with delicious chocolate sauce, 15 pieces in the box',
  },
  1962105672: {
    name_en: '2 Cookie Boxes',
    description_en: '20 pieces per box',
  },
  1962105670: {
    name_en: '2 Large Cookie Boxes',
    description_en: '16 pieces per box, served with chocolate sauce',
  },
  600217645: {
    name_en: 'Kinder Mini Max',
    description_en: 'Kinder Mini Max with delicious chocolate sauce, 32 pieces in a box',
  },
  1962105675: {
    name_en: 'Toblerone Mini Bites',
    description_en: 'Toblerone milk chocolate mini bites, 40 pieces in the box',
  },
  1962105685: {
    name_en: "Hershey's Cookies Mini Bites",
    description_en: "Hershey's chocolate mini bites, 40 pieces in the box",
  },
  1962105687: {
    name_en: "Hershey's White Chocolate Mini Bites",
    description_en: "White Hershey's chocolate mini bites, 40 pieces in the box",
  },
  1962105691: {
    name_en: 'Oreo Mini Bites 40 Pieces',
    description_en: 'Oreo mini bites, 40 pieces in the box',
  },
  1962105693: {
    name_en: 'Pistachio Mini Bites 40 Pieces',
    description_en: 'Pistachio mini bites, 40 pieces in the box',
  },
  1962105677: {
    name_en: 'Double Chocolate Mini Bites',
    description_en: 'Double chocolate mini bites, 40 pieces in the box',
  },
  1962105695: {
    name_en: 'Pistachio Stuffed Cookies',
    description_en: '16 pieces, served with chocolate sauce',
  },
  1962105697: {
    name_en: 'Double Chocolate Cookies',
    description_en: '16 pieces, served with chocolate sauce',
  },
  1962105702: {
    name_en: 'Nutella Chocolate Cookies',
    description_en: '16 pieces, served with chocolate sauce',
  },
  1962105703: {
    name_en: 'Assorted Cookies',
    description_en: '16 pieces, served with chocolate sauce',
  },
  1962105705: {
    name_en: 'White Nutella Chocolate Cookies',
    description_en: '16 pieces, served with chocolate sauce',
  },
  1962105707: {
    name_en: 'Molten Kinder',
    description_en: '6 pieces',
  },
  172097966: {
    name_en: 'Molten Nutella',
    description_en: 'Molten Nutella, 6 pieces',
  },
  1962105653: {
    name_en: 'Toblerone Cookies',
    description_en: 'Toblerone chocolate cookies, 20 pieces in the box',
  },
  1962105654: {
    name_en: "Hershey's Cookies",
    description_en: "Hershey's chocolate cookies, 20 pieces in the box",
  },
  1962105655: {
    name_en: "Hershey's White Chocolate Cookies",
    description_en: "White Hershey's chocolate cookies, 20 pieces in the box",
  },
  1962105656: {
    name_en: "Reese's Cookies",
    description_en: "Reese's chocolate cookies, 20 pieces in the box",
  },
  1962105657: {
    name_en: 'Mixed Cookies',
    description_en: 'Assorted cookies, 20 pieces in the box',
  },
  1962105658: {
    name_en: 'Custom Box',
    description_en: '20 assorted pieces of your choice in the box',
  },
  1962105659: {
    name_en: 'Nutella Cookies',
    description_en: 'Nutella cookies, 20 pieces in the box',
  },
  1962105660: {
    name_en: 'Double Cookies',
    description_en: 'Double chocolate cookies, 20 pieces in the box',
  },
  1962105661: {
    name_en: 'Pistachio Cookies',
    description_en: 'Pistachio flavored cookies, 20 pieces in the box',
  },
  1962105662: {
    name_en: 'Oreo Cookies',
    description_en: 'Oreo cookies, 20 pieces in the box',
  },
  1962105663: {
    name_en: 'Chocolate Chip Cookies',
    description_en: 'Chocolate chip cookies, 20 pieces in the box',
  },
  1962105664: {
    name_en: 'Assorted Molten Cookies',
    description_en: '6 pieces of Kinder and Nutella',
  },
  1962105667: {
    name_en: 'Galaxy Chocolate Cookies',
    description_en: '20 cookies with Galaxy milk chocolate',
  },
};

const CATEGORY_TRANSLATIONS = {
  'مينى بايتس': 'Mini Bites',
  'كوكيز كب': 'Large Cookies',
  'اختيارات على ذوقك 🔥': 'Picks for You 🔥',
  كوكيز: 'Cookies',
  'اكسترا كوكيز': 'Extra Cookies',
  العروض: 'Offers',
  'مولتن كوكيز': 'Molten Cookies',
};

const PHRASE_REPLACEMENTS = [
  ['مينى بايتس', 'Mini Bites'],
  ['ميني بايتس', 'Mini Bites'],
  ['كوكيز', 'Cookies'],
  ['شوكولاتة', 'Chocolate'],
  ['شيكولاتة', 'Chocolate'],
  ['نوتيلا', 'Nutella'],
  ['كيندر', 'Kinder'],
  ['توبليرون', 'Toblerone'],
  ['هرشيز', "Hershey's"],
  ['هيرشيز', "Hershey's"],
  ['اوريو', 'Oreo'],
  ['بوستاشو', 'Pistachio'],
  ['بستاشيو', 'Pistachio'],
  ['فستق', 'Pistachio'],
  ['مولتن', 'Molten'],
  ['مولتون', 'Molten'],
  ['دوبل', 'Double'],
  ['دبل', 'Double'],
  ['ميكس', 'Mixed'],
  ['مشكل', 'Assorted'],
  ['مشكلة', 'Assorted'],
  ['منوعة', 'Assorted'],
  ['ريسز', "Reese's"],
  ['جلاكسي', 'Galaxy'],
  ['40 قطعة', '40 pieces'],
  ['40 قطعه', '40 pieces'],
  ['32 حبة', '32 pieces'],
  ['20 قطعة', '20 pieces'],
  ['16 قطعة', '16 pieces'],
  ['15 قطعه', '15 pieces'],
  ['6 حبات', '6 pieces'],
  ['6 قطع', '6 pieces'],
  ['داخل البوكس', 'in the box'],
  ['داخل العلبة', 'in the box'],
  ['داحل البوكس', 'in the box'],
  ['تقدم مع صوص شوكولاتة', 'served with chocolate sauce'],
  ['لكل بوكس', 'per box'],
  ['2 بوكس', '2 boxes'],
  ['بوكس', 'box'],
  ['قطعة', 'piece'],
];

function containsArabic(text) {
  return /[\u0600-\u06FF]/.test(String(text || ''));
}

function translateCategoryName(categoryName) {
  const key = String(categoryName || '').trim();
  if (!key) return '';
  return CATEGORY_TRANSLATIONS[key] || key;
}

function translateWithDictionary(text) {
  let result = String(text || '').trim();
  if (!result || !containsArabic(result)) return result;

  for (const [from, to] of PHRASE_REPLACEMENTS) {
    result = result.split(from).join(to);
  }

  result = result.replace(/\s+/g, ' ').trim();
  if (containsArabic(result)) {
    return result;
  }
  return result;
}

function resolveEnglishName(item, nameAr) {
  const existing = String(item.name_en ?? item.nameEn ?? '').trim();
  if (existing) return existing;

  const byId = ITEM_TRANSLATIONS[Number(item.id)]?.name_en;
  if (byId) return byId;

  const legacyName = String(item.name || '').trim();
  if (legacyName && !containsArabic(legacyName)) return legacyName;

  return translateWithDictionary(nameAr);
}

function resolveEnglishDescription(item, descriptionAr) {
  const existing = String(item.description_en ?? item.descriptionEn ?? '').trim();
  if (existing) return existing;

  const byId = ITEM_TRANSLATIONS[Number(item.id)]?.description_en;
  if (byId) return byId;

  const legacyDescription = String(item.description || '').trim();
  if (legacyDescription && !containsArabic(legacyDescription)) {
    return legacyDescription;
  }

  if (!descriptionAr) return '';
  return translateWithDictionary(descriptionAr);
}

function itemNeedsBilingualMigration(item) {
  const nameAr = String(item.name_ar ?? item.nameAr ?? item.name ?? '').trim();
  const nameEn = String(item.name_en ?? item.nameEn ?? '').trim();
  const descriptionAr = String(
    item.description_ar ?? item.descriptionAr ?? item.description ?? '',
  ).trim();
  const descriptionEn = String(item.description_en ?? item.descriptionEn ?? '').trim();
  const categoryEn = String(item.category_name_en ?? item.categoryNameEn ?? '').trim();

  if (!nameAr && !nameEn) return false;

  const needsNameEn = nameAr && !nameEn;
  const needsDescriptionEn = descriptionAr && !descriptionEn;
  const needsCategoryEn =
    String(item.category_name ?? item.categoryName ?? '').trim() && !categoryEn;

  return needsNameEn || needsDescriptionEn || needsCategoryEn || !item.name_ar;
}

function migrateMenuItem(item) {
  const categoryName = String(
    item.category_name ?? item.categoryName ?? item.category ?? 'عام',
  ).trim();
  const nameAr = String(item.name_ar ?? item.nameAr ?? item.name ?? '').trim();
  const descriptionAr = String(
    item.description_ar ?? item.descriptionAr ?? item.description ?? '',
  ).trim();
  const nameEn = resolveEnglishName(item, nameAr);
  const descriptionEn = resolveEnglishDescription(item, descriptionAr);
  const categoryNameEn =
    String(item.category_name_en ?? item.categoryNameEn ?? '').trim() ||
    translateCategoryName(categoryName);

  return {
    ...item,
    category_name: categoryName || 'عام',
    category_name_en: categoryNameEn,
    categoryNameEn: categoryNameEn,
    name_ar: nameAr,
    name_en: nameEn,
    description_ar: descriptionAr,
    description_en: descriptionEn,
    name: nameAr || nameEn || String(item.name || '').trim(),
    description: descriptionAr || descriptionEn || String(item.description || '').trim(),
    nameAr: nameAr,
    nameEn: nameEn,
    descriptionAr: descriptionAr,
    descriptionEn: descriptionEn,
  };
}

function migrateMenuItems(items) {
  if (!Array.isArray(items)) return { items: [], updated: 0 };

  let updated = 0;
  const migrated = items.map((item) => {
    if (!itemNeedsBilingualMigration(item)) {
      return migrateMenuItem(item);
    }
    updated += 1;
    return migrateMenuItem(item);
  });

  return { items: migrated, updated };
}

module.exports = {
  ITEM_TRANSLATIONS,
  CATEGORY_TRANSLATIONS,
  containsArabic,
  translateCategoryName,
  translateWithDictionary,
  itemNeedsBilingualMigration,
  migrateMenuItem,
  migrateMenuItems,
};
