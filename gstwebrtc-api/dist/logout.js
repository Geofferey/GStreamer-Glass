(() => {
  const scriptUrl = document.currentScript && document.currentScript.src
    ? document.currentScript.src
    : new URL('./logout.js', document.baseURI).href;
  const endpoint = new URL(scriptUrl);
  endpoint.search = '';
  endpoint.hash = '';
  // Authentication is a permanent origin-level gate, independent of the
  // viewer mount. Keeping the action at /auth/ prevents /live/ assets,
  // service workers, and static routing from ever shadowing it.
  const logoutEndpoint = new URL('/auth/logout', endpoint);

  // Warm the connection to this origin as soon as the page loads, well
  // before any click on Sign out -- the TLS edge redirects /auth/logout
  // straight to /auth/login?return=..., and reusing an already-open
  // connection for that whole chain avoids paying TLS-handshake latency at
  // the exact moment the user is waiting for something to happen.
  try {
    const preconnect = document.createElement('link');
    preconnect.rel = 'preconnect';
    preconnect.href = endpoint.origin;
    document.head.appendChild(preconnect);
  } catch (_) {}

  // A cached, previously-authenticated page can survive a PWA close even
  // though the server-side session is gone -- Chrome does not clear a
  // service worker's CacheStorage (or the underlying script that runs, if
  // it's an old cached copy of player.js itself) just because the app was
  // closed. Explicit logout is the one moment client-side JS is definitely
  // still running fresh, so it's the most reliable place to tear that state
  // down proactively -- waiting for the NEXT load's own cleanup logic to
  // run doesn't help if that next load is itself served from the very
  // cache being cleaned up. Awaited before navigating: firing the redirect
  // first can abort this cleanup mid-flight.
  async function clearCachedPwaState() {
    try {
      if ('serviceWorker' in navigator) {
        const registrations = await navigator.serviceWorker.getRegistrations();
        await Promise.all(registrations
          .filter((registration) => registration.scope.startsWith(endpoint.origin))
          .map((registration) => registration.unregister()));
      }
    } catch (_) {}
    try {
      if ('caches' in window) {
        const cacheNames = await caches.keys();
        await Promise.all(cacheNames
          .filter((name) => name.startsWith('gstglass-pwa-'))
          .map((name) => caches.delete(name)));
      }
    } catch (_) {}
  }

  window.GST_GLASS_LOGOUT = () => {
    const requestUrl = new URL(logoutEndpoint);
    requestUrl.searchParams.set('t', Date.now().toString());
    clearCachedPwaState().finally(() => location.replace(requestUrl.href));
  };
})();
