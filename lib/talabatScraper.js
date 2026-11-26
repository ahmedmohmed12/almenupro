const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const CLOUDFLARE_HELP_AR =
  'Talabat يحجب السحب التلقائي (Cloudflare 403). افتح الرابط في Chrome على جهازك، انسخ محتوى __NEXT_DATA__ من أدوات المطوّر (Elements) أو الصق Cookie من الطلبات الناجحة، ثم أعد المحاولة.';

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
    .replace(/&quot;/g, '"')
    .trim();
}

function coerceImageCandidate(raw) {
  if (raw == null) return '';
  if (typeof raw === 'string') return decodeHtml(raw);
  if (typeof raw === 'object') {
    return decodeHtml(
      raw.url ||
        raw.src ||
        raw.href ||
        raw.image ||
        raw.imageUrl ||
        raw.originalImage ||
        raw.path ||
        '',
    );
  }
  return decodeHtml(String(raw));
}

function normalizeImageUrl(item) {
  const candidates = [
    item?.originalImage,
    item?.original_image,
    item?.image,
    item?.imageUrl,
    item?.image_url,
    item?.nmrImage,
    item?.nmr_image,
    item?.thumbnail,
    item?.thumbnailUrl,
    item?.thumbnail_url,
    item?.productImage,
    item?.product_image,
    item?.coverImage,
    item?.cover_image,
    item?.photo,
    item?.media?.url,
    item?.media?.image,
    Array.isArray(item?.images) ? item.images[0] : null,
    Array.isArray(item?.dishImages) ? item.dishImages[0] : null,
    Array.isArray(item?.dish_images) ? item.dish_images[0] : null,
  ];

  let cleaned = '';
  for (const candidate of candidates) {
    cleaned = coerceImageCandidate(candidate);
    if (cleaned) break;
  }
  if (!cleaned) return '';

  // Keep useful CDN query params (some hosts need them); drop tracking-only junk later if needed.
  if (cleaned.startsWith('//')) {
    return `https:${cleaned}`;
  }
  if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
    return cleaned;
  }
  if (cleaned.startsWith('/')) {
    return `https://images.deliveryhero.io${cleaned}`;
  }
  // Protocol-less host path: images.deliveryhero.io/...
  if (/^[\w.-]+\.[a-z]{2,}\//i.test(cleaned) || cleaned.includes('deliveryhero.io')) {
    return `https://${cleaned.replace(/^\/+/, '')}`;
  }
  return `https://${cleaned.replace(/^\/+/, '')}`;
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
  const talabatId = item.id ?? null;

  return {
    talabatId,
    talabat_id: talabatId,
    name,
    description: (item.description || '').trim(),
    price: Math.round(price * 1000) / 1000,
    categoryName: resolveCategoryName(item, fallbackCategory),
    category_name: resolveCategoryName(item, fallbackCategory),
    imageUrl: normalizeImageUrl(item),
    image_url: normalizeImageUrl(item),
    isAvailable: true,
    is_available: 1,
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

function menuDataFromNextRoot(next) {
  if (!next || typeof next !== 'object') return null;
  return (
    next.props?.pageProps?.initialMenuState?.menuData ||
    next.props?.pageProps?.menuData ||
    next.pageProps?.initialMenuState?.menuData ||
    (Array.isArray(next.categories) ? next : null)
  );
}

function flattenMenuCategories(menuState) {
  if (!menuState?.categories?.length) return null;

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
    const key =
      item.talabatId != null
        ? `id:${item.talabatId}`
        : `name:${item.name.toLowerCase()}`;
    if (!merged.has(key)) {
      merged.set(key, item);
    }
  }

  return Array.from(merged.values());
}

function parseMenuFromNextRoot(next) {
  const menuState = menuDataFromNextRoot(next);
  return flattenMenuCategories(menuState);
}

function parseMenuFromBffJson(data) {
  if (!data || typeof data !== 'object') return null;
  const menuState =
    data.initialMenuState?.menuData ||
    data.menuData ||
    (data.menu?.categories ? data.menu : null) ||
    (Array.isArray(data.categories) ? data : null);
  return flattenMenuCategories(menuState);
}

