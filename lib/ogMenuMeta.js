const DEFAULT_FRONTEND_ORIGIN = 'https://frontend-six-lime-13.vercel.app';
const DEFAULT_BACKEND_ORIGIN = 'https://backend-henna-chi-76.vercel.app';

const SOCIAL_CRAWLER_PATTERN =
  /bot|crawl|spider|slurp|facebook|whatsapp|twitter|linkedin|telegram|slack|discord|preview|embed/i;

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function normalizeOrigin(raw, fallback) {
  const value = String(raw || fallback || '').trim().replace(/\/+$/, '');
  return value || fallback;
}

function formatOgText(value) {
  return String(value || '')
    .replace(/\r\n/g, '\n')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{2,}/g, '\n')
    .trim();
}

function resolvePublicDescription(restaurant) {
  const description = formatOgText(
    restaurant.description ??
      restaurant.description_ar ??
      restaurant.descriptionAr ??
      '',
  );
  if (description) return description;
  return `منيو مطعم ${restaurant.name} لطلب الوجبات أونلاين`;
}

function resolveOgDescription(restaurant) {
  const description = formatOgText(
    restaurant.description ??
      restaurant.description_ar ??
      restaurant.descriptionAr ??
      '',
  );
  if (description) return description;
  return `اطلب الآن من منيو ${restaurant.name}`;
}

function resolveAbsoluteAssetUrl(raw, backendOrigin, frontendOrigin) {
  const fallback = `${frontendOrigin}/icons/Icon-512.png`;
  const value = String(raw || '').trim();
  if (!value) return fallback;

  if (value.startsWith('http://') || value.startsWith('https://')) {
    try {
      const host = new URL(value).hostname.toLowerCase();
      if (
        /fbcdn\.net|cdninstagram\.com|instagram\.com|facebook\.com|deliveryhero\.io|talabat\.com|cloudinary\.com|googleusercontent\.com/.test(
          host,
        )
      ) {
        return `${backendOrigin}/api/image-proxy?url=${encodeURIComponent(value)}`;
      }
    } catch (_) {}
    return value;
  }

  if (
    value.startsWith('/menu-images/') ||
    value.startsWith('/api/uploads/menu/') ||
    value.startsWith('/api/image-proxy')
  ) {
    return `${backendOrigin}${value}`;
  }

  if (value.startsWith('/')) {
    return `${frontendOrigin}${value}`;
  }

  return value;
}

function pickFirstMenuItemImage(items = []) {
  for (const item of items) {
    const raw = item.image_url || item.imageUrl || item.image;
    if (String(raw || '').trim()) return String(raw).trim();
  }
  return '';
}

function buildRestaurantOgData(restaurant, options = {}) {
  const slug = String(restaurant.slug || options.slug || '').trim().toLowerCase();
  const frontendOrigin = normalizeOrigin(
    options.frontendOrigin,
    DEFAULT_FRONTEND_ORIGIN,
  );
  const backendOrigin = normalizeOrigin(options.backendOrigin, DEFAULT_BACKEND_ORIGIN);
  const siteOrigin = normalizeOrigin(options.siteOrigin, frontendOrigin);
  const kind = options.kind === 'links' ? 'links' : 'menu';
  const menuPath =
    options.menuPath ||
    (kind === 'links' ? `/r/${slug}/links` : `/${slug}`);
  const canonicalUrl = `${siteOrigin}${menuPath.startsWith('/') ? menuPath : `/${menuPath}`}`;
  const ogUrl = options.ogUrl || canonicalUrl;
  const name = String(
    options.displayName || restaurant.name || slug || 'Restaurant',
  ).trim();
  const title =
    options.title ||
    (kind === 'links'
      ? `${name} — روابط المطعم`
      : `${name} — المنيو الإلكتروني`);
  const description =
    options.description ||
    (kind === 'links'
      ? formatOgText(
          restaurant.description ??
            restaurant.description_ar ??
            restaurant.descriptionAr ??
            '',
        ) || `روابط وتواصل مطعم ${name}`
      : resolvePublicDescription(restaurant));
  const ogDescription =
    options.ogDescription ||
    (kind === 'links'
      ? description
      : resolveOgDescription(restaurant));
  const logoRaw =
    restaurant.logoUrl ||
    restaurant.logo_url ||
    pickFirstMenuItemImage(options.menuItems || options.items);
  const logoUrl =
    options.ogImageUrl ||
    resolveAbsoluteAssetUrl(logoRaw, backendOrigin, frontendOrigin);

  return {
    slug,
    name,
    title,
    description,
    ogDescription,
    canonicalUrl,
    ogUrl,
    logoUrl,
    twitterDescription: description,
    kind,
  };
}

