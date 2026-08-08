const { containsArabic, translateWithDictionary, translateCategoryName } = require('./bilingualMenu');

const MYMEMORY_URL = 'https://api.mymemory.translated.net/get';
const REQUEST_TIMEOUT_MS = 8000;

function detectLanguage(text) {
  const value = String(text || '').trim();
  if (!value) return null;
  return containsArabic(value) ? 'ar' : 'en';
}

function normalizeBilingualFields(raw = {}) {
  const nameAr = String(raw.name_ar ?? raw.nameAr ?? raw.name ?? '').trim();
  const nameEn = String(raw.name_en ?? raw.nameEn ?? '').trim();
  const descriptionAr = String(
    raw.description_ar ?? raw.descriptionAr ?? raw.description ?? '',
  ).trim();
  const descriptionEn = String(raw.description_en ?? raw.descriptionEn ?? '').trim();
  const name = nameAr || nameEn || String(raw.name ?? '').trim();
  const description = descriptionAr || descriptionEn || String(raw.description ?? '').trim();

  return {
    name_ar: nameAr,
    name_en: nameEn,
    description_ar: descriptionAr,
    description_en: descriptionEn,
    name,
    description,
  };
}

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function translateWithMyMemory(text, fromLang, toLang) {
  const query = String(text || '').trim();
  if (!query) return '';

  const url = `${MYMEMORY_URL}?q=${encodeURIComponent(query)}&langpair=${fromLang}|${toLang}`;
  const response = await fetchWithTimeout(url);
  if (!response.ok) {
    throw new Error(`MyMemory HTTP ${response.status}`);
  }

  const payload = await response.json();
  const translated = String(payload?.responseData?.translatedText || '').trim();
  if (!translated) {
    throw new Error('Empty translation response');
  }
  if (/MYMEMORY WARNING/i.test(translated)) {
    throw new Error('MyMemory quota warning');
  }

  return translated;
}

function dictionaryFallback(text, fromLang, toLang) {
  const query = String(text || '').trim();
  if (!query) return '';

  if (fromLang === 'ar' && toLang === 'en') {
    const translated = translateWithDictionary(query);
    return translated && !containsArabic(translated) ? translated : query;
  }

  if (fromLang === 'en' && toLang === 'ar') {
    return query;
  }

  return query;
}

async function translateText(text, fromLang, toLang) {
  const query = String(text || '').trim();
  if (!query) return '';
  if (fromLang === toLang) return query;

  try {
    return await translateWithMyMemory(query, fromLang, toLang);
  } catch (error) {
    console.warn('Auto-translate API fallback:', error.message || error);
    return dictionaryFallback(query, fromLang, toLang);
  }
}

async function translateMissingField(value, oppositeValue, fromLang, toLang) {
  const primary = String(value || '').trim();
  const opposite = String(oppositeValue || '').trim();
  if (!primary || opposite) return opposite;
  return translateText(primary, fromLang, toLang);
}

async function ensureAutoTranslatedBilingual(raw = {}) {
  const base = normalizeBilingualFields(raw);

  let nameAr = base.name_ar;
  let nameEn = base.name_en;
  let descriptionAr = base.description_ar;
  let descriptionEn = base.description_en;

  if (nameAr && !nameEn) {
    nameEn = await translateText(nameAr, 'ar', 'en');
  } else if (nameEn && !nameAr) {
    nameAr = await translateText(nameEn, 'en', 'ar');
  } else if (!nameAr && !nameEn) {
    const fallbackName = String(raw.name || '').trim();
    if (fallbackName) {
      const lang = detectLanguage(fallbackName);
      if (lang === 'ar') {
        nameAr = fallbackName;
        nameEn = await translateText(fallbackName, 'ar', 'en');
      } else if (lang === 'en') {
        nameEn = fallbackName;
        nameAr = await translateText(fallbackName, 'en', 'ar');
      }
    }
  }

  descriptionEn = await translateMissingField(descriptionAr, descriptionEn, 'ar', 'en');
  descriptionAr = await translateMissingField(descriptionEn, descriptionAr, 'en', 'ar');

  if (descriptionAr && !descriptionEn) {
    descriptionEn = await translateText(descriptionAr, 'ar', 'en');
  } else if (descriptionEn && !descriptionAr) {
    descriptionAr = await translateText(descriptionEn, 'en', 'ar');
  }

  return normalizeBilingualFields({
    ...raw,
    name_ar: nameAr,
    name_en: nameEn,
    description_ar: descriptionAr,
    description_en: descriptionEn,
  });
}

async function ensureAutoTranslatedCategory(raw = {}, existing = {}) {
  const categoryName = String(
    raw.category_name ?? raw.categoryName ?? existing.category_name ?? existing.categoryName ?? 'عام',
  ).trim();
  let categoryNameEn = String(
    raw.category_name_en ?? raw.categoryNameEn ?? existing.category_name_en ?? existing.categoryNameEn ?? '',
  ).trim();

  if (categoryName && !categoryNameEn) {
    if (containsArabic(categoryName)) {
      categoryNameEn =
        (await translateText(categoryName, 'ar', 'en')) || translateCategoryName(categoryName);
    } else {
      categoryNameEn = categoryName;
    }
  } else if (categoryNameEn && !categoryName) {
    // no-op
  } else if (categoryName && !categoryNameEn) {
    categoryNameEn = translateCategoryName(categoryName);
  }

  return {
    category_name: categoryName || 'عام',
    category_name_en: categoryNameEn || translateCategoryName(categoryName || 'عام'),
    categoryNameEn: categoryNameEn || translateCategoryName(categoryName || 'عام'),
  };
}

module.exports = {
  detectLanguage,
  normalizeBilingualFields,
  translateText,
  ensureAutoTranslatedBilingual,
  ensureAutoTranslatedCategory,
};