function parseMenuFromHtml(html) {
  const next = extractNextData(html);
  if (!next) {
    if (String(html || '').trim().startsWith('{')) {
      try {
        return parseMenuFromNextRoot(JSON.parse(html));
      } catch (_) {}
    }
    throw new Error('تعذر قراءة بيانات Talabat من الصفحة');
  }
  const items = parseMenuFromNextRoot(next);
  if (!items?.length) {
    return null;
  }
  return items;
}

function cloudflareError(status) {
  const err = new Error(
    status === 403 ? CLOUDFLARE_HELP_AR : `Talabat responded with ${status}`,
  );
  err.code = status === 403 ? 'TALABAT_CLOUDFLARE' : 'TALABAT_HTTP';
  err.status = status;
  return err;
}

function buildFetchHeaders(referer, cookie) {
  const headers = {
    'User-Agent': USER_AGENT,
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'ar-KW,ar;q=0.9,en-US;q=0.8,en;q=0.7',
    Referer: referer || 'https://www.talabat.com/',
    'X-Requested-With': 'XMLHttpRequest',
    'sec-ch-ua': '"Chromium";v="131", "Not_A Brand";v="24"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
  };
  const cookieValue = String(cookie || '').trim();
  if (cookieValue) {
    headers.Cookie = cookieValue;
  }
  return headers;
}

function parseTalabatUrlDetails(rawUrl) {
  const parsed = parseTalabatUrl(rawUrl);
  const url = new URL(rawUrl.trim());
  const aid = url.searchParams.get('aid') || url.searchParams.get('areaId');
  return {
    ...parsed,
    aid,
    menuUrl: url.toString(),
    branchId: parsed.type === 'menu' ? parsed.vendorId : null,
    country: parsed.type === 'menu' ? parsed.country : null,
  };
}

function normalizeManualMenuItem(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const name = String(raw.name || raw.title || '').trim();
  if (!name) return null;
  const talabatId = raw.talabatId ?? raw.talabat_id ?? raw.id ?? null;
  const categoryName = String(
    raw.categoryName || raw.category_name || raw.category || raw.section || 'عام',
  ).trim() || 'عام';
  const price = Math.round((Number(raw.price) || 0) * 1000) / 1000;
  const imageUrl =
    normalizeImageUrl(raw) ||
    String(raw.imageUrl || raw.image_url || raw.image || '').trim();
  return {
    talabatId,
    talabat_id: talabatId,
    name,
    description: String(raw.description || '').trim(),
    price,
    categoryName,
    category_name: categoryName,
    imageUrl,
    image_url: imageUrl,
    isAvailable: true,
    is_available: 1,
    source: 'Talabat',
  };
}

function parseBookmarkletExport(data) {
  if (!data || typeof data !== 'object') return null;
  const list =
    data.items ||
    data.menu?.items ||
    data.menu?.categories?.flatMap((c) => c.items || []) ||
    null;
  if (!Array.isArray(list) || !list.length) return null;
  const items = list.map(normalizeManualMenuItem).filter(Boolean);
  return items.length ? items : null;
}

function parseAnyManualMenuJson(raw) {
  let data = raw;
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (!trimmed) return null;
    data = JSON.parse(trimmed);
  }
  if (!data || typeof data !== 'object') return null;

  const bookmarklet = parseBookmarkletExport(data);
  if (bookmarklet?.length) {
    return {
      menuUrl: String(data.menuUrl || data.menu_url || '').trim(),
      items: bookmarklet,
    };
  }

  if (Array.isArray(data)) {
    const items = data.map(normalizeManualMenuItem).filter(Boolean);
    if (items.length) return { menuUrl: '', items };
  }

  const fromNext = parseMenuFromNextRoot(data);
  if (fromNext?.length) {
    return { menuUrl: String(data.menuUrl || data.menu_url || '').trim(), items: fromNext };
  }

  return null;
}