function buildOgMenuHtml(ogData) {
  const title = escapeHtml(ogData.title);
  const name = escapeHtml(ogData.name);
  const description = escapeHtml(ogData.description);
  const ogDescription = escapeHtml(ogData.ogDescription);
  const canonicalUrl = escapeHtml(ogData.canonicalUrl);
  const ogUrl = escapeHtml(ogData.ogUrl || ogData.canonicalUrl);
  const logoUrl = escapeHtml(ogData.logoUrl);
  const twitterDescription = escapeHtml(ogData.twitterDescription);

  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <meta name="description" content="${description}">

  <meta property="og:url" content="${ogUrl}">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${ogDescription}">
  <meta property="og:image" content="${logoUrl}">
  <meta property="og:image:secure_url" content="${logoUrl}">
  <meta property="og:image:type" content="image/jpeg">
  <meta property="og:image:width" content="300">
  <meta property="og:image:height" content="300">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${title}">
  <meta name="twitter:description" content="${twitterDescription}">
  <meta name="twitter:image" content="${logoUrl}">

  <meta http-equiv="refresh" content="0;url=${canonicalUrl}">
  <link rel="canonical" href="${canonicalUrl}">
</head>
<body>
  <p><a href="${canonicalUrl}">${title}</a></p>
  <script>window.location.replace(${JSON.stringify(ogData.canonicalUrl)});</script>
</body>
</html>`;
}

function isSocialCrawler(userAgent) {
  return SOCIAL_CRAWLER_PATTERN.test(String(userAgent || ''));
}

function parseMenuSlugFromPath(pathname) {
  const parsed = parseRestaurantOgRequest(pathname);
  return parsed?.slug || null;
}

/**
 * Parses menu / link-hub /og paths into `{ slug, kind }`.
 * kind: `menu` | `links`
 */
function parseRestaurantOgRequest(pathname) {
  const path = String(pathname || '').replace(/\/+$/, '') || '/';
  let segments = path.split('/').filter(Boolean);
  if (segments.length === 0) return null;

  if (segments[0].toLowerCase() === 'og') {
    segments = segments.slice(1);
  }
  if (segments.length === 0) return null;

  const reserved = new Set([
    'admin',
    'legacy-menu',
    'menu',
    'restaurant',
    'api',
    'og',
    'r',
    'links',
    'login',
    'create',
    'customers',
  ]);

  if (segments.length === 1) {
    const slug = segments[0].toLowerCase();
    if (reserved.has(slug) || slug.includes('.')) return null;
    return { slug, kind: 'menu' };
  }

  const prefix = segments[0].toLowerCase();
  if (prefix === 'menu' || prefix === 'restaurant') {
    const slug = segments[1]?.toLowerCase();
    if (!slug || reserved.has(slug) || slug.includes('.')) return null;
    return { slug, kind: 'menu' };
  }

  if (prefix === 'r') {
    const slug = segments[1]?.toLowerCase();
    if (!slug || reserved.has(slug) || slug.includes('.')) return null;
    const isLinks =
      segments.length >= 3 && segments[2].toLowerCase() === 'links';
    return { slug, kind: isLinks ? 'links' : 'menu' };
  }

  return null;
}

module.exports = {
  DEFAULT_FRONTEND_ORIGIN,
  DEFAULT_BACKEND_ORIGIN,
  SOCIAL_CRAWLER_PATTERN,
  escapeHtml,
  resolvePublicDescription,
  resolveOgDescription,
  resolveAbsoluteAssetUrl,
  buildRestaurantOgData,
  buildOgMenuHtml,
  isSocialCrawler,
  parseMenuSlugFromPath,
  parseRestaurantOgRequest,
};
