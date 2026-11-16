const CACHE_NAME = 'almenupro-pos-v5';
const PRECACHE_URLS = [
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

  // HTML navigations: always network first; never substitute cached "/" for /admin paths.
  if (request.mode === 'navigate' || request.headers.get('accept')?.includes('text/html')) {
    event.respondWith(
      fetch(request, { cache: 'no-store', redirect: 'follow' })
        .then((response) => {
          if (response.ok && !response.redirected && response.url === request.url) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(async () => {
          const cached = await caches.match(request);
          if (cached) return cached;
          const shell = await caches.match('/index.html');
          if (shell) return shell;
          return Response.error();
        }),
    );
    return;
  }

  if (!isStaticAsset(url.pathname)) return;

  // Executable assets must be network-first. Serving a cached debug
  // main.dart.js beside a newer release bootstrap leaves Flutter blank.
  if (
    url.pathname.endsWith('.js') ||
    url.pathname.endsWith('.wasm') ||
    url.pathname.endsWith('.css')
  ) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response && response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => caches.match(request)),
    );
    return;
  }

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
