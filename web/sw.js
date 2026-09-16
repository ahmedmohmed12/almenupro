const CACHE_NAME = 'almenupro-pos-v2';
const PRECACHE_URLS = [
  '/',
  '/admin',
  '/index.html',
  '/manifest.json',
  '/favicon.png',
  '/flutter.js',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/Icon-maskable-192.png',
  '/icons/Icon-maskable-512.png',
];

function isStaticAsset(pathname) {
  if (
    pathname === '/' ||
    pathname === '/admin' ||
    pathname === '/index.html' ||
    pathname === '/manifest.json' ||
    pathname === '/favicon.png' ||
    pathname === '/flutter.js' ||
    pathname === '/flutter_bootstrap.js' ||
    pathname === '/main.dart.js' ||
    pathname === '/version.json'
  ) {
    return true;
  }
  return (
    pathname.startsWith('/assets/') ||
    pathname.startsWith('/canvaskit/') ||
    pathname.startsWith('/icons/') ||
    pathname.startsWith('/fonts/') ||
    pathname.endsWith('.wasm') ||
    pathname.endsWith('.otf') ||
    pathname.endsWith('.ttf') ||
    pathname.endsWith('.woff') ||
    pathname.endsWith('.woff2') ||
    pathname.endsWith('.png') ||
    pathname.endsWith('.jpg') ||
    pathname.endsWith('.jpeg') ||
    pathname.endsWith('.webp') ||
    pathname.endsWith('.svg') ||
    pathname.endsWith('.json') ||
    pathname.endsWith('.js') ||
    pathname.endsWith('.css')
  );
}

function shouldBypass(pathname) {
  return (
    pathname.startsWith('/api') ||
    pathname.endsWith('/sw.js') ||
    pathname.includes('flutter_service_worker') ||
    pathname.startsWith('/og/')
  );
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) =>
        Promise.all(
          PRECACHE_URLS.map((url) =>
            cache.add(url).catch(() => undefined),
          ),
        ),
      )
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_NAME)
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  let url;
  try {
    url = new URL(request.url);
  } catch (_) {
    return;
  }
  if (url.origin !== self.location.origin) return;
  if (shouldBypass(url.pathname)) return;

  // HTML navigations: network first, cache fallback for offline POS boot.
  if (request.mode === 'navigate' || request.headers.get('accept')?.includes('text/html')) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(async () => {
          const cached =
            (await caches.match(request)) ||
            (await caches.match('/index.html')) ||
            (await caches.match('/'));
          if (cached) return cached;
          return Response.error();
        }),
    );
    return;
  }

  if (!isStaticAsset(url.pathname)) return;

  // Static cashier assets: cache-first for instant POS loads.
  event.respondWith(
    caches.match(request).then((cached) => {
      const networkFetch = fetch(request)
        .then((response) => {
          if (response && response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => cached);
      return cached || networkFetch;
    }),
  );
});
