const CACHE_NAME = 'gstglass-pwa-3.7.52f45';
const SHELL_KEY = new URL('./index.html', self.registration.scope).href;
const APP_SHELL = [
  './index.html',
  './player.js',
  './player.css?v=3.7.52f45-honest-video-sender-queue',
  './manifest.webmanifest?v=3.7.52f45-honest-video-sender-queue',
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

async function networkFirst(request, fallbackKey) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetch(request, { cache: 'no-cache' });
    if (response && response.ok) await cache.put(fallbackKey || request, response.clone());
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
