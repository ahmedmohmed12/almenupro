const SOCIAL_CRAWLER_PATTERN =
  /bot|crawl|spider|slurp|facebook|whatsapp|facebot|twitter|linkedin|telegram|slack|discord|preview|embed|meta-externalagent/i;

const DEFAULT_BACKEND_ORIGIN = 'https://almenupro-backend.vercel.app';

export const config = {
  matcher: ['/menu/:path*', '/restaurant/:path*', '/:slug'],
};

function isSocialCrawler(userAgent) {
  return SOCIAL_CRAWLER_PATTERN.test(String(userAgent || ''));
}

function parseMenuSlugFromPath(pathname) {
  const path = String(pathname || '').replace(/\/+$/, '') || '/';
  const segments = path.split('/').filter(Boolean);
  if (segments.length === 0) return null;

  if (segments.length === 1) {
    const slug = segments[0].toLowerCase();
    if (
      ['admin', 'legacy-menu', 'menu', 'restaurant', 'api', 'og'].includes(slug) ||
      slug.includes('.')
    ) {
      return null;
    }
    return slug;
  }

  if (segments.length >= 2) {
    const prefix = segments[0].toLowerCase();
    if (prefix === 'menu' || prefix === 'restaurant') {
      const slug = segments[1].toLowerCase();
      return slug.includes('.') ? null : slug;
    }
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

    const slug = parseMenuSlugFromPath(url.pathname);
    if (!slug) {
      return passThrough();
    }

    const backendOrigin = (
      process.env.BACKEND_ORIGIN || DEFAULT_BACKEND_ORIGIN
    ).replace(/\/+$/, '');
    const ogEndpoint = `${backendOrigin}/og/menu/${encodeURIComponent(slug)}?site=${encodeURIComponent(url.origin)}`;

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
