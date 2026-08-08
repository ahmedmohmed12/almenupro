const DEFAULT_FRONTEND_ORIGIN = 'https://almenupro-frontend-three.vercel.app';
const DEFAULT_BACKEND_ORIGIN = 'https://almenupro-backend.vercel.app';

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

function resolvePublicDescription(restaurant) {
  const description = String(
    restaurant.description ??
      restaurant.description_ar ??
      restaurant.descriptionAr ??
      '',
  ).trim();
  if (description) return description;
  return `منيو مطعم ${restaurant.name} لطلب الوجبات أونلاين`;
}

function resolveOgDescription(restaurant) {
  const description = String(
    restaurant.description ??
      restaurant.description_ar ??
      restaurant.descriptionAr ??
      '',
  ).trim();
  if (description) return description;
  return `اطلب الآن من منيو ${restaurant.name}`;
}

function resolveAbsoluteAssetUrl(raw, backendOrigin, frontendOrigin) {
  const fallback = `${frontendOrigin}/icons/Icon-512.png`;
  const value = String(raw || '').trim();
  if (!value) return fallback;

  if (value.startsWith('http://') || value.startsWith('https://')) {
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
  const menuPath = options.menuPath || `/menu/${slug}`;
  const canonicalUrl = `${siteOrigin}${menuPath.startsWith('/') ? menuPath : `/${menuPath}`}`;
  const name = String(restaurant.name || slug || 'Restaurant').trim();
  const title = `${name} — المنيو الإلكتروني`;
  const description = resolvePublicDescription(restaurant);
  const ogDescription = resolveOgDescription(restaurant);
  const logoRaw =
    restaurant.logoUrl ||
    restaurant.logo_url ||
    pickFirstMenuItemImage(options.menuItems);
  const logoUrl = resolveAbsoluteAssetUrl(logoRaw, backendOrigin, frontendOrigin);

  return {
    slug,
    name,
    title,
    description,
    ogDescription,
    canonicalUrl,
    logoUrl,
    twitterDescription: description,
  };
}

function buildOgMenuHtml(ogData) {
  const title = escapeHtml(ogData.title);
  const name = escapeHtml(ogData.name);
  const description = escapeHtml(ogData.description);
  const ogDescription = escapeHtml(ogData.ogDescription);
  const canonicalUrl = escapeHtml(ogData.canonicalUrl);
  const logoUrl = escapeHtml(ogData.logoUrl);
  const twitterDescription = escapeHtml(ogData.twitterDescription);

  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <meta name="description" content="${description}">

  <meta property="og:url" content="${canonicalUrl}">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${name}">
  <meta property="og:description" content="${ogDescription}">
  <meta property="og:image" content="${logoUrl}">
  <meta property="og:image:width" content="300">
  <meta property="og:image:height" content="300">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${name}">
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
  const path = String(pathname || '').replace(/\/+$/, '') || '/';
  const segments = path.split('/').filter(Boolean);
  if (segments.length === 0) return null;

  if (segments.length === 1) {
    const slug = segments[0].toLowerCase();
    if (['admin', 'legacy-menu', 'menu', 'restaurant', 'api', 'og'].includes(slug)) {
      return null;
    }
    return slug;
  }

  if (segments.length >= 2) {
    const prefix = segments[0].toLowerCase();
    if (prefix === 'menu' || prefix === 'restaurant') {
      return segments[1].toLowerCase();
    }
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
};