function scrapeFromUserPayload({ html, nextData, menuJson, url }) {
  const manualRaw =
    menuJson != null && menuJson !== ''
      ? menuJson
      : nextData != null && nextData !== ''
        ? nextData
        : null;

  if (manualRaw != null) {
    const parsed = parseAnyManualMenuJson(manualRaw);
    if (parsed?.items?.length) {
      return {
        menuUrl: url || parsed.menuUrl || '',
        items: parsed.items,
      };
    }
  }

  let next = null;
  if (nextData != null && nextData !== '') {
    next = typeof nextData === 'string' ? JSON.parse(nextData) : nextData;
  } else if (menuJson != null && menuJson !== '') {
    next = typeof menuJson === 'string' ? JSON.parse(menuJson) : menuJson;
  } else if (html) {
    next = extractNextData(html);
    if (!next && String(html).trim().startsWith('{')) {
      next = JSON.parse(html);
    }
  }
  if (!next) {
    throw new Error(
      'تعذر قراءة JSON — الصق مخرجات Bookmarklet أو __NEXT_DATA__',
    );
  }
  const items = parseMenuFromNextRoot(next);
  if (!items?.length) {
    throw new Error('لم يتم العثور على أصناف في البيانات الملصقة');
  }
  return { menuUrl: url || String(next.menuUrl || '').trim(), items };
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

async function fetchTalabatResponse(url, headers) {
  const response = await fetch(url, { headers, redirect: 'follow' });
  const text = await response.text();
  if (
    !response.ok ||
    text.includes('cf-chl') ||
    text.includes('Attention Required! | Cloudflare')
  ) {
    throw cloudflareError(response.ok ? 403 : response.status);
  }
  return text;
}

async function fetchJson(url, options = {}) {
  const text = await fetchTalabatResponse(
    url,
    buildFetchHeaders(options.referer, options.cookie),
  );
  try {
    return JSON.parse(text);
  } catch (_) {
    throw new Error('استجابة Talabat ليست JSON صالحاً');
  }
}

async function fetchHtml(url, options = {}) {
  const headers = {
    ...buildFetchHeaders(url, options.cookie),
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Cache-Control': 'no-cache',
  };
  return fetchTalabatResponse(url, headers);
}

async function tryFetchMenuBff(details, cookie) {
  if (!details.branchId || !details.country) return null;
  const aidQuery = details.aid
    ? `?areaId=${encodeURIComponent(details.aid)}`
    : '';
  const base = `https://www.talabat.com/${details.country}/nextMenuBff/branch-menus/${details.branchId}`;
  const candidates = [base + aidQuery, `${base}/menu${aidQuery}`];
  for (const bffUrl of candidates) {
    try {
      const data = await fetchJson(bffUrl, {
        referer: details.menuUrl,
        cookie,
      });
      const items = parseMenuFromBffJson(data);
      if (items?.length) {
        return { menuUrl: details.menuUrl, items };
      }
    } catch (_) {
      // try next candidate / fall through to HTML
    }
  }
  return null;
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

async function resolveMenuUrl(inputUrl, cookie = '') {
  const parsed = parseTalabatUrl(inputUrl);

  if (parsed.type === 'menu') {
    return parsed.menuUrl;
  }

  const brandHtml = await fetchHtml(parsed.brandUrl, { cookie });
  const brand = parseBrandInfo(brandHtml);
  if (!brand) {
    throw new Error(
      'تعذر العثور على بيانات المطعم. تأكد من رابط Talabat الصحيح',
    );
  }

  return `https://www.talabat.com/${brand.countrySlug}/restaurant/${brand.vendorId}/${brand.branchSlug}?aid=${brand.branchId}`;
}

async function scrapeTalabatMenu(inputUrl, options = {}) {
  const cookie =
    options.cookie || process.env.TALABAT_CF_COOKIE || '';
  if (options.html || options.nextData || options.menuJson) {
    return scrapeFromUserPayload({ ...options, url: inputUrl });
  }

  const details = parseTalabatUrlDetails(inputUrl);
  const fromBff = await tryFetchMenuBff(details, cookie);
  if (fromBff) return fromBff;

  const menuUrl = await resolveMenuUrl(inputUrl, cookie);
  const html = await fetchHtml(menuUrl, { cookie });
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
  scrapeFromUserPayload,
  parseAnyManualMenuJson,
  parseBookmarkletExport,
  parseMenuFromHtml,
  parseMenuFromNextRoot,
  parseBrandInfo,
  parseTalabatUrl,
  CLOUDFLARE_HELP_AR,
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
