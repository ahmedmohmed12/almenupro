const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

const PROMO_SECTION_HINTS = [
  'pick',
  'اختيارات',
  'عروض',
  'offer',
  'promotion',
];

function extractNextData(html) {
  const match = html.match(
    /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/,
  );
  if (!match) return null;
  return JSON.parse(match[1]);
}

function decodeHtml(value) {
  return String(value || '')
    .replace(/&amp;/g, '&')
    .replace(/&#x27;/g, "'")
    .trim();
}

function normalizeImageUrl(item) {
  const raw = item.originalImage || item.image || '';
  const cleaned = decodeHtml(raw.split('?')[0]);
  if (!cleaned) return '';
  if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
    return cleaned;
  }
  return `https://${cleaned}`;
}

function isPromoSection(name) {
  const normalized = String(name || '').trim().toLowerCase();
  return PROMO_SECTION_HINTS.some((hint) => normalized.includes(hint));
}

function resolveCategoryName(item, fallbackCategory) {
  return (
    (item.originalSection || item.sectionName || fallbackCategory || 'عام')
      .trim() || 'عام'
  );
}

function buildMenuItem(item, fallbackCategory) {
  const name = (item.name || '').trim();
  const price = Number(item.price) || 0;

  return {
    talabatId: item.id,
    name,
    description: (item.description || '').trim(),
    price: Math.round(price * 1000) / 1000,
    categoryName: resolveCategoryName(item, fallbackCategory),
    imageUrl: normalizeImageUrl(item),
    isAvailable: true,
    source: 'Talabat',
  };
}

function shouldReplaceExisting(existing, candidate) {
  if (isPromoSection(existing.categoryName) && !isPromoSection(candidate.categoryName)) {
    return true;
  }

  if (!isPromoSection(existing.categoryName) && isPromoSection(candidate.categoryName)) {
    return false;
  }

  return false;
}

function collectCategoryItems(category, bucket) {
  const categoryName = category.name || 'عام';

  for (const item of category.items || []) {
    bucket.push({ item, fallbackCategory: categoryName });
  }

  for (const sub of category.subCategories || category.subcategories || []) {
    collectCategoryItems(
      {
        ...sub,
        name: sub.name || categoryName,
      },
      bucket,
    );
  }
}

function parseMenuFromHtml(html) {
  const next = extractNextData(html);
  if (!next) {
    throw new Error('تعذر قراءة بيانات Talabat من الصفحة');
  }

  const menuState = next.props?.pageProps?.initialMenuState?.menuData;
  if (!menuState?.categories?.length) {
    return null;
  }

  const rawEntries = [];
  for (const category of menuState.categories) {
    collectCategoryItems(category, rawEntries);
  }

  const byTalabatId = new Map();
  const byName = new Map();

  for (const entry of rawEntries) {
    const { item, fallbackCategory } = entry;
    const name = (item.name || '').trim();
    if (!name) continue;

    const candidate = buildMenuItem(item, fallbackCategory);
    const talabatId = item.id;

    if (talabatId != null) {
      const existing = byTalabatId.get(talabatId);
      if (!existing) {
        byTalabatId.set(talabatId, candidate);
      } else if (shouldReplaceExisting(existing, candidate)) {
        byTalabatId.set(talabatId, candidate);
      }
      continue;
    }

    const nameKey = name.toLowerCase();
    const existingByName = byName.get(nameKey);
    if (!existingByName) {
      byName.set(nameKey, candidate);
    } else if (shouldReplaceExisting(existingByName, candidate)) {
      byName.set(nameKey, candidate);
    }
  }

  const merged = new Map();
  for (const item of byTalabatId.values()) {
    merged.set(`id:${item.talabatId}`, item);
  }
  for (const item of byName.values()) {
    const key = item.talabatId != null ? `id:${item.talabatId}` : `name:${item.name.toLowerCase()}`;
    if (!merged.has(key)) {
      merged.set(key, item);
    }
  }

  return Array.from(merged.values());
}

function parseBrandInfo(html) {
  const next = extractNextData(html);
  if (!next) return null;

  const data = next.props?.pageProps?.data;
  if (!data?.vendorId) return null;

  const countrySlug =
    next.props?.pageProps?.currentURL?.split('/')?.filter(Boolean)?.[0] ||
    'kuwait';

  return {
    vendorId: data.vendorId,
    branchId: data.id,
    branchSlug: data.branchSlug || data.restaurantSlug,
    countrySlug,
    countryId: data.countryId,
  };
}

async function fetchHtml(url) {
  const response = await fetch(url, {
    headers: {
      'User-Agent': USER_AGENT,
      Accept: 'text/html,application/xhtml+xml',
    },
    redirect: 'follow',
  });

  if (!response.ok) {
    throw new Error(`Talabat responded with ${response.status}`);
  }

  return response.text();
}

function parseTalabatUrl(rawUrl) {
  const url = new URL(rawUrl.trim());
  const parts = url.pathname.split('/').filter(Boolean);
  const isArabic = parts[0] === 'ar';
  const offset = isArabic ? 1 : 0;
  const country = parts[offset];
  const section = parts[offset + 1];

  if (section === 'restaurant' && parts[offset + 2]) {
    return {
      type: 'menu',
      country,
      vendorId: parts[offset + 2],
      menuUrl: url.toString(),
    };
  }

  return {
    type: 'brand',
    country,
    brandSlug: section,
    brandUrl: url.toString(),
  };
}

async function resolveMenuUrl(inputUrl) {
  const parsed = parseTalabatUrl(inputUrl);

  if (parsed.type === 'menu') {
    return parsed.menuUrl;
  }

  const brandHtml = await fetchHtml(parsed.brandUrl);
  const brand = parseBrandInfo(brandHtml);
  if (!brand) {
    throw new Error(
      'تعذر العثور على بيانات المطعم. تأكد من رابط Talabat الصحيح',
    );
  }

  return `https://www.talabat.com/${brand.countrySlug}/restaurant/${brand.vendorId}/${brand.branchSlug}?aid=${brand.branchId}`;
}

async function scrapeTalabatMenu(inputUrl) {
  const menuUrl = await resolveMenuUrl(inputUrl);
  const html = await fetchHtml(menuUrl);
  const items = parseMenuFromHtml(html);

  if (!items?.length) {
    throw new Error(
      'لم يتم العثور على أصناف. تأكد أن الرابط يفتح صفحة المنيو في Talabat',
    );
  }

  return { menuUrl, items };
}

module.exports = {
  scrapeTalabatMenu,
  parseMenuFromHtml,
  parseBrandInfo,
  parseTalabatUrl,
};

if (require.main === module) {
  const url = process.argv[2];
  scrapeTalabatMenu(url)
    .then((result) => {
      console.log('menuUrl', result.menuUrl);
      console.log('items', result.items.length);
      console.log(JSON.stringify(result.items.slice(0, 3), null, 2));
    })
    .catch((error) => {
      console.error(error.message);
      process.exit(1);
    });
}
