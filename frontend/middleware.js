const SOCIAL_CRAWLER_PATTERN =
  /bot|crawl|spider|slurp|facebook|whatsapp|facebot|twitter|linkedin|telegram|slack|discord|preview|embed|meta-externalagent/i;

const DEFAULT_BACKEND_ORIGIN = 'https://backend-henna-chi-76.vercel.app';

export const config = {
  matcher: ['/menu/:path*', '/restaurant/:path*', '/r/:path*', '/:slug'],
};

function isSocialCrawler(userAgent) {
  return SOCIAL_CRAWLER_PATTERN.test(String(userAgent || ''));
}

function parseRestaurantOgRequest(pathname) {
  const path = String(pathname || '').replace(/\/+$/, '') || '/';
  const segments = path.split('/').filter(Boolean);
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

export default async function middleware(request) {
  const passThrough = () =>
    new Response(null, {
      headers: { 'x-middleware-next': '1' },
    });

  try {
    const url = new URL(request.url);
    const userAgent = request.headers.get('user-agent') || '';
    if (!isSocialCrawler(userAgent)) {
      return passThrough();
    }

    const parsed = parseRestaurantOgRequest(url.pathname);
    if (!parsed?.slug) {
      return passThrough();
    }

    const backendOrigin = (
      process.env.BACKEND_ORIGIN || DEFAULT_BACKEND_ORIGIN
    ).replace(/\/+$/, '');
    const ogPath =
      parsed.kind === 'links'
        ? `/og/r/${encodeURIComponent(parsed.slug)}/links`
        : `/og/menu/${encodeURIComponent(parsed.slug)}`;
    const ogEndpoint = `${backendOrigin}${ogPath}?site=${encodeURIComponent(url.origin)}`;

    const response = await fetch(ogEndpoint, {
      headers: { Accept: 'text/html' },
    });
    if (!response.ok) {
      return passThrough();
    }

    const html = await response.text();
    return new Response(html, {
      status: 200,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'public, max-age=300',
      },
    });
  } catch (error) {
    console.error('[og-middleware]', error);
    return passThrough();
  }
}
