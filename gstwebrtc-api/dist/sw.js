const CACHE_NAME = 'gstglass-pwa-3.8-viewer-auth-57';
const SHELL_KEY = new URL('./index.html', self.registration.scope).href;
const APP_SHELL = [
  './index.html',
  './logout.js',
  './player.js',
  './player.css?v=3.8.30',
  './manifest.webmanifest?v=3.8.40',
  './icons/gstreamer-glass-192.png',
  './icons/gstreamer-glass-512.png',
  './icons/gstreamer-glass-maskable-192.png',
  './icons/gstreamer-glass-maskable-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys
        .filter((key) => key.startsWith('gstglass-pwa-') && key !== CACHE_NAME)
        .map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

function isRuntimeConfig(url) {
  return url.pathname.endsWith('/gstglass-config.js');
}

function isAuthenticationAction(url) {
  const path = url.pathname.replace(/\/+$/, '') || '/';
  // /auth is a permanently reserved gate namespace at the origin root (see
  // Glass's own IsAuthenticationEndpointPath) -- every child must bypass the
  // service worker, not just the specific login/logout routes this used to
  // enumerate. Bare /auth or /auth/ (no /login) is exactly what an installed
  // PWA can end up showing after being redirected there, and missing it here
  // was the actual bug: a service-worker fetch() follows Glass's redirect
  // (e.g. a still-valid session hitting /auth/) internally, so the *content*
  // ends up correct but the address bar -- and an installed PWA's own
  // last-known-URL, which is what gets restored on relaunch -- never moves
  // to /live/. Native network navigation is required so the address bar,
  // cookie mutation, and redirect all complete together.
  return path === '/auth' ||
    path.startsWith('/auth/') ||
    path.endsWith('/__gstglass/auth/login') ||
    path.endsWith('/__gstglass/auth/logout') ||
    path.endsWith('/logout');
}

async function networkFirst(request, fallbackKey) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetch(request, { cache: 'no-cache' });
    // Never cache an authentication redirect/login response under the app
    // shell URL. Only a successful same-URL protected asset may be retained.
    if (response && response.ok && !response.redirected && response.url === request.url) {
      await cache.put(fallbackKey || request, response.clone());
    }
    return response;
  } catch (err) {
    const cached = await cache.match(fallbackKey || request, { ignoreSearch: false });
    if (cached) return cached;
    throw err;
  }
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Do not wrap /auth/* navigations in respondWith(fetch(...)) -- see
  // isAuthenticationAction's comment.
  if (isAuthenticationAction(url)) return;

  // This file is generated from the current Glass settings and may change
  // every second. Never put it in Cache Storage, including on reload probes.
  if (isRuntimeConfig(url)) {
    event.respondWith(fetch(request, { cache: 'no-store' }));
    return;
  }

  // player.js is timestamped to defeat intermediary caches. Store/fall back to
  // one canonical copy so the installed shell can still open without a network.
  if (url.pathname.endsWith('/player.js') && url.searchParams.has('t')) {
    const playerKey = new URL('./player.js', self.registration.scope).href;
    event.respondWith(networkFirst(request, playerKey));
    return;
  }

  // Avoid filling Cache Storage with other timestamped diagnostic probes.
  if (url.searchParams.has('t') || url.searchParams.has('reload')) {
    event.respondWith(fetch(request, { cache: 'no-store' }));
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, SHELL_KEY));
    return;
  }

  event.respondWith(networkFirst(request));
});
