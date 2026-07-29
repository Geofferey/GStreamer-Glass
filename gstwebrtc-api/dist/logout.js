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

  window.GST_GLASS_LOGOUT = () => {
    const requestUrl = new URL(logoutEndpoint);
    requestUrl.searchParams.set('t', Date.now().toString());
    location.replace(requestUrl.href);
  };
})();
