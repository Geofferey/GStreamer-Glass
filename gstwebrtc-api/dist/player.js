(() => {
  const FRONTEND_VERSION = '3.8-viewer-auth-40';
  console.info(`[GStreamer Glass Live] frontend ${FRONTEND_VERSION}`);
  const playerRoot = document.getElementById('playerRoot');
  const video = document.getElementById('video');
  const overlay = document.getElementById('overlay');
  const statusEl = document.getElementById('status');
  const detailEl = document.getElementById('detail');
  const fullscreenButton = document.getElementById('fullscreenButton');
  const statsOverlay = document.getElementById('statsOverlay');
  const audio = document.getElementById('audio') || (() => {
    const el = document.createElement('audio');
    el.id = 'audio';
    el.autoplay = true;
    el.controls = false;
    el.style.display = 'none';
    (playerRoot || document.body).appendChild(el);
    return el;
  })();

  // Chromium on Android promotes a fullscreen <video> into its native media
  // surface. That surface can queue frames after WebRTC's reported jitter
  // buffer, creating visible latency while receiver statistics stay nominal.
  // Firefox Android and desktop browsers keep their established behavior.
  const userAgent = navigator.userAgent || '';
  const androidContainerFullscreen = /Android/i.test(userAgent) && !/Firefox/i.test(userAgent);
  if (androidContainerFullscreen) {
    // Keep Chrome's native controls but remove their direct video-fullscreen
    // escape hatch when the token is supported. Our button enters DOM/container
    // fullscreen and therefore keeps video on the normal compositor path.
    try { video.controlsList.add('nofullscreen'); } catch (_) {
      video.setAttribute('controlsList', 'nofullscreen');
    }
  }

  // Keep the WebRTC track on the browser's native <video> compositor path.
  // That is the path browsers can hardware-decode. There is no standards-based
  // switch that can force a hardware decoder for an RTCPeerConnection, so avoid
  // canvas/WebCodecs copies and provide the strongest applicable media hints.
  video.autoplay = true;
  video.playsInline = true;
  video.muted = true;
  video.preload = 'auto';
  video.setAttribute('playsinline', '');
  video.setAttribute('webkit-playsinline', '');
  try { video.disableRemotePlayback = true; } catch (_) {}

  const state = {
    ws: null,
    peerId: null,
    ready: false,
    pc: null,
    sessionId: null,
    remotePeerId: null,
    pendingIce: [],
    pendingRemoteIce: [],
    producers: new Map(),
    started: false,
    reconnectTimer: null,
    reconnectAttempts: 0,
    intentionalStopMarker: false,
    streamStateKnown: false,
    streamStateRequestToken: 0,
    streamTransitionToken: null,
    authRevokedToken: null,
    restartPending: false,
    manualResumeRequired: false,
    stopResumeLocked: false,
    proxyPairRetryCount: 0,
    proxyPairRetrying: false,
    proxyPairLocalTicks: 0,
    ownPublicIp: '',
    keepAliveTimer: null,
    keepAliveCount: 0,
    lastKeepAliveAt: 0,
    signalingAttemptToken: 0,
    connectionModeOverride: '',
    signalingRoute: 'proxy',
    signalingUrl: '',
    signalingCandidates: [],
    screenWakeLock: null,
    screenWakeLockPending: false,
    screenWakeLockStatus: 'idle',
    screenWakeLockLastError: '',
    screenWakeLockRetryCount: 0,
    screenWakeLockRetryTimer: null,
    statsTimer: null,
    lastIceProtocol: '',
    fullscreenAutoTried: false,
    fullscreenRenderRecoveryToken: 0,
    fullscreenRenderRecoveryTimer: null,
    fullscreenRenderRecoveryCount: 0,
    lastPresentedVideoAt: 0,
    lastUserGestureAt: 0,
    receivers: new Set(),
    currentJitterMs: 0,
    currentJitterMsByKind: { audio: null, video: null },
    latestJbufStatsByKind: { audio: null, video: null },
    adaptiveStableTicks: 0,
    lastInboundVideo: null,
    lastStatsVideo: null,
    lastJbufStats: null,
    lastInboundAudio: null,
    lastJbufStatsByKind: { audio: null, video: null },
    jitterApplyTimer: null,
    jbufHighTicks: 0,
    jbufHighTicksByKind: { audio: 0, video: 0 },
    jbufReconnectPending: false,
    jbufWatchdogWarmupUntil: 0,
    jbufWatchdogWarmupReason: '',
    configReloadTimer: null,
    lastConfigSignature: '',
    videoStream: null,
    audioStream: null,
    activeRenderMode: '',
    mediaPlayAttempt: { video: 0, audio: 0 },
    inboundBitrateSamples: new Map(),
    liveEdgeEstimateMs: NaN,
    liveEdgeInstantMs: NaN,
    liveEdgeSamples: [],
    liveEdgeState: 'unknown',
    liveEdgeFaultActive: false,
    lastCompactStatus: '',
    videoZoom: { scale: 1, x: 0, y: 0, pointers: new Map(), pinchStart: null, panStart: null, gestureMoved: false, suppressTapUntil: 0 },
    splitAudio: { ws: null, pc: null, sessionId: null, peerId: null, remotePeerId: null, pendingIce: [], pendingRemoteIce: [], producers: new Map(), ready: false, url: '', route: '', candidates: [], attemptToken: 0, status: 'idle', reconnectTimer: null, reconnectAttempts: 0, proxyPairRetryCount: 0, proxyPairRetrying: false, proxyPairLocalTicks: 0, lastRouteLine: '', connectTimer: null, keepAliveTimer: null, keepAliveCount: 0, lastKeepAliveAt: 0, lastError: '', lastTrackKind: '', lastInboundStats: null, lastHealthyAt: 0, lastRecoverAt: 0, recoveryCount: 0, stallTicks: 0, offsetHighTicks: 0, lastAvOffsetMs: NaN, syncHealth: 'free-run', connectStartedAt: 0, trackReceivedAt: 0, warmupUntil: 0, avOffsetBaselineMs: NaN, avOffsetBaselineSamples: 0, avOffsetBaselineLocked: false, avOffsetDeltaMs: NaN, avOffsetBaselineReason: 'none' },
    controller: { userPaused: false, userMuted: false, volume: 1, uiPinned: false, initialized: false, installPrompt: null, bar: null, playButton: null, muteButton: null, volumeInput: null, spacer: null, reconnectButton: null, routeButton: null, logoutButton: null, installButton: null, zoomButton: null, pinButton: null, fullscreenButton: null, status: null, lastAppliedAt: 0 }
  };

  function isStandalonePwa() {
    return !!(window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
  }

  function registerPwaServiceWorker() {
    if (!('serviceWorker' in navigator) || !window.isSecureContext) return;
    if (viewerAuthenticationEnabled()) {
      window.addEventListener('load', () => {
        const cleanupReloadKey = 'gstglass-auth-worker-cleanup';
        const controlledByRetiredWorker =
          !!navigator.serviceWorker.controller &&
          sessionStorage.getItem(cleanupReloadKey) !== 'complete';
        Promise.all([
          navigator.serviceWorker.getRegistrations()
            .then((registrations) => Promise.all(registrations
              .filter((registration) => registration.scope.startsWith(new URL('./', location.href).href))
              .map((registration) => registration.unregister()))),
          ('caches' in window
            ? caches.keys().then((keys) => Promise.all(keys
              .filter((key) => key.startsWith('gstglass-pwa-'))
              .map((key) => caches.delete(key))))
            : Promise.resolve())
        ]).then(() => {
          // unregister() does not release an already-controlled page. Without
          // one clean reload, that retired worker can consume the first
          // post-login auth/logout navigation and hide the TLS edge's 303.
          if (controlledByRetiredWorker) {
            sessionStorage.setItem(cleanupReloadKey, 'complete');
            location.reload();
            return;
          }
          sessionStorage.removeItem(cleanupReloadKey);
        }).catch((err) => log('authenticated viewer cache cleanup failed', err && err.message ? err.message : err));
      }, { once: true });
      return;
    }
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('./sw.js', { scope: './', updateViaCache: 'none' })
        .then((registration) => registration.update())
        .catch((err) => log('PWA service worker registration failed', err && err.message ? err.message : err));
    }, { once: true });
  }

  function query(name) {
    try { return new URLSearchParams(location.search).get(name); } catch (_) { return null; }
  }

  function configValue(name, fallback) {
    const cfg = window.GST_GLASS_CONFIG || {};
    return cfg[name] !== undefined && cfg[name] !== null ? cfg[name] : fallback;
  }

  function configSignature(cfg) {
    try {
      return JSON.stringify(cfg || {});
    } catch (_) {
      return String(Date.now());
    }
  }

  function parseConfigScript(text) {
    const eq = text.indexOf('=');
    const start = text.indexOf('{', eq >= 0 ? eq : 0);
    const end = text.lastIndexOf('}');
    if (start < 0 || end <= start) throw new Error('Could not find JSON object in gstglass-config.js');
    return JSON.parse(text.slice(start, end + 1));
  }

  async function reloadRuntimeConfig(reason = 'poll') {
    try {
      const res = await fetch(`./gstglass-config.js?reload=${Date.now()}`, { cache: 'no-store' });
      if (!res.ok) return false;
      const cfg = parseConfigScript(await res.text());
      const sig = configSignature(cfg);
      if (sig === state.lastConfigSignature) return false;
      const previousGrouping = mediaStreamGroupingSignature();
      const previousIceMapping = mappedIceHostSignature();
      state.lastConfigSignature = sig;
      window.GST_GLASS_CONFIG = cfg;
      const nextGrouping = mediaStreamGroupingSignature();
      const nextIceMapping = mappedIceHostSignature();
      if (jbufDebugEnabled()) log('config reloaded', reason, playerConfigLine(), cfg);
      applyAllReceiverJitter('config reload', true);
      refreshRenderedTracks('config reload');
      reconcileSplitAudio('config reload');
      updatePlayerControls();
      applyLogicalMediaState('config reload');
      const activeIceMappingChanged = previousIceMapping !== nextIceMapping && connectionMode() === 'proxy';
      if ((previousGrouping !== nextGrouping || activeIceMappingChanged) && state.pc) {
        log('Connection-affecting player config changed; restarting WebRTC session',
          previousGrouping, '→', nextGrouping, previousIceMapping, '→', nextIceMapping);
        restartConnectionForMode(activeIceMappingChanged ? 'mapped-ice-host-change' : 'mediastream-grouping-change');
      }
      return true;
    } catch (err) {
      if (jbufDebugEnabled()) log('config reload failed', err);
      return false;
    }
  }

  function signalingAllowedByStreamState() {
    return state.streamStateKnown &&
      !state.intentionalStopMarker &&
      !state.manualResumeRequired;
  }

  function stopSignaling(reason = 'stream-state') {
    const active = !!(
      state.ws ||
      state.pc ||
      state.reconnectTimer ||
      state.splitAudio.ws ||
      state.splitAudio.pc ||
      state.splitAudio.reconnectTimer
    );
    clearTimeout(state.reconnectTimer);
    state.reconnectTimer = null;
    if (!active) return;
    state.signalingAttemptToken += 1;
    const socket = state.ws;
    state.ws = null;
    state.ready = false;
    stopKeepAlive();
    stopSession(false, { stopSplitAudio: true, reason });
    try { if (socket) socket.close(1000, reason); } catch (_) {}
  }

  function finishRestart() {
    state.restartPending = false;
    if (state.stopResumeLocked) {
      state.manualResumeRequired = true;
      stopSignaling('manual-resume-required');
      setStatus('Available', 'Press Play to connect.', 'good');
      return;
    }
    state.manualResumeRequired = false;
    state.reconnectAttempts = 0;
    connect();
  }

  // Authentication is a permanent origin-level gate, independent of the
  // viewer mount (see logout.js) -- /auth/login always lives at the
  // origin root, never relative to wherever this page happens to be
  // served from. Mirrors logout.js's own redirect construction.
  function redirectToLogin() {
    const loginUrl = new URL('/auth/login', window.location.href);
    loginUrl.searchParams.set('return', window.location.pathname + window.location.search);
    location.replace(loginUrl.href);
  }

  // Dedicated auth session heartbeat. reloadRuntimeConfig/fetchStreamStopMarker
  // only ever notice a revoked session as a side effect of some other fetch
  // happening to get redirected -- this instead polls the auth mechanism
  // itself, directly, on its own schedule. /auth/status is always answered
  // locally by the TLS/plaintext-auth proxy (see its comment on the C# side),
  // regardless of whether GST/webrtcsink is even running, so this keeps
  // working through a stream stop/restart exactly when it matters most.
  // Absolute origin-relative URL, same reasoning as redirectToLogin() --
  // /auth/* is a permanent origin-level gate, never relative to this page's
  // own mount path.
  async function checkAuthStatus() {
    try {
      const statusUrl = new URL('/auth/status', window.location.href);
      const res = await fetch(`${statusUrl.pathname}?reload=${Date.now()}`, { cache: 'no-store' });
      if (res.redirected && res.url && !res.url.includes('/auth/status')) {
        location.replace(res.url);
        return;
      }
      if (!res.ok) return;
      const data = await res.json();
      if (data && data.authenticated === false) {
        redirectToLogin();
      }
    } catch (_) {
      // Best-effort heartbeat -- a transient network hiccup here must never
      // itself trigger a redirect; a genuinely dead server is already
      // handled by fetchStreamStopMarker's own error path.
    }
  }

  async function fetchStreamStopMarker() {
    const requestToken = ++state.streamStateRequestToken;
    const abortController = typeof AbortController === 'function' ? new AbortController() : null;
    const abortTimer = abortController ? setTimeout(() => abortController.abort(), 750) : null;
    try {
      const res = await fetch(`./gstglass-stream-state.json?reload=${Date.now()}`, {
        cache: 'no-store',
        ...(abortController ? { signal: abortController.signal } : {})
      });
      if (abortTimer) clearTimeout(abortTimer);
      if (requestToken !== state.streamStateRequestToken) return;

      // This request is auth-gated exactly like the live page itself, and
      // that check happens entirely INSIDE the TLS/plaintext-auth proxy,
      // before it ever tries to reach GST -- so it applies whether GST is
      // up or not (mid-restart included). If the session was revoked
      // (explicitly, or a restart regenerated the session-signing key),
      // the proxy has already redirected this fetch to the login page by
      // the time control reaches here. fetch() follows that redirect on
      // its own and would otherwise just hand back the login page's HTML
      // as "content" for what was expected to be JSON -- res.redirected
      // and res.url expose where it actually landed, so a real navigation
      // can happen instead of a silent, invisible swap.
      if (res.redirected && res.url && !res.url.includes('gstglass-stream-state.json')) {
        location.replace(res.url);
        return;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      const transition = String(data.transition || '');
      const transitionToken = String(data.transitionToken || '');
      const transitionChanged = state.streamTransitionToken !== null &&
        !!transitionToken &&
        transitionToken !== state.streamTransitionToken;
      state.streamTransitionToken = transitionToken;

      // Viewer sessions are about to be revoked (stream end/restart with
      // "Keep auth on restarts" unchecked) -- written to this file BEFORE
      // the server actually revokes anything, specifically so this fetch
      // still succeeds normally and this redirect still lands on a live,
      // responding server. Checked -- and acted on -- before anything
      // else below, since there is no point reconciling stream/restart
      // state for a session that is about to stop being valid anyway.
      const authRevokedToken = String(data.authRevokedToken || '');
      const authRevoked = state.authRevokedToken !== null &&
        !!authRevokedToken &&
        authRevokedToken !== state.authRevokedToken;
      state.authRevokedToken = authRevokedToken;
      if (authRevoked) {
        redirectToLogin();
        return;
      }

      state.streamStateKnown = true;
      state.intentionalStopMarker = !!data.intentionalStop;

      if (data.restarting) {
        state.restartPending = true;
        state.manualResumeRequired = state.stopResumeLocked;
        stopSignaling('restarting');
        setStatus('Restarting', 'Waiting for the stream to return.', 'warn');
      } else if (state.intentionalStopMarker) {
        state.restartPending = false;
        state.manualResumeRequired = true;
        state.stopResumeLocked = true;
        stopSignaling('intentional-stop');
        setStatus('Stream stopped', 'The broadcaster intentionally stopped the stream.', 'warn');
      } else if (transitionChanged && transition === 'stop') {
        state.restartPending = false;
        state.manualResumeRequired = true;
        state.stopResumeLocked = true;
        stopSignaling('manual-resume-required');
        setStatus('Available', 'Press Play to connect.', 'good');
      } else if (transitionChanged && transition === 'restart') {
        finishRestart();
      } else if (state.restartPending) {
        finishRestart();
      } else if (state.manualResumeRequired) {
        stopSignaling('manual-resume-required');
        setStatus('Available', 'Press Play to connect.', 'good');
      } else if (!state.ws && !state.reconnectTimer) {
        state.reconnectAttempts = 0;
        connect();
      }
      updatePlayerControls();
    } catch (_) {
      if (abortTimer) clearTimeout(abortTimer);
      if (requestToken !== state.streamStateRequestToken) return;
      state.streamStateKnown = false;
      state.intentionalStopMarker = true;
      state.manualResumeRequired = state.stopResumeLocked;
      stopSignaling('state-unavailable');
      setStatus('Stream stopped', 'State file unavailable; waiting without signaling.', 'warn');
      updatePlayerControls();
    }
  }

  function startConfigReloadTimer() {
    state.lastConfigSignature = configSignature(window.GST_GLASS_CONFIG || {});
    if (state.configReloadTimer) clearInterval(state.configReloadTimer);
    state.configReloadTimer = setInterval(() => {
      reloadRuntimeConfig('poll');
      fetchStreamStopMarker();
      checkAuthStatus();
    }, 1000);
    setTimeout(() => reloadRuntimeConfig('startup'), 250);
    setTimeout(() => fetchStreamStopMarker(), 250);
    setTimeout(() => checkAuthStatus(), 250);
  }

  function stopConfigReloadTimer() {
    if (state.configReloadTimer) clearInterval(state.configReloadTimer);
    state.configReloadTimer = null;
  }

  function boolValue(value, fallback = false) {
    if (value === undefined || value === null || value === '') return fallback;
    if (typeof value === 'boolean') return value;
    const text = String(value).trim().toLowerCase();
    if (['1', 'true', 'yes', 'on', 'enabled'].includes(text)) return true;
    if (['0', 'false', 'no', 'off', 'disabled'].includes(text)) return false;
    return fallback;
  }

  function screenWakeLockEnabled() {
    const raw = query('wakeLock') || query('screenWakeLock') || query('keepAwake');
    if (raw !== null && raw !== undefined && raw !== '') return boolValue(raw, true);
    return boolValue(configValue('screenWakeLock', true), true);
  }

  function screenWakeLockWanted() {
    return screenWakeLockEnabled() &&
      document.visibilityState === 'visible' &&
      document.body.classList.contains('playing') &&
      !state.controller.userPaused &&
      !!video.srcObject;
  }

  function screenWakeLockLine() {
    const supported = !!(navigator.wakeLock && typeof navigator.wakeLock.request === 'function');
    const status = supported ? state.screenWakeLockStatus : 'unsupported';
    const error = state.screenWakeLockLastError ? ` (${state.screenWakeLockLastError})` : '';
    return `screen wake ${status}${error}`;
  }

  async function requestScreenWakeLock(reason = 'state') {
    if (!screenWakeLockWanted()) return false;
    if (!navigator.wakeLock || typeof navigator.wakeLock.request !== 'function') {
      state.screenWakeLockStatus = 'unsupported';
      return false;
    }
    if (state.screenWakeLock && !state.screenWakeLock.released) {
      state.screenWakeLockStatus = 'active';
      return true;
    }
    if (state.screenWakeLockPending) return false;

    state.screenWakeLockPending = true;
    state.screenWakeLockStatus = 'requesting';
    try {
      const sentinel = await navigator.wakeLock.request('screen');
      if (!screenWakeLockWanted()) {
        try { await sentinel.release(); } catch (_) {}
        state.screenWakeLockStatus = 'released';
        return false;
      }
      state.screenWakeLock = sentinel;
      state.screenWakeLockStatus = 'active';
      state.screenWakeLockLastError = '';
      sentinel.addEventListener('release', () => {
        if (state.screenWakeLock === sentinel) state.screenWakeLock = null;
        state.screenWakeLockStatus = 'released';
        if (jbufDebugEnabled()) log('screen wake lock released', reason);
        if (screenWakeLockWanted() && state.screenWakeLockRetryCount < 2) {
          state.screenWakeLockRetryCount += 1;
          if (state.screenWakeLockRetryTimer) clearTimeout(state.screenWakeLockRetryTimer);
          state.screenWakeLockRetryTimer = setTimeout(() => {
            state.screenWakeLockRetryTimer = null;
            requestScreenWakeLock('release-retry');
          }, 750);
        }
      }, { once: true });
      if (jbufDebugEnabled()) log('screen wake lock active', reason);
      return true;
    } catch (err) {
      state.screenWakeLock = null;
      state.screenWakeLockStatus = 'denied';
      state.screenWakeLockLastError = err && err.name ? err.name : (err && err.message ? err.message : String(err));
      log('screen wake lock request failed', reason, state.screenWakeLockLastError);
      return false;
    } finally {
      state.screenWakeLockPending = false;
    }
  }

  async function releaseScreenWakeLock(reason = 'state') {
    if (state.screenWakeLockRetryTimer) clearTimeout(state.screenWakeLockRetryTimer);
    state.screenWakeLockRetryTimer = null;
    const sentinel = state.screenWakeLock;
    state.screenWakeLock = null;
    state.screenWakeLockStatus = 'released';
    if (!sentinel || sentinel.released) return true;
    try {
      await sentinel.release();
      if (jbufDebugEnabled()) log('screen wake lock released by player', reason);
      return true;
    } catch (err) {
      state.screenWakeLockLastError = err && err.name ? err.name : String(err);
      return false;
    }
  }

  function syncScreenWakeLock(reason = 'state', resetRetry = false) {
    if (resetRetry) state.screenWakeLockRetryCount = 0;
    if (screenWakeLockWanted()) requestScreenWakeLock(reason);
    else releaseScreenWakeLock(reason);
  }

  function normalizeProxySignalPath(raw, kind, appendKind = true) {
    const fallbackBase = String(configValue('signalingProxyBasePath', '/live/GstSignal') || '/live/GstSignal').trim();
    let value = String(raw || fallbackBase).trim();
    if (!value) value = '/live/GstSignal';
    const suffix = String(kind || 'video').toLowerCase() === 'audio' ? 'voice' : 'video';
    const absoluteInput = /^wss?:\/\//i.test(value);
    let absolute = null;
    try {
      absolute = new URL(value, location.href);
      value = absolute.pathname;
    } catch (_) {}
    value = `/${value.replace(/^\/+|\/+$/g, '')}`;
    if (appendKind && !new RegExp(`/${suffix}$`, 'i').test(value)) value += `/${suffix}`;
    if (absoluteInput && absolute) {
      absolute.pathname = value;
      return trimWsUrl(absolute.toString());
    }
    return value;
  }

  function proxyWsUrl(kind = 'video') {
    const audio = String(kind || '').toLowerCase() === 'audio';
    const explicit = audio
      ? (query('proxyAudioWs') || query('audioProxyWs') || configValue('audioProxyWsUrl', ''))
      : (query('proxyWs') || query('proxySignal') || query('proxySignaling') || configValue('proxyWsUrl', ''));
    if (explicit) {
      const normalized = normalizeWsUrl(explicit) || explicit;
      try {
        const parsed = new URL(normalized, location.href);
        if (location.protocol === 'https:' && parsed.protocol === 'ws:') parsed.protocol = 'wss:';
        return trimWsUrl(parsed.toString());
      } catch (_) { return trimWsUrl(normalized); }
    }

    const queryPath = audio
      ? (query('proxyAudioPath') ?? query('audioProxyPath'))
      : (query('proxyVideoPath') ?? query('videoProxyPath'));
    const configuredPath = configValue(audio ? 'audioSignalingProxyPath' : 'videoSignalingProxyPath', undefined);
    const explicitPath = queryPath !== null ? queryPath : configuredPath;
    const hasExplicitPath = explicitPath !== undefined && explicitPath !== null;
    // A present-but-empty Player-tab value explicitly disables this preferred
    // proxy path, allowing the mapped/direct candidates below to lead.
    if (hasExplicitPath && !String(explicitPath).trim()) return '';
    const basePath = query('proxySignalBase') || query('signalProxyBase') || configValue('signalingProxyBasePath', '/live/GstSignal');
    const path = hasExplicitPath
      ? normalizeProxySignalPath(explicitPath, audio ? 'audio' : 'video', false)
      : normalizeProxySignalPath(basePath, audio ? 'audio' : 'video', true);
    if (/^wss?:\/\//i.test(path)) return path;
    const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
    return `${scheme}://${location.host}${path}`;
  }

  // Always builds a root WebSocket endpoint from the hostname/domain used to
  // open the player. This deliberately does not inherit /live/GstSignal/*
  // (or any other path) from an explicit/proxied signaling URL.
  function pageHostWsUrl(port) {
    if (!port) return '';
    const host = query('signalHost') || query('host') || (location.hostname && location.hostname !== '0.0.0.0' ? location.hostname : '127.0.0.1');
    const requestedScheme = query('signalScheme') || query('scheme') || '';
    const scheme = location.protocol === 'https:' ? 'wss' : (requestedScheme || 'ws');
    return `${scheme}://${formatWsHost(host)}:${port}`;
  }

  function pageHostVideoWsUrl() {
    const port = query('signalPort') || query('videoSignalingPort') || query('port') || String(configValue('videoSignalingPort', configValue('signalingPort', 8189)));
    return pageHostWsUrl(port);
  }

  function directVideoWsUrl() {
    const exact = query('ws') || query('signaling') || query('signal') || String(configValue('directSignalingWsUrl', '') || '');
    if (exact) {
      const normalized = normalizeWsUrl(exact) || exact;
      try {
        const parsed = new URL(normalized, location.href);
        if (location.protocol === 'https:' && parsed.protocol === 'ws:') {
          log('ignoring insecure direct signaling URL on HTTPS page', normalized);
          return '';
        }
        return trimWsUrl(parsed.toString());
      } catch (_) { return trimWsUrl(normalized); }
    }

    return pageHostVideoWsUrl();
  }

  function uniqueWsUrls(urls) {
    const seen = new Set();
    return urls.filter((url) => {
      const normalized = trimWsUrl(url);
      if (!normalized || seen.has(normalized)) return false;
      seen.add(normalized);
      return true;
    });
  }

  function viewerAuthenticationEnabled() {
    return boolValue(configValue('viewerAuthenticationEnabled', false), false);
  }

  // Authenticated viewer sessions are carried by a Secure, host-scoped
  // HttpOnly cookie. When authentication is enabled, never fall back to an
  // insecure or different-host signaling socket that cannot carry that
  // cookie and could bypass the TLS proxy's authorization check.
  function authenticatedSignalingCandidates(urls) {
    const candidates = uniqueWsUrls(urls);
    if (!viewerAuthenticationEnabled()) return candidates;
    if (location.protocol !== 'https:') return [];
    return candidates.filter((url) => {
      try {
        const parsed = new URL(url, location.href);
        return parsed.protocol === 'wss:' && parsed.hostname === location.hostname;
      } catch (_) {
        return false;
      }
    });
  }

  // Signalling can be UPnP-mapped to a different external (WAN-side) port
  // than the one gst-launch actually binds to internally (see
  // externalSignalingPort in gstglass-config.js). Build this from the page
  // hostname and a root path so a proxy URL can never leak
  // /live/GstSignal/video into the mapped direct endpoint.
  function externalVideoWsUrl() {
    const port = Number(query('externalSignalingPort') || configValue('externalSignalingPort', 0)) || 0;
    if (!port) return '';
    return pageHostWsUrl(port);
  }

  function primarySignalingCandidates() {
    const proxy = proxyWsUrl('video');
    const direct = directVideoWsUrl();
    const pageDirect = pageHostVideoWsUrl();
    const external = externalVideoWsUrl();
    const mode = connectionMode();
    // Connection mode controls the WebRTC ICE/media route, not how the
    // browser is allowed to reach the signaling server. PROXY mode keeps the
    // configured Player-tab path first, then falls back to root WebSockets on
    // the page's host/domain (mapped WAN port, then configured direct port).
    // Its WAN/public ICE policy remains unchanged.
    if (mode === 'proxy') return authenticatedSignalingCandidates([proxy, external, pageDirect, direct]);
    if (mode === 'lan') return authenticatedSignalingCandidates([proxy, direct, external]);
    return authenticatedSignalingCandidates([proxy, direct, external]);
  }

  function signalingRouteForUrl(url, kind = 'video') {
    const target = trimWsUrl(url);
    if (kind === 'audio' && sharedSignalingEnabled() && target === trimWsUrl(primaryWsUrlForSplit())) return state.signalingRoute || 'proxy';
    if (target && target === trimWsUrl(proxyWsUrl(kind))) return 'proxy';
    const direct = kind === 'audio' ? directSplitAudioWsUrl() : directVideoWsUrl();
    if (target && target === trimWsUrl(direct)) return 'direct';
    const pageDirect = kind === 'audio' ? pageHostSplitAudioWsUrl() : pageHostVideoWsUrl();
    if (target && target === trimWsUrl(pageDirect)) return 'direct';
    const external = kind === 'audio' ? externalSplitAudioWsUrl() : externalVideoWsUrl();
    if (target && external && target === trimWsUrl(external)) return 'external';
    return 'explicit';
  }

  function signalingConnectTimeoutMs() {
    const raw = query('signalTimeoutMs') || query('signalingConnectTimeoutMs') || configValue('signalingConnectTimeoutMs', 7000);
    const value = Number.parseInt(raw, 10);
    return Number.isFinite(value) ? Math.min(30000, Math.max(1000, value)) : 7000;
  }

  function defaultWs() {
    try {
      if (state.ws && state.ws.url) return state.ws.url;
    } catch (_) {}
    return primarySignalingCandidates()[0] || directVideoWsUrl() || proxyWsUrl('video');
  }

  function normalizeConnectionMode(value) {
    const mode = String(value || '').trim().toLowerCase();
    if (['lan', 'local', 'direct'].includes(mode)) return 'lan';
    if (['proxy', 'remote', 'relay'].includes(mode)) return 'proxy';
    return 'auto';
  }

  // Presentation-only label for the route switch. The internal/config/API
  // value remains "proxy" everywhere else for compatibility.
  function connectionModeControlLabel(mode = connectionMode()) {
    const normalized = normalizeConnectionMode(mode);
    return normalized === 'proxy' ? 'WAN' : normalized.toUpperCase();
  }

  function connectionMode() {
    if (state.connectionModeOverride) return normalizeConnectionMode(state.connectionModeOverride);
    const fromQuery = query('route') || query('mode') || query('connectionMode');
    if (fromQuery) return normalizeConnectionMode(fromQuery);
    try {
      const saved = localStorage.getItem('gstglass-connection-mode');
      if (saved) return normalizeConnectionMode(saved);
      // One-way migration from releases that stored the media mode under a
      // signaling-route key. Only migrate canonical media-mode values: an old
      // "direct" signaling transport must never silently select LAN ICE.
      const legacy = String(localStorage.getItem('gstglass-signaling-route') || '').trim().toLowerCase();
      if (['lan', 'auto', 'proxy'].includes(legacy)) {
        localStorage.setItem('gstglass-connection-mode', legacy);
        return legacy;
      }
    } catch (_) {}
    return normalizeConnectionMode(configValue('connectionMode', 'auto'));
  }

  function turnUrl() {
    return String(query('turn') || query('turnUrl') || configValue('turnUrl', '') || '').trim();
  }

  function mediaRoutePolicyLine() {
    const mode = connectionMode();
    if (mode === 'lan') return 'media LAN-priority ICE (no local STUN)';
    if (mode === 'proxy' && turnUrl()) return 'media TURN relay-only';
    if (mode === 'proxy') return 'media public ICE priority (srflx preferred over host)';
    return 'media automatic ICE';
  }

  function isPrivateIceAddress(address) {
    // Beyond classic RFC1918/link-local/ULA, also catch address ranges that
    // are real but never internet-routable to the far side -- an ICE
    // candidate sitting in one of these is exactly as unreachable externally
    // as a 10.x/192.168.x host candidate, it's just a different reservation:
    //   100.64.0.0/10  RFC 6598 Shared Address Space (carrier-grade NAT,
    //                  very common on cellular networks)
    //   192.0.0.0/24   IETF Protocol Assignments, incl. 464XLAT client-side
    //                  translation addresses (RFC 7335)
    const text = String(address || '').trim();
    // Browsers commonly hide local host addresses behind an mDNS name. It is
    // still a LAN-only address even though it does not resemble an RFC1918 IP.
    if (/\.local\.?$/i.test(text)) return true;
    if (/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|127\.|fc|fd|fe80:|::1$)/i.test(text)) return true;
    if (/^192\.0\.0\./.test(text)) return true;
    const cgnat = text.match(/^100\.(\d{1,3})\./);
    if (cgnat && Number(cgnat[1]) >= 64 && Number(cgnat[1]) <= 127) return true;
    return false;
  }

  function isValidIpv4Address(address) {
    const parts = String(address || '').trim().split('.');
    return parts.length === 4 && parts.every((part) => /^\d{1,3}$/.test(part) && Number(part) >= 0 && Number(part) <= 255);
  }

  function parseAdditionalIceHosts(value) {
    const values = Array.isArray(value) ? value : String(value || '').split(/[,;\s]+/);
    // Runtime config resolves DNS names on the Glass host. Requiring an IPv4
    // literal here also prevents query-string text from being spliced into a
    // candidate line and avoids inconsistent browser FQDN candidate support.
    const hosts = [];
    const seen = new Set();
    values.forEach((value) => {
      const host = String(value || '').trim();
      if (!isValidIpv4Address(host) || seen.has(host)) return;
      seen.add(host);
      hosts.push(host);
    });
    // Bound candidate growth and reserve enough standards-compliant priority
    // space beneath the ordered mapped-host band for normal ICE fallbacks.
    return hosts.slice(0, 32);
  }

  function additionalIceHosts() {
    const queryValue = query('additionalIceHosts');
    if (queryValue !== null) return parseAdditionalIceHosts(queryValue);
    const legacyQueryValue = query('additionalIceHost');
    if (legacyQueryValue !== null) return parseAdditionalIceHosts(legacyQueryValue);
    const oldestQueryValue = query('iceHost');
    if (oldestQueryValue !== null) return parseAdditionalIceHosts(oldestQueryValue);
    const configured = configValue('additionalIceHosts', undefined);
    if (configured !== undefined) return parseAdditionalIceHosts(configured);
    return parseAdditionalIceHosts(configValue('additionalIceHost', ''));
  }

  function additionalIceHost() {
    return additionalIceHosts()[0] || '';
  }

  function mappedRtpPortBound(name) {
    const queryValue = query(name);
    const value = Number.parseInt(queryValue !== null ? queryValue : configValue(name, 0), 10);
    return Number.isFinite(value) && value > 0 && value <= 65535 ? value : 0;
  }

  function mappedIceHostSignature() {
    return `${additionalIceHosts().join(',')}:${mappedRtpPortBound('minRtpPort')}-${mappedRtpPortBound('maxRtpPort')}`;
  }

  function mappedHostIcePriority(hostIndex, originalPriority) {
    const original = Number.parseInt(originalPriority, 10);
    const componentBits = Number.isFinite(original) ? original & 0xff : 1;
    // Reserve the standards-compliant top ICE-priority band for configured
    // mapped hosts, leaving a full local-preference byte between list entries.
    return Math.max(256 + componentBits, 2122317056 - (Math.max(0, hostIndex) * 256) + componentBits);
  }

  function rewriteCandidateForMappedHost(candidateLine, host = additionalIceHost(), hostIndex = 0) {
    const minPort = mappedRtpPortBound('minRtpPort');
    const maxPort = mappedRtpPortBound('maxRtpPort');
    if (!host || !minPort || !maxPort || maxPort < minPort) return '';

    const text = String(candidateLine || '');
    const hasAttributePrefix = /^a=/i.test(text);
    const raw = hasAttributePrefix ? text.slice(2) : text;
    if (!/^candidate:/i.test(raw)) return '';
    const parts = raw.trim().split(/\s+/);
    const typIndex = parts.findIndex((part) => String(part).toLowerCase() === 'typ');
    if (parts.length < 8 || typIndex < 0 || String(parts[typIndex + 1]).toLowerCase() !== 'host') return '';
    if (String(parts[2] || '').toLowerCase() !== 'udp') return '';
    const address = parts[4] || '';
    const port = Number.parseInt(parts[5], 10);
    if (!isPrivateIceAddress(address) || !Number.isFinite(port) || port < minPort || port > maxPort || address === host) return '';

    // The external and internal ports are deliberately identical. Only the
    // address changes; the candidate continues to describe the real socket
    // owned by webrtcsink/libnice behind the 1:1 forwarding rule.
    parts[4] = host;
    parts[3] = String(mappedHostIcePriority(hostIndex, parts[3]));
    return `${hasAttributePrefix ? 'a=' : ''}${parts.join(' ')}`;
  }

  function expandRemoteIceCandidates(candidate, scope = 'primary remote') {
    if (connectionMode() !== 'proxy') return [candidate];
    if (!candidate) return [candidate];
    const init = typeof candidate.toJSON === 'function' ? candidate.toJSON() : candidate;
    if (!init || typeof init !== 'object' || !init.candidate) return [candidate];
    const mappedCandidates = additionalIceHosts().map((host, index) => {
      const candidateLine = rewriteCandidateForMappedHost(init.candidate, host, index);
      return candidateLine && candidateLine !== init.candidate ? { ...init, candidate: candidateLine } : null;
    }).filter(Boolean);
    if (!mappedCandidates.length) return [init];
    if (jbufDebugEnabled()) log(`${scope} added ${mappedCandidates.length} ordered mapped ICE candidate(s): ${additionalIceHosts().join(', ')}`);
    return [...mappedCandidates, init];
  }

  function injectMappedIceCandidatesIntoDescription(description, scope = 'primary remote') {
    const hosts = additionalIceHosts();
    if (connectionMode() !== 'proxy' || !description || !description.sdp || !hosts.length) return description;
    let injected = 0;
    const lines = [];
    String(description.sdp).split(/\r?\n/).forEach((line) => {
      if (/^a=candidate:/i.test(line)) {
        hosts.forEach((host, index) => {
          const mapped = rewriteCandidateForMappedHost(line, host, index);
          if (mapped && mapped !== line) {
            lines.push(mapped);
            injected += 1;
          }
        });
      }
      lines.push(line);
    });
    if (!injected) return description;
    if (jbufDebugEnabled()) log(`${scope} injected ${injected} ordered mapped ICE candidate(s) for ${hosts.join(', ')}`);
    return { type: description.type, sdp: lines.join('\r\n') };
  }

  function routeIcePriority(type, originalPriority, address) {
    const mode = connectionMode();
    const candidateType = String(type || '').toLowerCase();
    const original = Number.parseInt(originalPriority, 10);
    const componentBits = Number.isFinite(original) ? original & 0xff : 1;
    // Candidate type alone cannot tell us whether a host path is local-only:
    // a producer may advertise a host candidate containing its public/WAN
    // address. Treat only private/mDNS (or address-less) host candidates as
    // LAN paths so PROXY keeps preferring genuinely external host candidates.
    const isPrivateHost = candidateType === 'host' && (!address || isPrivateIceAddress(address));
    const mappedHostIndex = candidateType === 'host' ? additionalIceHosts().indexOf(String(address || '')) : -1;
    // A prflx candidate discovered on a private address (common on
    // multi-homed machines/virtual adapters, where a connectivity check
    // arrives on a different local interface than the one a candidate was
    // advertised for) is just as much a local-only path as host -- it must
    // not rank anywhere near a genuine externally-reachable srflx candidate.
    const isPrivatePrflx = candidateType === 'prflx' && isPrivateIceAddress(address);
    if (mode === 'proxy') {
      // Every configured 1:1 host outranks every automatically gathered path.
      // The first fallback starts one full local-preference step below the
      // final mapped host, preserving normal relay > srflx > prflx > host
      // ordering only within the fallback band.
      if (mappedHostIndex >= 0) return mappedHostIcePriority(mappedHostIndex, original);
      const fallbackTop = 2122317056 - (additionalIceHosts().length * 256);
      if (candidateType === 'relay') return fallbackTop + componentBits;
      if (candidateType === 'srflx') return fallbackTop - 256 + componentBits;
      if (candidateType === 'prflx' && !isPrivatePrflx) return fallbackTop - 512 + componentBits;
      if (candidateType === 'host' && !isPrivateHost) {
        return fallbackTop - 768 + componentBits;
      }
      if (isPrivateHost || isPrivatePrflx) return 256 + componentBits;
    }
    if (mode === 'lan') {
      if (isPrivateHost || isPrivatePrflx) return 2130706176 + componentBits;
      if ((candidateType === 'host' && !isPrivateHost) || candidateType === 'srflx' || (candidateType === 'prflx' && !isPrivatePrflx) || candidateType === 'relay') return 256 + componentBits;
    }
    return Number.isFinite(original) ? original : originalPriority;
  }

  function rewriteIceCandidatePriority(candidateLine) {
    const text = String(candidateLine || '');
    if (connectionMode() === 'auto' || !text) return text;
    const hasAttributePrefix = /^a=/i.test(text);
    const raw = hasAttributePrefix ? text.slice(2) : text;
    if (!/^candidate:/i.test(raw)) return text;
    const parts = raw.trim().split(/\s+/);
    const typIndex = parts.findIndex((part) => String(part).toLowerCase() === 'typ');
    if (parts.length < 8 || typIndex < 0 || !parts[typIndex + 1]) return text;
    parts[3] = String(routeIcePriority(parts[typIndex + 1], parts[3], parts[4]));
    return `${hasAttributePrefix ? 'a=' : ''}${parts.join(' ')}`;
  }

  // In PROXY mode, our own private/mDNS host candidates are withheld while
  // public host, srflx, prflx, and relay candidates remain eligible.
  //
  // The remote side (scope containing "remote", i.e. what the *producer*
  // advertises to us) is different: rejecting its private-address candidates
  // outright, not just deprioritizing them, is what actually closes the
  // peer-reflexive-discovery loophole -- if our own ICE agent never learns a
  // private remote address exists, it never attempts a connectivity check
  // toward it, so the producer never sees an unexpected check to discover us
  // by. This only became safe to do once webrtcsink reliably gathers its own
  // srflx candidate (confirmed in testing after the STUN fix) -- rejecting the
  // producer's host candidate back when it had no srflx of its own at all
  // left zero usable remote candidates and broke every connection outright.
  // A configured 1:1 mapped host now supplies that public candidate when STUN
  // cannot discover the router's static forwarding rule.
  function applyIceRoutePolicyToCandidate(candidate, scope = 'primary') {
    if (!candidate || connectionMode() === 'auto') return candidate;
    const init = typeof candidate.toJSON === 'function' ? candidate.toJSON() : candidate;
    if (!init || typeof init !== 'object' || !init.candidate) return candidate;
    if (scope.includes('remote') && connectionMode() === 'proxy') {
      const raw = String(init.candidate).replace(/^a=/i, '').trim();
      const parts = raw.split(/\s+/);
      const address = parts[4] || '';
      if (isPrivateIceAddress(address)) {
        if (jbufDebugEnabled()) log(`${scope} rejected private remote ICE candidate (${address})`);
        return null;
      }
    }
    const rewritten = rewriteIceCandidatePriority(init.candidate);
    if (rewritten === init.candidate) return init;
    if (jbufDebugEnabled()) log(`${scope} applied ${connectionMode()} ICE candidate priority`);
    return { ...init, candidate: rewritten };
  }

  function isLocalOnlyHostIceCandidateLine(candidateLine) {
    const text = String(candidateLine || '');
    const raw = /^a=/i.test(text) ? text.slice(2) : text;
    if (!/^candidate:/i.test(raw)) return false;
    const parts = raw.trim().split(/\s+/);
    const typIndex = parts.findIndex((part) => String(part).toLowerCase() === 'typ');
    if (typIndex < 0 || !parts[typIndex + 1]) return false;
    if (String(parts[typIndex + 1]).toLowerCase() !== 'host') return false;
    const address = parts[4] || '';
    return !address || isPrivateIceAddress(address);
  }

  // Our own srflx candidate *is* our public IP as discovered via STUN -- no
  // separate lookup/dummy RTCPeerConnection/external "what's my IP" service
  // needed, it's already flowing through the normal candidate-gathering path.
  function noteOwnPublicIpFromCandidate(candidateLine) {
    const text = String(candidateLine || '');
    const raw = /^a=/i.test(text) ? text.slice(2) : text;
    if (!/^candidate:/i.test(raw)) return;
    const parts = raw.trim().split(/\s+/);
    const typIndex = parts.findIndex((part) => String(part).toLowerCase() === 'typ');
    if (typIndex < 0 || !parts[typIndex + 1]) return;
    if (String(parts[typIndex + 1]).toLowerCase() !== 'srflx') return;
    const address = parts[4] || '';
    if (!address || address === state.ownPublicIp) return;
    state.ownPublicIp = address;
    log(`own public IP (via srflx): ${address}`);
  }

  // isOutbound=true for our own local/answer SDP: withhold only what *we*
  // advertise about ourselves in PROXY mode (private/mDNS host only; a
  // public-address host candidate is an external path and remains eligible).
  // isOutbound=false for what we accept from the remote: reject any embedded
  // candidate whose address is private (address-based, not just type=host --
  // catches private-address prflx too), same reasoning as the trickled-ICE
  // path in applyIceRoutePolicyToCandidate above. Most producers trickle
  // candidates separately rather than embedding them in the SDP, so this
  // mainly matters for producers that don't.
  function applyIceRoutePolicyToDescription(description, scope = 'primary', isOutbound = false) {
    if (!description || connectionMode() === 'auto' || !description.sdp) return description;
    let changed = 0;
    let withheld = 0;
    let rejected = 0;
    const mode = connectionMode();
    const withholdOwnHost = isOutbound && mode === 'proxy';
    const rejectRemotePrivate = !isOutbound && mode === 'proxy';
    const sdp = String(description.sdp).split(/\r?\n/).filter((line) => {
      if (!/^a=candidate:/i.test(line)) return true;
      if (withholdOwnHost && isLocalOnlyHostIceCandidateLine(line)) { withheld += 1; return false; }
      if (rejectRemotePrivate) {
        const parts = line.replace(/^a=/i, '').trim().split(/\s+/);
        const address = parts[4] || '';
        if (isPrivateIceAddress(address)) { rejected += 1; return false; }
      }
      return true;
    }).map((line) => {
      if (!/^a=candidate:/i.test(line)) return line;
      const rewritten = rewriteIceCandidatePriority(line);
      if (rewritten !== line) changed += 1;
      return rewritten;
    }).join('\r\n');
    if ((changed || withheld || rejected) && jbufDebugEnabled()) log(`${scope} reprioritized ${changed}, withheld ${withheld}, rejected ${rejected} embedded ICE candidate(s) for ${mode}`);
    return { type: description.type, sdp };
  }

  function stunUrl() {
    const value = query('stun');
    if (value === '0' || value === 'none' || value === 'off') return '';
    if (value) return value;
    // Mirror Glass's own configured STUN server (including an explicit blank,
    // i.e. "no STUN") instead of silently defaulting to Google's whenever the
    // config doesn't say otherwise -- configValue() only falls through to the
    // Google default when the key is truly absent (old cached config), not
    // when it's present-but-empty.
    const configured = configValue('stunUrl', undefined);
    if (configured !== undefined) return configured;
    return 'stun:stun.l.google.com:19302';
  }

  function keepAliveMs() {
    const raw = query('keepalive') || query('ka') || String(configValue('keepAliveSeconds', 15));
    const n = Number.parseInt(raw, 10);
    if (!Number.isFinite(n) || n <= 0) return 0;
    return Math.max(5, Math.min(n, 300)) * 1000;
  }



  function fullscreenEnabled() {
    const raw = (query('fullscreen') || query('fs') || query('autofs') || '1').toLowerCase();
    return !['0', 'false', 'off', 'no'].includes(raw);
  }

  function clampMs(value, min = 0, max = 500) {
    const n = Number.parseInt(value, 10);
    if (!Number.isFinite(n)) return min;
    return Math.max(min, Math.min(n, max));
  }

  function playerJitterMs() {
    const raw =
      query('jitter') ||
      query('jitterMs') ||
      query('jbuf') ||
      query('browserJitterTargetMs') ||
      query('browserJitterHintMs') ||
      query('jbufTargetMs') ||
      query('jitterBufferTargetMs') ||
      String(
        configValue(
          'playerJitterMs',
          configValue(
            'browserJitterTargetMs',
            configValue('browserJitterHintMs', configValue('jitterBufferTargetMs', 80))
          )
        )
      );
    const n = Number.parseInt(raw, 10);
    if (!Number.isFinite(n) || n <= 0) return 0;
    return Math.max(0, Math.min(n, 500));
  }

  function receiverJitterMs(kind) {
    const fallback = playerJitterMs();
    let raw = null;
    if (kind === 'audio') {
      raw =
        query('audioJbufMs') ||
        query('audioJitterMs') ||
        query('audioJitterBufferMs') ||
        query('audioJitterBufferTargetMs') ||
        configValue('audioJbufMs', configValue('audioJitterBufferTargetMs', fallback));
    } else if (kind === 'video') {
      raw =
        query('videoJbufMs') ||
        query('videoJitterMs') ||
        query('videoJitterBufferMs') ||
        query('videoJitterBufferTargetMs') ||
        configValue('videoJbufMs', configValue('videoJitterBufferTargetMs', fallback));
    }

    const n = Number.parseInt(raw !== null && raw !== undefined ? raw : fallback, 10);
    if (!Number.isFinite(n) || n <= 0) return 0;
    return Math.max(0, Math.min(n, 500));
  }

  function receiverKind(receiver) {
    return receiver && receiver.track && receiver.track.kind ? receiver.track.kind : 'unknown';
  }

  function jbufWatchdogMode() {
    const raw = query('jbufWatchdog') || query('watchdog') || String(configValue('jbufWatchdogMode', configValue('jbufWatchdog', 'Warn only')));
    const value = raw.toLowerCase();
    if (['0', 'false', 'off', 'none', 'disabled'].includes(value)) return 'Off';
    if (value.includes('reconnect')) return 'Auto-reconnect viewer';
    return 'Warn only';
  }

  function jbufMaxMs() {
    const raw = query('jbufMax') || query('jbufMaxMs') || String(configValue('jbufMaxMs', 30));
    const n = Number.parseInt(raw, 10);
    if (!Number.isFinite(n)) return 30;
    return Math.max(5, Math.min(n, 500));
  }

  function jbufDebugEnabled() {
    const raw = query('jbufDebug');
    if (raw !== null) return boolValue(raw, false);
    return boolValue(configValue('jbufDebug', false), false);
  }


  function splitPlayerSyncMode() {
    const raw = query('splitSync') || query('splitPlayerSync') || query('splitPlayerSyncMode') || String(configValue('splitPlayerSyncMode', configValue('splitAudioWatchdogMode', 'Off / free-run')));
    const value = String(raw || '').trim().toLowerCase();
    if (!value || ['0', 'false', 'off', 'none', 'free', 'free-run', 'freerun'].includes(value)) return 'Off / free-run';
    if (value.includes('soft') || value.includes('sync')) return 'Soft sync experimental';
    if (value.includes('watch') || value.includes('recover') || value.includes('audio')) return 'Audio watchdog only';
    return 'Off / free-run';
  }

  function splitPlayerSyncEnabled() {
    return splitAudioEnabled() && splitPlayerSyncMode() !== 'Off / free-run';
  }

  function splitSoftSyncEnabled() {
    return splitAudioEnabled() && splitPlayerSyncMode() === 'Soft sync experimental';
  }

  function splitAudioStallMs() {
    const raw = query('splitAudioStallSec') || query('splitAudioStallSeconds') || configValue('splitAudioStallSeconds', 3);
    const n = Number.parseInt(String(raw || ''), 10);
    const sec = Number.isFinite(n) ? n : 3;
    return Math.max(1, Math.min(sec, 30)) * 1000;
  }


  function watchdogWarmupMs() {
    const raw = query('watchdogWarmupSec') || query('watchdogWarmupSeconds') || query('jbufWatchdogWarmupSec') || query('jbufWatchdogWarmupSeconds') || configValue('watchdogWarmupSeconds', configValue('jbufWatchdogWarmupSeconds', configValue('splitAudioWarmupSeconds', configValue('splitAudioEqualizeSeconds', 8))));
    const n = Number.parseInt(String(raw || ''), 10);
    const sec = Number.isFinite(n) ? n : 8;
    return Math.max(0, Math.min(sec, 600)) * 1000;
  }

  function beginJbufWatchdogWarmup(reason = 'warmup') {
    const ms = watchdogWarmupMs();
    const now = performance.now();
    if (ms <= 0) return;
    state.jbufWatchdogWarmupUntil = Math.max(state.jbufWatchdogWarmupUntil || 0, now + ms);
    state.jbufWatchdogWarmupReason = reason;
    state.jbufHighTicks = 0;
    state.jbufHighTicksByKind = { audio: 0, video: 0 };
    state.jbufReconnectPending = false;
    if (jbufDebugEnabled()) log('jbuf watchdog warmup', reason, `${Math.round(ms)}ms`);
  }

  function jbufWatchdogWarmupRemainingMs() {
    const until = state.jbufWatchdogWarmupUntil || 0;
    return Math.max(0, until - performance.now());
  }

  function beginWatchdogWarmup(reason = 'warmup') {
    beginJbufWatchdogWarmup(reason);
    beginSplitAudioWarmup(reason);
  }

  function splitAudioWarmupMs() {
    const raw = query('splitAudioWarmupSec') || query('splitAudioWarmupSeconds') || query('splitAudioEqualizeSec') || query('splitAudioEqualizeSeconds') || configValue('splitAudioWarmupSeconds', configValue('splitAudioEqualizeSeconds', 8));
    const n = Number.parseInt(String(raw || ''), 10);
    const sec = Number.isFinite(n) ? n : 8;
    return Math.max(0, Math.min(sec, 600)) * 1000;
  }

  function beginSplitAudioWarmup(reason = 'warmup') {
    const sa = state.splitAudio;
    const ms = splitAudioWarmupMs();
    const now = performance.now();
    if (ms <= 0) return;
    sa.warmupUntil = Math.max(sa.warmupUntil || 0, now + ms);
    sa.lastHealthyAt = now;
    sa.stallTicks = 0;
    sa.offsetHighTicks = 0;
    resetSplitAudioOffsetBaseline(`warmup:${reason}`);
    if (jbufDebugEnabled()) log('split audio warmup', reason, `${Math.round(ms)}ms`);
  }

  function splitAudioWarmupRemainingMs() {
    const until = state.splitAudio.warmupUntil || 0;
    return Math.max(0, until - performance.now());
  }

  function splitAvOffsetWarnMs() {
    const raw = query('splitAvOffsetWarnMs') || query('splitOffsetWarnMs') || query('splitAvOffsetDriftWarnMs') || configValue('splitAvOffsetWarnMs', configValue('splitAvOffsetDriftWarnMs', 140));
    const n = Number.parseInt(String(raw || ''), 10);
    return Math.max(20, Math.min(Number.isFinite(n) ? n : 140, 1000));
  }

  function splitAvOffsetBaselineConfiguredMs() {
    const raw = query('splitAvOffsetBaselineMs') || query('splitOffsetBaselineMs') || query('splitAvBaselineMs') || configValue('splitAvOffsetBaselineMs', configValue('splitAvBaselineMs', 0));
    const n = Number.parseInt(String(raw || ''), 10);
    if (!Number.isFinite(n) || n <= 0) return NaN;
    return Math.max(0, Math.min(n, 1000));
  }

  function splitAvBaselineLearnTicks() {
    const raw = query('splitAvBaselineLearnTicks') || query('splitBaselineLearnTicks') || configValue('splitAvBaselineLearnTicks', 5);
    const n = Number.parseInt(String(raw || ''), 10);
    return Math.max(1, Math.min(Number.isFinite(n) ? n : 5, 30));
  }

  function resetSplitAudioOffsetBaseline(reason = 'reset') {
    const sa = state.splitAudio || {};
    const configured = splitAvOffsetBaselineConfiguredMs();
    if (Number.isFinite(configured)) {
      sa.avOffsetBaselineMs = configured;
      sa.avOffsetBaselineSamples = splitAvBaselineLearnTicks();
      sa.avOffsetBaselineLocked = true;
      sa.avOffsetBaselineReason = 'configured';
    } else {
      sa.avOffsetBaselineMs = NaN;
      sa.avOffsetBaselineSamples = 0;
      sa.avOffsetBaselineLocked = false;
      sa.avOffsetBaselineReason = reason;
    }
    sa.avOffsetDeltaMs = NaN;
    sa.offsetHighTicks = 0;
    resetLiveEdgeAverage(`av-baseline-${reason}`);
  }

  function updateSplitAudioOffsetBaseline(offsetMs, allowLearning = true) {
    const sa = state.splitAudio || {};
    if (!Number.isFinite(offsetMs)) return false;
    const configured = splitAvOffsetBaselineConfiguredMs();
    if (Number.isFinite(configured)) {
      sa.avOffsetBaselineMs = configured;
      sa.avOffsetBaselineSamples = splitAvBaselineLearnTicks();
      sa.avOffsetBaselineLocked = true;
      sa.avOffsetBaselineReason = 'configured';
      sa.avOffsetDeltaMs = Math.max(0, offsetMs - configured);
      return true;
    }

    if (!splitAudioOffsetPlausibleForBaseline(offsetMs)) {
      sa.avOffsetBaselineReason = 'implausible-offset';
      sa.avOffsetDeltaMs = Math.max(0, offsetMs - liveEdgeUnlearnedOffsetAllowanceMs());
      return false;
    }

    if (!allowLearning) {
      if (!Number.isFinite(sa.avOffsetBaselineMs)) {
        sa.avOffsetBaselineReason = 'waiting-warmup';
        sa.avOffsetDeltaMs = NaN;
      }
      return false;
    }

    const need = splitAvBaselineLearnTicks();
    const samples = Math.max(0, Number.isFinite(sa.avOffsetBaselineSamples) ? sa.avOffsetBaselineSamples : 0);
    if (!Number.isFinite(sa.avOffsetBaselineMs) || samples <= 0) {
      sa.avOffsetBaselineMs = offsetMs;
      sa.avOffsetBaselineSamples = 1;
      sa.avOffsetBaselineLocked = need <= 1;
      sa.avOffsetBaselineReason = sa.avOffsetBaselineLocked ? 'auto-learned' : 'learning';
    } else if (!sa.avOffsetBaselineLocked) {
      const nextSamples = samples + 1;
      sa.avOffsetBaselineMs = ((sa.avOffsetBaselineMs * samples) + offsetMs) / nextSamples;
      sa.avOffsetBaselineSamples = nextSamples;
      if (nextSamples >= need) {
        sa.avOffsetBaselineLocked = true;
        sa.avOffsetBaselineReason = 'auto-learned';
      } else {
        sa.avOffsetBaselineReason = 'learning';
      }
    }

    sa.avOffsetDeltaMs = Number.isFinite(sa.avOffsetBaselineMs) ? Math.max(0, offsetMs - sa.avOffsetBaselineMs) : NaN;
    return !!sa.avOffsetBaselineLocked;
  }

  function playerSeparateHtmlMediaElements() {
    const explicit = query('separateHtmlMediaElements') || query('playerSeparateHtmlMediaElements');
    if (explicit !== null && explicit !== undefined && explicit !== '') return boolValue(explicit, false);

    const configured = configValue('playerSeparateHtmlMediaElements', configValue('separateHtmlMediaElements', null));
    if (configured !== null && configured !== undefined) return boolValue(configured, false);

    // Backward compatibility for f39-f42 config/query values.
    const legacy = query('avRenderMode') || query('playerAvRenderMode') || String(configValue('playerAvRenderMode', configValue('avRenderMode', 'Synced single media element')));
    const value = String(legacy || '').toLowerCase();
    return value.includes('decoupled') || value.includes('separate') || value === 'split' || value === '2';
  }

  function playerAvRenderMode() {
    return playerSeparateHtmlMediaElements() ? 'Decoupled video/audio elements' : 'Synced single media element';
  }

  function isDecoupledRenderMode() {
    return playerSeparateHtmlMediaElements();
  }


  function mediaStreamGroupingMode() {
    const raw = query('mediaStreamGrouping') || query('avMediaStreamGrouping') || String(configValue('mediaStreamGrouping', configValue('avMediaStreamGrouping', 'Combined A/V MediaStream (default)')));
    const explicitSeparate = query('separateMediaStreams');
    if (explicitSeparate !== null && explicitSeparate !== undefined && explicitSeparate !== '') {
      return boolValue(explicitSeparate, false) ? 'Separate audio/video MediaStreams (experimental)' : 'Combined A/V MediaStream (default)';
    }
    return String(raw || '').toLowerCase().includes('separate')
      ? 'Separate audio/video MediaStreams (experimental)'
      : 'Combined A/V MediaStream (default)';
  }

  function separateMediaStreamsEnabled() {
    return !splitAudioEnabled() && mediaStreamGroupingMode().startsWith('Separate');
  }

  function sanitizeMediaStreamId(value, fallback) {
    const clean = String(value || '').trim().replace(/[^A-Za-z0-9_.-]/g, '-').replace(/-+/g, '-');
    return clean || fallback;
  }

  function mediaStreamId(kind) {
    const fallback = kind === 'audio' ? 'gstglass-audio' : 'gstglass-video';
    const raw = kind === 'audio'
      ? (query('audioMsid') || query('audioMediaStreamId') || configValue('audioMediaStreamId', configValue('audioMsid', fallback)))
      : (query('videoMsid') || query('videoMediaStreamId') || configValue('videoMediaStreamId', configValue('videoMsid', fallback)));
    return sanitizeMediaStreamId(raw, fallback);
  }

  function mediaStreamGroupingSignature() {
    return `${mediaStreamGroupingMode()}|${mediaStreamId('video')}|${mediaStreamId('audio')}`;
  }

  function effectiveDecoupledRenderMode() {
    // Physical split producers necessarily render through independent elements.
    // MSID grouping by itself no longer forces the HTML rendering choice.
    return isDecoupledRenderMode() || splitAudioEnabled();
  }

  function rewriteRemoteMediaStreamIds(description, scope = 'primary remote') {
    if (!description || !description.sdp || !separateMediaStreamsEnabled()) return description;

    const ids = { video: mediaStreamId('video'), audio: mediaStreamId('audio') };
    const lines = String(description.sdp).split(/\r?\n/);
    let currentKind = '';
    let mediaMsidChanges = 0;
    let ssrcMsidChanges = 0;
    let semanticChanged = false;

    const rewritten = lines.map((line) => {
      const media = /^m=(audio|video)\b/i.exec(line);
      if (media) currentKind = media[1].toLowerCase();
      else if (/^m=/i.test(line)) currentKind = '';

      if (/^a=msid-semantic:\s*WMS\b/i.test(line)) {
        semanticChanged = true;
        return `a=msid-semantic: WMS ${ids.video} ${ids.audio}`;
      }

      if ((currentKind === 'audio' || currentKind === 'video') && /^a=msid:/i.test(line)) {
        const match = /^a=msid:\s*([^\s]+)(?:\s+(.+))?$/i.exec(line);
        if (!match) return line;
        mediaMsidChanges += 1;
        const trackId = match[2] ? ` ${match[2]}` : '';
        return `a=msid:${ids[currentKind]}${trackId}`;
      }

      if ((currentKind === 'audio' || currentKind === 'video') && /^a=ssrc:\d+\s+msid:/i.test(line)) {
        const match = /^(a=ssrc:\d+\s+msid:)\s*([^\s]+)(?:\s+(.+))?$/i.exec(line);
        if (!match) return line;
        ssrcMsidChanges += 1;
        const trackId = match[3] ? ` ${match[3]}` : '';
        return `${match[1]}${ids[currentKind]}${trackId}`;
      }

      return line;
    });

    if (!semanticChanged) {
      const firstMedia = rewritten.findIndex((line) => /^m=/i.test(line));
      const semantic = `a=msid-semantic: WMS ${ids.video} ${ids.audio}`;
      if (firstMedia >= 0) rewritten.splice(firstMedia, 0, semantic);
      else rewritten.push(semantic);
    }

    if (!mediaMsidChanges && !ssrcMsidChanges) {
      log(`${scope} separate MediaStreams requested, but offer contained no rewritable msid attributes`);
      return description;
    }

    log(`${scope} separated MediaStreams`, `video=${ids.video}`, `audio=${ids.audio}`, `media-msid=${mediaMsidChanges}`, `ssrc-msid=${ssrcMsidChanges}`);
    return { type: description.type, sdp: rewritten.join('\r\n') };
  }

  function avPipelineMode() {
    const raw = query('avPipelineMode') || query('directWebRtcAvPipelineMode') || String(configValue('avPipelineMode', configValue('directWebRtcAvPipelineMode', 'Single pipeline')));
    const text = String(raw || '').toLowerCase();
    return text.includes('split') ? 'Split A/V pipelines - separate gst-launch' : 'Single pipeline';
  }

  function sharedSignalingEnabled() {
    const raw = query('sharedSignaling') || query('splitSharedSignaling');
    if (raw !== null && raw !== undefined && raw !== '') {
      return ['1', 'true', 'yes', 'on'].includes(String(raw).toLowerCase());
    }
    return Boolean(configValue('sharedSignaling', configValue('splitSharedSignaling', false)));
  }

  function splitAudioSignalingPort() {
    const raw = query('splitAudioPort') || query('audioPort') || query('splitAudioSignalingPort') || configValue('splitAudioSignalingPort', 0);
    const n = Number.parseInt(String(raw || ''), 10);
    return Number.isFinite(n) && n > 0 ? n : 0;
  }

  function producerMetaText(peer) {
    if (!peer) return '';
    const meta = peer.meta;
    if (!meta) return '';
    if (typeof meta === 'string') return meta.toLowerCase();
    try {
      return [meta.name, meta.title, meta.label, meta.kind, meta.role, meta.media, JSON.stringify(meta)]
        .filter(Boolean).join(' ').toLowerCase();
    } catch (_) {
      return String(meta).toLowerCase();
    }
  }

  function producerMatchesKind(peer, kind) {
    const target = String(kind || '').toLowerCase();
    const text = producerMetaText(peer);
    const configuredName = target === 'audio'
      ? String(configValue('splitAudioProducerName', 'gstglass-audio')).toLowerCase()
      : String(configValue('videoProducerName', 'gstglass-video')).toLowerCase();
    return text.includes(configuredName) || text.includes(`kind=${target}`) || text.includes(`kind:${target}`) || text.includes(`"kind":"${target}"`) || text.includes(target);
  }

  function selectProducerForKind(producers, kind) {
    const list = [...(producers ? producers.values() : [])];
    if (!list.length) return null;
    if (!sharedSignalingEnabled()) return list[0];
    return list.find((peer) => producerMatchesKind(peer, kind)) || null;
  }

  function isLoopbackHostName(hostname) {
    const h = String(hostname || '').toLowerCase().replace(/^\[|\]$/g, '');
    return h === 'localhost' || h === '127.0.0.1' || h === '::1' || h === '0.0.0.0' || h.startsWith('127.');
  }

  function formatWsHost(hostname) {
    const h = String(hostname || '').trim();
    if (!h || h === '0.0.0.0' || h === '*') return '127.0.0.1';
    if (h.includes(':') && !h.startsWith('[')) return `[${h}]`;
    return h;
  }

  function buildProxyAwareWsUrl(port) {
    if (!port) return '';
    const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
    const host = formatWsHost(location.hostname || '127.0.0.1');
    return `${scheme}://${host}:${port}`;
  }

  function trimWsUrl(url) {
    return String(url || '').replace(/\/$/, '');
  }

  function primaryWsUrlForSplit() {
    try {
      if (state.ws && state.ws.url) return state.ws.url;
    } catch (_) {}
    return defaultWs();
  }

  function buildWsWithPort(primary, port) {
    if (!port || !primary) return '';
    try {
      const u = new URL(primary, location.href);
      u.port = String(port);
      return trimWsUrl(u.toString());
    } catch (err) {
      log('could not apply split signaling port to URL', primary, port, err);
      return buildProxyAwareWsUrl(port);
    }
  }

  function normalizeWsUrl(raw) {
    const text = String(raw || '').trim();
    if (!text || text === '0' || text.toLowerCase() === 'off' || text.toLowerCase() === 'auto') return '';
    if (text.startsWith('ws://') || text.startsWith('wss://')) return text;
    if (text.startsWith('//')) return (location.protocol === 'https:' ? 'wss:' : 'ws:') + text;
    if (/^[^/:]+:\d+$/.test(text) || /^\[[^\]]+\]:\d+$/.test(text)) return (location.protocol === 'https:' ? 'wss://' : 'ws://') + text;
    return text;
  }

  function directSplitAudioWsUrl() {
    if (sharedSignalingEnabled()) return trimWsUrl(directVideoWsUrl());
    const explicit = query('splitAudioWs') || query('audioWs') || String(configValue('splitAudioWsUrl', ''));
    const normalized = normalizeWsUrl(explicit);
    const cfgPort = splitAudioSignalingPort();

    if (normalized) {
      try {
        const u = new URL(normalized, location.href);
        const pageIsLoopback = isLoopbackHostName(location.hostname);
        const targetIsLoopback = isLoopbackHostName(u.hostname);
        const derivedPort = Number.parseInt(u.port || String(cfgPort || ''), 10);

        if (targetIsLoopback && !pageIsLoopback) {
          const rebuilt = buildWsWithPort(directVideoWsUrl(), derivedPort || cfgPort);
          log('split audio ignoring loopback direct WS URL for remote page', normalized, '=>', rebuilt);
          return rebuilt;
        }

        if (location.protocol === 'https:' && u.protocol === 'ws:') {
          log('split audio ignoring insecure direct WS URL on HTTPS page', normalized);
          return '';
        }

        return trimWsUrl(u.toString());
      } catch (err) {
        log('split audio invalid explicit direct WS URL; deriving from primary direct URL', normalized, err);
      }
    }

    return buildWsWithPort(directVideoWsUrl(), cfgPort);
  }

  function pageHostSplitAudioWsUrl() {
    if (sharedSignalingEnabled()) return pageHostVideoWsUrl();
    return pageHostWsUrl(splitAudioSignalingPort());
  }

  // Mirrors externalVideoWsUrl() for the independent split-audio signalling
  // connection -- '' (dropped by uniqueWsUrls) unless a split-audio external
  // port is actually configured (splitAudioExternalSignalingPort).
  function externalSplitAudioWsUrl() {
    if (sharedSignalingEnabled()) return '';
    const port = Number(query('splitAudioExternalSignalingPort') || configValue('splitAudioExternalSignalingPort', 0)) || 0;
    if (!port) return '';
    return pageHostWsUrl(port);
  }

  function splitAudioSignalingCandidates() {
    if (sharedSignalingEnabled()) return authenticatedSignalingCandidates([primaryWsUrlForSplit()]);
    const proxy = proxyWsUrl('audio');
    const direct = directSplitAudioWsUrl();
    const pageDirect = pageHostSplitAudioWsUrl();
    const external = externalSplitAudioWsUrl();
    const mode = connectionMode();
    // Keep signaling transport independent from the PROXY media/ICE policy,
    // mirroring the primary connection. The configured /voice path stays
    // exact and first; mapped/direct root WebSockets remain fallbacks.
    if (mode === 'proxy') return authenticatedSignalingCandidates([proxy, external, pageDirect, direct]);
    if (mode === 'lan') return authenticatedSignalingCandidates([proxy, direct, external]);
    if (state.signalingRoute === 'direct') return authenticatedSignalingCandidates([direct, external, proxy]);
    return authenticatedSignalingCandidates([proxy, direct, external]);
  }

  function splitAudioWsUrl() {
    const sa = state.splitAudio || {};
    return trimWsUrl(sa.url || splitAudioSignalingCandidates()[0] || '');
  }

  function splitAudioEnabled() {
    return avPipelineMode().toLowerCase().includes('split');
  }

  function playerConfigLine() {
    const topology = avPipelineMode();
    const render = playerAvRenderMode();
    const sync = splitAudioEnabled() ? splitPlayerSyncMode() : 'single-pipeline';
    const grouping = separateMediaStreamsEnabled() ? `separate msid V=${mediaStreamId('video')} A=${mediaStreamId('audio')}` : 'combined msid';
    const effectiveRender = splitAudioEnabled() && !isDecoupledRenderMode() ? `${render}→forced split elements` : render;
    return `playback ${topology} · render ${effectiveRender} · ${grouping} · sync ${sync} · targets V${receiverJitterMs('video')}ms/A${receiverJitterMs('audio')}ms · max ${jbufMaxMs()}ms · watchdog ${jbufWatchdogMode()}`;
  }

  function splitAudioStatusLine() {
    const sa = state.splitAudio || {};
    if (!splitAudioEnabled()) return 'off';
    const url = sa.url || splitAudioWsUrl() || 'no-url';
    const pcState = sa.pc ? (sa.pc.iceConnectionState || sa.pc.connectionState || 'pc') : 'no-pc';
    const wsState = sa.ws ? ['connecting', 'open', 'closing', 'closed'][sa.ws.readyState] || String(sa.ws.readyState) : 'no-ws';
    const producerCount = sa.producers ? sa.producers.size : 0;
    const err = sa.lastError ? ` err ${sa.lastError}` : '';
    const track = sa.lastTrackKind ? ` track ${sa.lastTrackKind}` : '';
    const ka = sa.keepAliveTimer ? ` ka ${sa.keepAliveCount || 0}` : '';
    const route = sa.route ? ` ${sa.route}` : '';
    return `${sa.status || 'idle'}${route} ${wsState}/${pcState} producers ${producerCount} ${url}${track}${ka}${err}`;
  }


  function splitSyncStatusLine() {
    if (!splitAudioEnabled()) return 'split sync off';
    const sa = state.splitAudio || {};
    const mode = splitPlayerSyncMode();
    const offset = Number.isFinite(sa.lastAvOffsetMs) ? `offset audio+${Math.round(sa.lastAvOffsetMs)}ms` : 'offset --';
    const baseline = Number.isFinite(sa.avOffsetBaselineMs) ? ` baseline ${Math.round(sa.avOffsetBaselineMs)}ms` : ' baseline auto';
    const delta = Number.isFinite(sa.avOffsetDeltaMs) ? ` drift +${Math.round(sa.avOffsetDeltaMs)}ms` : '';
    const learnNeed = splitAvBaselineLearnTicks();
    const learn = (!sa.avOffsetBaselineLocked && Number.isFinite(sa.avOffsetBaselineSamples) && sa.avOffsetBaselineSamples > 0) ? ` learning ${sa.avOffsetBaselineSamples}/${learnNeed}` : '';
    const warmupLeft = splitAudioWarmupRemainingMs();
    const warmup = warmupLeft > 0 ? ` warmup ${Math.ceil(warmupLeft / 1000)}s` : '';
    const health = sa.syncHealth || (mode === 'Off / free-run' ? 'free-run' : 'watching');
    const recoveries = Number.isFinite(sa.recoveryCount) && sa.recoveryCount > 0 ? ` recoveries ${sa.recoveryCount}` : '';
    return `split sync ${mode} ${offset}${baseline}${delta}${learn}${warmup} health ${health}${recoveries}`;
  }

  function jbufTrendWindowTicks() {
    const sec = Number.parseInt(query('jbufTrendSec') || String(configValue('jbufTrendWindowSec', 3)), 10);
    return Math.max(1, Math.min(Number.isFinite(sec) ? sec : 3, 10));
  }

  function adaptiveJitterEnabled() {
    const raw = query('adaptive') || query('adaptiveJitter') || query('aj');
    if (raw !== null) return !['0', 'false', 'off', 'no'].includes(String(raw).toLowerCase());
    return !!configValue('adaptiveJitter', false);
  }

  function adaptiveJitterMinMs() {
    return clampMs(query('jitterMin') || query('adaptiveMin') || configValue('adaptiveJitterMinMs', playerJitterMs()), 0, 3000);
  }

  function adaptiveJitterMaxMs() {
    const min = adaptiveJitterMinMs();
    return Math.max(min, clampMs(query('jitterMax') || query('adaptiveMax') || configValue('adaptiveJitterMaxMs', Math.max(min, 500)), min, 500));
  }

  function setReceiverJitter(ms, reason = 'configured') {
    const safeMs = Math.max(0, Math.min(Number(ms) || 0, 500));
    state.currentJitterMs = safeMs;
    if (safeMs <= 0) return;
    state.receivers.forEach((receiver) => applyReceiverJitter(receiver, reason, safeMs, true));
    log('receiver jitter target override', `${safeMs}ms`, reason);
  }

  function applyReceiverJitter(receiver, reason = 'configured', overrideMs = null, quiet = false) {
    if (!receiver) return false;
    state.receivers.add(receiver);
    const kind = receiverKind(receiver);
    const ms = overrideMs !== null && overrideMs !== undefined
      ? Math.max(0, Math.min(Number(overrideMs) || 0, 500))
      : receiverJitterMs(kind);
    if (ms <= 0) return false;
    const legacySeconds = ms / 1000;
    let applied = false;
    try {
      if ('jitterBufferTarget' in receiver) {
        // Current Chromium API uses milliseconds.
        receiver.jitterBufferTarget = ms;
        applied = true;
      }
      if ('playoutDelayHint' in receiver) {
        // Legacy Chromium API uses seconds. Set it too when present.
        receiver.playoutDelayHint = legacySeconds;
        applied = true;
      }
      if (applied) {
        if (kind === 'audio' || kind === 'video') state.currentJitterMsByKind[kind] = ms;
        if (!quiet || jbufDebugEnabled()) log(`${kind} receiver jitter target set`, `${ms}ms`, reason);
        return true;
      }
      if (!quiet) log(`${kind} receiver jitter target not supported by this browser`, `${ms}ms requested`);
    } catch (err) {
      if (!quiet) log(`${kind} receiver jitter target failed`, err && err.message ? err.message : err);
    }
    return false;
  }

  function applyAllReceiverJitter(reason = 'refresh', quiet = true) {
    let count = 0;
    state.receivers.forEach((receiver) => {
      if (applyReceiverJitter(receiver, reason, null, quiet)) count += 1;
    });
    return count;
  }

  function videoZoomMax() {
    const raw = query('zoomMax') || query('videoZoomMax') || configValue('videoZoomMax', 4);
    const n = Number.parseFloat(String(raw));
    return Math.max(2, Math.min(Number.isFinite(n) ? n : 4, 8));
  }

  function constrainVideoZoom(scale, x, y) {
    const width = Math.max(1, video.clientWidth || window.innerWidth || 1);
    const height = Math.max(1, video.clientHeight || window.innerHeight || 1);
    const maxX = width * Math.max(0, scale - 1) / 2;
    const maxY = height * Math.max(0, scale - 1) / 2;
    return {
      x: Math.max(-maxX, Math.min(Number(x) || 0, maxX)),
      y: Math.max(-maxY, Math.min(Number(y) || 0, maxY))
    };
  }

  function updateVideoZoomControl() {
    const button = state.controller && state.controller.zoomButton;
    if (!button) return;
    const scale = state.videoZoom.scale || 1;
    button.hidden = scale <= 1.001;
    button.textContent = `↺ ${scale.toFixed(1)}×`;
    button.title = `Reset video zoom (${scale.toFixed(1)}×)`;
    button.setAttribute('aria-label', button.title);
  }

  function applyVideoZoom(scale, x, y, reason = 'gesture') {
    const zoom = state.videoZoom;
    const nextScale = Math.max(1, Math.min(Number(scale) || 1, videoZoomMax()));
    const next = nextScale <= 1.001 ? { x: 0, y: 0 } : constrainVideoZoom(nextScale, x, y);
    zoom.scale = nextScale <= 1.001 ? 1 : nextScale;
    zoom.x = next.x;
    zoom.y = next.y;
    video.style.transform = zoom.scale === 1
      ? ''
      : `translate3d(${zoom.x.toFixed(2)}px, ${zoom.y.toFixed(2)}px, 0) scale(${zoom.scale.toFixed(4)})`;
    document.body.classList.toggle('videoZoomed', zoom.scale > 1.001);
    updateVideoZoomControl();
    if (jbufDebugEnabled() && reason === 'reset') log('video zoom reset');
  }

  function resetVideoZoom(reason = 'reset') {
    applyVideoZoom(1, 0, 0, reason);
  }

  function setupVideoPinchZoom() {
    const zoom = state.videoZoom;

    function pointerCenter(points) {
      const pair = Array.from(points.values()).slice(0, 2);
      return { x: (pair[0].x + pair[1].x) / 2, y: (pair[0].y + pair[1].y) / 2 };
    }

    function pointerDistance(points) {
      const pair = Array.from(points.values()).slice(0, 2);
      return Math.hypot(pair[1].x - pair[0].x, pair[1].y - pair[0].y);
    }

    function beginPinch() {
      if (zoom.pointers.size < 2) return;
      // Use the untransformed player viewport. getBoundingClientRect() on the
      // video includes its current CSS scale and would make a second pinch jump.
      const rect = (playerRoot || video).getBoundingClientRect();
      const center = pointerCenter(zoom.pointers);
      const scale = Math.max(1, zoom.scale || 1);
      zoom.pinchStart = {
        distance: Math.max(1, pointerDistance(zoom.pointers)),
        scale,
        anchorX: (center.x - rect.left - rect.width / 2 - zoom.x) / scale,
        anchorY: (center.y - rect.top - rect.height / 2 - zoom.y) / scale
      };
      zoom.panStart = null;
    }

    function beginPan(pointerId, point) {
      zoom.panStart = zoom.scale > 1.001
        ? { pointerId, clientX: point.x, clientY: point.y, x: zoom.x, y: zoom.y }
        : null;
    }

    function finishPointer(ev) {
      if (!zoom.pointers.has(ev.pointerId)) return;
      zoom.pointers.delete(ev.pointerId);
      if (zoom.gestureMoved) zoom.suppressTapUntil = Date.now() + 500;

      if (zoom.pointers.size >= 2) {
        beginPinch();
      } else if (zoom.pointers.size === 1) {
        const remaining = Array.from(zoom.pointers.entries())[0];
        zoom.pinchStart = null;
        beginPan(remaining[0], remaining[1]);
      } else {
        zoom.pinchStart = null;
        zoom.panStart = null;
      }
    }

    video.addEventListener('pointerdown', (ev) => {
      if (ev.pointerType === 'mouse' && ev.button !== 0) return;
      if (zoom.pointers.size === 0) zoom.gestureMoved = false;
      zoom.pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
      try { video.setPointerCapture(ev.pointerId); } catch (_) {}
      if (zoom.pointers.size >= 2) beginPinch();
      else beginPan(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    });

    video.addEventListener('pointermove', (ev) => {
      if (!zoom.pointers.has(ev.pointerId)) return;
      zoom.pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });

      if (zoom.pointers.size >= 2 && zoom.pinchStart) {
        ev.preventDefault();
        const rect = (playerRoot || video).getBoundingClientRect();
        const center = pointerCenter(zoom.pointers);
        const ratio = pointerDistance(zoom.pointers) / zoom.pinchStart.distance;
        const scale = Math.max(1, Math.min(zoom.pinchStart.scale * ratio, videoZoomMax()));
        const x = center.x - rect.left - rect.width / 2 - zoom.pinchStart.anchorX * scale;
        const y = center.y - rect.top - rect.height / 2 - zoom.pinchStart.anchorY * scale;
        if (Math.abs(ratio - 1) > 0.015) zoom.gestureMoved = true;
        applyVideoZoom(scale, x, y, 'pinch');
        return;
      }

      const pan = zoom.panStart;
      if (pan && pan.pointerId === ev.pointerId && zoom.scale > 1.001) {
        ev.preventDefault();
        const dx = ev.clientX - pan.clientX;
        const dy = ev.clientY - pan.clientY;
        if (Math.hypot(dx, dy) > 3) zoom.gestureMoved = true;
        applyVideoZoom(zoom.scale, pan.x + dx, pan.y + dy, 'pan');
      }
    }, { passive: false });

    video.addEventListener('pointerup', finishPointer);
    video.addEventListener('pointercancel', finishPointer);
    video.addEventListener('lostpointercapture', finishPointer);
  }

  function isFullscreen() {
    return !!(document.fullscreenElement || document.webkitFullscreenElement || document.msFullscreenElement || video.webkitDisplayingFullscreen);
  }

  function setFullscreenState() {
    const active = isFullscreen();
    document.body.classList.toggle('isFullscreen', active);
    document.body.classList.toggle('fsWanted', fullscreenEnabled() && document.body.classList.contains('playing') && !isFullscreen());
    if (active) document.body.classList.remove('fsBlocked');
    const button = state.controller && state.controller.fullscreenButton;
    if (button) {
      button.textContent = active ? '⧢' : '⛶';
      button.title = active ? 'Exit fullscreen' : 'Enter fullscreen';
      button.setAttribute('aria-label', button.title);
      button.setAttribute('aria-pressed', active ? 'true' : 'false');
    }
  }

  let playerUiHideTimer = null;

  function hidePlayerUi() {
    if (state.controller.uiPinned) return;
    if (playerUiHideTimer) clearTimeout(playerUiHideTimer);
    playerUiHideTimer = null;
    document.body.classList.remove('uiActive');
    if (!document.body.classList.contains('statusAlert')) {
      document.body.classList.remove('showStatus');
    }
  }

  function revealPlayerUi(reason = 'interaction', holdMs = 2200) {
    if (!document.body.classList.contains('playing')) return;
    document.body.classList.add('uiActive', 'showStatus');
    if (playerUiHideTimer) clearTimeout(playerUiHideTimer);
    if (state.controller.uiPinned) {
      playerUiHideTimer = null;
      return;
    }
    playerUiHideTimer = setTimeout(() => {
      playerUiHideTimer = null;
      // A paused player must keep its controls available so playback can be
      // resumed without hunting for an invisible button.
      if (!state.controller.userPaused && !state.controller.uiPinned) hidePlayerUi();
    }, Math.max(500, Number(holdMs) || 2200));
    if (jbufDebugEnabled()) log('player UI revealed', reason);
  }

  function noteVideoFramePresented(reason = 'frame') {
    state.lastPresentedVideoAt = performance.now();
    if (jbufDebugEnabled()) log('video frame presented', reason);
  }

  function markTrackForRealtimeDecode(track) {
    if (!track || track.kind !== 'video') return;
    // contentHint does not force hardware decode, but it tells the browser this
    // is continuously moving realtime content rather than text/detail capture.
    try { track.contentHint = 'motion'; } catch (_) {}
  }

  function cancelFullscreenRenderRecovery() {
    state.fullscreenRenderRecoveryToken += 1;
    if (state.fullscreenRenderRecoveryTimer) clearTimeout(state.fullscreenRenderRecoveryTimer);
    state.fullscreenRenderRecoveryTimer = null;
  }

  function rebindVideoSurface(reason = 'render-recovery') {
    const source = video.srcObject;
    if (!source || state.controller.userPaused) return false;
    const liveTrack = source.getVideoTracks && source.getVideoTracks().find((track) => track.readyState === 'live');
    if (!liveTrack) return false;
    markTrackForRealtimeDecode(liveTrack);
    invalidateMediaPlay('video');
    try { video.pause(); } catch (_) {}
    video.srcObject = null;
    // Re-attaching the same MediaStream rebuilds a lost fullscreen/compositor
    // surface without renegotiating WebRTC or disturbing the separate audio path.
    requestAnimationFrame(() => {
      if (state.controller.userPaused || !source.getVideoTracks().some((track) => track.readyState === 'live')) return;
      video.srcObject = source;
      requestMediaPlayback(video, 'video', reason);
      state.fullscreenRenderRecoveryCount += 1;
      if (jbufDebugEnabled()) log('video render surface rebound', reason, `count=${state.fullscreenRenderRecoveryCount}`);
    });
    return true;
  }

  function scheduleFullscreenRenderRecovery(reason = 'fullscreen', delayMs = 180) {
    cancelFullscreenRenderRecovery();
    const token = state.fullscreenRenderRecoveryToken;
    const source = video.srcObject;
    if (!source || state.controller.userPaused) return;
    const track = source.getVideoTracks && source.getVideoTracks()[0];
    if (!track || track.readyState !== 'live') return;
    markTrackForRealtimeDecode(track);
    requestMediaPlayback(video, 'video', `${reason}:play`);

    const startedAt = performance.now();
    let frameObserved = false;
    if (typeof video.requestVideoFrameCallback === 'function') {
      try {
        video.requestVideoFrameCallback(() => {
          if (token !== state.fullscreenRenderRecoveryToken || video.srcObject !== source) return;
          frameObserved = true;
          noteVideoFramePresented(reason);
        });
      } catch (_) {}
    }

    state.fullscreenRenderRecoveryTimer = setTimeout(() => {
      state.fullscreenRenderRecoveryTimer = null;
      if (token !== state.fullscreenRenderRecoveryToken || video.srcObject !== source || state.controller.userPaused) return;
      const stillLive = source.getVideoTracks && source.getVideoTracks().some((item) => item.readyState === 'live');
      if (!stillLive) return;
      const recentlyPresented = state.lastPresentedVideoAt >= startedAt;
      // readyState can be HAVE_ENOUGH_DATA while the fullscreen render surface
      // itself is blank. A missing presented-frame callback is the key signal.
      if (!frameObserved && !recentlyPresented) rebindVideoSurface(`${reason}:blank-surface`);
    }, Math.max(350, Number(delayMs) + 700));
  }

  async function requestVideoFullscreen(reason = 'manual') {
    if (!fullscreenEnabled()) return false;
    if (isFullscreen()) return true;
    const target = androidContainerFullscreen && playerRoot ? playerRoot : video;
    try {
      if (target.requestFullscreen) {
        await target.requestFullscreen({ navigationUI: 'hide' });
      } else if (target.webkitRequestFullscreen) {
        target.webkitRequestFullscreen();
      } else if (video.webkitEnterFullscreen) {
        // iOS fallback only. Android Chromium is deliberately kept out of the
        // native <video> fullscreen surface to avoid hidden render buffering.
        video.webkitEnterFullscreen();
      } else if (document.documentElement.requestFullscreen) {
        await document.documentElement.requestFullscreen({ navigationUI: 'hide' });
      } else {
        return false;
      }
      document.body.classList.remove('fsBlocked');
      setFullscreenState();
      syncScreenWakeLock('fullscreen-enter', true);
      scheduleFullscreenRenderRecovery(`fullscreen-enter:${reason}`);
      return true;
    } catch (err) {
      log('fullscreen request blocked', reason, err && err.message ? err.message : err);
      if (reason !== 'auto') document.body.classList.add('fsBlocked');
      setFullscreenState();
      return false;
    }
  }

  async function exitPlayerFullscreen(reason = 'manual') {
    if (!isFullscreen()) return true;
    try {
      const domFullscreen = document.fullscreenElement || document.webkitFullscreenElement || document.msFullscreenElement;
      if (domFullscreen && document.exitFullscreen) {
        await document.exitFullscreen();
      } else if (domFullscreen && document.webkitExitFullscreen) {
        document.webkitExitFullscreen();
      } else if (domFullscreen && document.msExitFullscreen) {
        document.msExitFullscreen();
      } else if (video.webkitDisplayingFullscreen && video.webkitExitFullscreen) {
        video.webkitExitFullscreen();
      } else {
        return false;
      }
      setFullscreenState();
      syncScreenWakeLock('fullscreen-exit', true);
      return true;
    } catch (err) {
      log('fullscreen exit failed', reason, err && err.message ? err.message : err);
      setFullscreenState();
      return false;
    }
  }

  async function togglePlayerFullscreen(reason = 'controller') {
    return isFullscreen()
      ? exitPlayerFullscreen(reason)
      : requestVideoFullscreen(reason);
  }

  function attemptAutoFullscreen() {
    if (state.fullscreenAutoTried || !fullscreenEnabled() || isFullscreen()) return;
    state.fullscreenAutoTried = true;
    // Browsers usually block fullscreen without a user gesture. We still try once
    // so desktop/kiosk/browser-policy cases can enter fullscreen automatically.
    requestVideoFullscreen('auto').then((ok) => {
      if (!ok) {
        document.body.classList.add('fsBlocked');
        setFullscreenState();
      }
    });
  }

  function recordUserInteraction(reason = 'gesture') {
    state.lastUserGestureAt = Date.now();
    revealPlayerUi(reason);
  }

  function noteUserGesture(requestFullscreen = true) {
    recordUserInteraction('gesture');
    state.controller.userPaused = false;
    applyLogicalMediaState('gesture');
    if (requestFullscreen) requestVideoFullscreen('gesture');
  }

  function shortId(id) {
    if (!id) return '—';
    return id.length > 12 ? `${id.slice(0, 8)}…${id.slice(-4)}` : id;
  }

  function setStatus(text, detail = '', kind = 'warn') {
    // Once media is playing, the compact Glass overlay is deliberately only a
    // high-level state indicator. All diagnostics belong in Stats overlay.
    if (state.started && document.body.classList.contains('playing')) {
      const lowered = `${text} ${detail}`.toLowerCase();
      if (lowered.includes('desync') || lowered.includes('de-sync') || lowered.includes('drift')) {
        text = 'De-synced';
        kind = 'bad';
      } else if (kind === 'good') {
        text = 'Live';
      } else {
        text = 'Delayed';
        kind = 'warn';
      }
      detail = '';
    }
    statusEl.textContent = text;
    statusEl.className = `status ${kind}`;
    detailEl.textContent = detail;
    document.body.classList.toggle('statusAlert', kind !== 'good');
    document.body.classList.add('showStatus');
    if (kind === 'good' && state.started) {
      setTimeout(() => document.body.classList.remove('showStatus'), 2500);
    }
    setFullscreenState();
  }

  function liveEdgeGreenMs() {
    const value = Number.parseInt(query('liveEdgeGreenMs') || String(configValue('liveEdgeGreenMs', 50)), 10);
    return Number.isFinite(value) ? Math.max(1, value) : 50;
  }

  function liveEdgeYellowMs() {
    const value = Number.parseInt(query('liveEdgeYellowMs') || String(configValue('liveEdgeYellowMs', 120)), 10);
    return Number.isFinite(value) ? Math.max(liveEdgeGreenMs() + 1, value) : 120;
  }

  function liveEdgeAverageWindowMs() {
    const seconds = Number.parseFloat(query('liveEdgeAverageSec') || String(configValue('liveEdgeAverageSec', 5)));
    return Number.isFinite(seconds) ? Math.round(Math.min(30, Math.max(1, seconds)) * 1000) : 5000;
  }

  function resetLiveEdgeAverage(reason = 'reset') {
    state.liveEdgeSamples = [];
    state.liveEdgeEstimateMs = NaN;
    state.liveEdgeInstantMs = NaN;
    if (jbufDebugEnabled()) log('live edge average reset', reason);
  }

  function liveEdgeUnlearnedOffsetAllowanceMs() {
    // Before an automatic split A/V baseline is trustworthy, allow the larger
    // of the configured JBUF ceiling and the normal drift warning. A raw
    // one-second audio lead must never be silently learned as "normal".
    return Math.max(jbufMaxMs(), splitAvOffsetWarnMs());
  }

  function splitAudioOffsetPlausibleForBaseline(offsetMs) {
    if (!Number.isFinite(offsetMs)) return false;
    return Math.max(0, offsetMs) <= liveEdgeUnlearnedOffsetAllowanceMs();
  }

  function splitAudioExcessOffsetMs() {
    if (!splitAudioEnabled()) return 0;
    const sa = state.splitAudio || {};
    if (sa.avOffsetBaselineLocked && Number.isFinite(sa.avOffsetDeltaMs)) {
      return Math.max(0, sa.avOffsetDeltaMs);
    }
    if (Number.isFinite(sa.lastAvOffsetMs)) {
      return Math.max(0, sa.lastAvOffsetMs - liveEdgeUnlearnedOffsetAllowanceMs());
    }
    return 0;
  }

  function updateLiveEdgeAverage(excessMs, now = performance.now()) {
    if (!Number.isFinite(excessMs)) {
      state.liveEdgeInstantMs = NaN;
      return state.liveEdgeEstimateMs;
    }

    const sampleMs = Math.max(0, excessMs);
    const windowMs = liveEdgeAverageWindowMs();
    const samples = Array.isArray(state.liveEdgeSamples) ? state.liveEdgeSamples : [];
    samples.push({ at: now, value: sampleMs });
    const cutoff = now - windowMs;
    while (samples.length && samples[0].at < cutoff) samples.shift();
    // Defensive cap in case a browser resumes an unusually fast timer after sleep.
    if (samples.length > 120) samples.splice(0, samples.length - 120);
    state.liveEdgeSamples = samples;

    const rollingAverage = samples.reduce((sum, sample) => sum + sample.value, 0) / Math.max(1, samples.length);
    state.liveEdgeInstantMs = sampleMs;
    state.liveEdgeEstimateMs = rollingAverage;
    return state.liveEdgeEstimateMs;
  }

  function estimateLiveEdgeMs(rttMs) {
    const videoJ = state.latestJbufStatsByKind.video;
    const videoWindowMs = videoJ && Number.isFinite(videoJ.windowMs)
      ? Math.max(0, videoJ.windowMs)
      : (videoJ && Number.isFinite(videoJ.valueMs) ? Math.max(0, videoJ.valueMs) : NaN);

    // Live Edge is the rolling average of excess holdback beyond the expected
    // transport/buffer floor. RTT is subtracted. A learned healthy A/V offset
    // carries no penalty, but positive drift above it does. While the baseline
    // is not yet trustworthy, raw offset beyond the existing JBUF/drift
    // allowance contributes immediately instead of being ignored.
    const avExcessMs = splitAudioExcessOffsetMs();

    // Do not poison the rolling window with a startup sample that lacks the
    // network floor. Keep the last valid average until both inputs exist.
    if (!Number.isFinite(videoWindowMs) || !Number.isFinite(rttMs)) return state.liveEdgeEstimateMs;

    const networkFloorMs = Math.max(0, rttMs);
    const excessMs = Math.max(0, videoWindowMs + avExcessMs - networkFloorMs);
    return updateLiveEdgeAverage(excessMs);
  }

  function liveEdgeDescriptor(ms, deSynced = false) {
    if (deSynced) return { label: 'De-synced', icon: '🔴', kind: 'bad', state: 'red' };
    if (!Number.isFinite(ms)) return { label: 'Live edge —', icon: '🟡', kind: 'warn', state: 'unknown' };
    if (ms <= liveEdgeGreenMs()) return { label: 'Live', icon: '🟢', kind: 'good', state: 'green' };
    if (ms <= liveEdgeYellowMs()) return { label: 'Delayed', icon: '🟡', kind: 'warn', state: 'yellow' };
    return { label: 'Delayed', icon: '🔴', kind: 'bad', state: 'red' };
  }

  function splitIsDesynced() {
    if (!splitAudioEnabled()) return false;
    const sa = state.splitAudio || {};
    if (Number.isFinite(sa.avOffsetDeltaMs) && sa.avOffsetBaselineLocked && sa.avOffsetDeltaMs > splitAvOffsetWarnMs()) return true;
    if (!sa.avOffsetBaselineLocked && Number.isFinite(sa.lastAvOffsetMs) &&
        sa.lastAvOffsetMs > liveEdgeUnlearnedOffsetAllowanceMs()) return true;
    return /drift|desync|de-sync|stale|stalled|ended|implausible/i.test(String(sa.syncHealth || ''));
  }

  function liveEdgeLine(ms, descriptor) {
    const value = Number.isFinite(ms) ? `${Math.round(ms)}ms` : '—';
    const seconds = Math.round(liveEdgeAverageWindowMs() / 1000);
    return `LIVE EDGE AVG ${value} ${descriptor.icon} · ${descriptor.label} · ${seconds}s`;
  }

  function log(...args) {
    console.log('[GStreamer Glass Live]', ...args);
  }

  function logicalSplitControlsActive() {
    return splitAudioEnabled() || effectiveDecoupledRenderMode();
  }

  function signalingTransportStatusLine() {
    const url = state.signalingUrl || defaultWs();
    let scheme = 'WS';
    let host = url;
    try {
      const parsed = new URL(url, location.href);
      scheme = parsed.protocol === 'wss:' ? 'WSS' : 'WS';
      host = parsed.host;
    } catch (_) {}
    const route = state.signalingRoute === 'direct'
      ? (connectionMode() === 'auto' ? 'direct fallback' : 'direct')
      : (state.signalingRoute === 'external' ? 'external (mapped port)'
        : (state.signalingRoute === 'explicit' ? 'explicit' : 'proxy'));
    return `signaling ${route} ${scheme} ${host}`;
  }

  function connectionModeStatusLine() {
    return `mode ${connectionMode().toUpperCase()} · ${signalingTransportStatusLine()} · ${mediaRoutePolicyLine()}`;
  }

  function updateConnectionModeControl() {
    const button = state.controller.routeButton;
    if (!button) return;
    const mode = connectionMode();
    const label = connectionModeControlLabel(mode);
    button.textContent = label;
    button.classList.toggle('isLan', mode === 'lan');
    button.classList.toggle('isProxy', mode === 'proxy');
    button.setAttribute('aria-label', `Connection mode ${label}. Activate to switch mode.`);
    button.setAttribute('aria-pressed', mode === 'auto' ? 'false' : 'true');
    button.title = `Connection mode: ${label}\n${signalingTransportStatusLine()}\n${mediaRoutePolicyLine()}\nActivate to switch AUTO → LAN → WAN.`;
  }

  function restartConnectionForMode(reason = 'mode-change') {
    // Match the original f21 route selector: a route change is a complete
    // signaling restart, not merely a replacement PeerConnection on the old
    // listener socket. This also rebuilds primary and split-audio ICE state.
    clearTimeout(state.reconnectTimer);
    state.signalingAttemptToken += 1;
    const oldSocket = state.ws;
    state.ws = null;
    state.ready = false;
    stopKeepAlive();
    stopSession(false, { stopSplitAudio: true, reason });
    try { if (oldSocket) oldSocket.close(1000, reason); } catch (_) {}
    if (signalingAllowedByStreamState()) connect();
  }

  function setConnectionMode(mode, reason = 'control') {
    const next = normalizeConnectionMode(mode);
    const previous = connectionMode();
    state.connectionModeOverride = next;
    try {
      localStorage.setItem('gstglass-connection-mode', next);
    } catch (_) {}
    updateConnectionModeControl();
    if (next === previous) return next;
    setStatus(`Connection mode: ${connectionModeControlLabel(next)}`, `${signalingTransportStatusLine()} · ${mediaRoutePolicyLine()}`, 'warn');
    log('connection mode changed', previous, '→', next, reason, mediaRoutePolicyLine());
    restartConnectionForMode(`connection-mode:${next}`);
    return next;
  }

  function cycleConnectionMode(reason = 'control') {
    const modes = ['auto', 'lan', 'proxy'];
    const current = modes.indexOf(connectionMode());
    return setConnectionMode(modes[(current + 1) % modes.length], reason);
  }

  function ensurePlayerControls() {
    const ctl = state.controller;
    if (ctl.initialized) return ctl;

    const bar = document.createElement('div');
    bar.id = 'glassControls';
    bar.className = 'glassControls';
    bar.setAttribute('role', 'group');
    bar.setAttribute('aria-label', 'GStreamer Glass playback controls');

    const playButton = document.createElement('button');
    playButton.type = 'button';
    playButton.className = 'glassControlButton glassIconButton glassPlayButton';
    playButton.textContent = '❚❚';
    playButton.title = 'Pause';
    playButton.setAttribute('aria-label', 'Pause');

    const muteButton = document.createElement('button');
    muteButton.type = 'button';
    muteButton.className = 'glassControlButton glassIconButton glassMuteButton';
    muteButton.textContent = '🔊';
    muteButton.title = 'Mute';
    muteButton.setAttribute('aria-label', 'Mute');

    const volumeInput = document.createElement('input');
    volumeInput.type = 'range';
    volumeInput.className = 'glassVolume';
    volumeInput.min = '0';
    volumeInput.max = '1';
    volumeInput.step = '0.01';
    volumeInput.value = String(ctl.volume);
    volumeInput.setAttribute('aria-label', 'Volume');

    const spacer = document.createElement('span');
    spacer.className = 'glassControlSpacer';
    spacer.setAttribute('aria-hidden', 'true');

    const reconnectButton = document.createElement('button');
    reconnectButton.type = 'button';
    reconnectButton.className = 'glassControlButton glassReconnectButton';
    reconnectButton.textContent = '↻ Audio';
    reconnectButton.title = 'Reconnect split audio';
    reconnectButton.setAttribute('aria-label', 'Reconnect split audio');

    const routeButton = document.createElement('button');
    routeButton.type = 'button';
    routeButton.className = 'glassControlButton glassRouteButton';
    routeButton.textContent = 'AUTO';
    routeButton.title = 'Connection mode: AUTO';
    routeButton.setAttribute('aria-label', 'Connection mode AUTO. Activate to switch mode.');
    routeButton.setAttribute('aria-pressed', 'false');

    const logoutButton = document.createElement('button');
    logoutButton.type = 'button';
    logoutButton.className = 'glassControlButton glassLogoutButton';
    logoutButton.textContent = 'Sign out';
    logoutButton.title = 'Sign out of this broadcast';
    logoutButton.setAttribute('aria-label', logoutButton.title);
    logoutButton.hidden = !viewerAuthenticationEnabled() || location.protocol !== 'https:';

    const installButton = document.createElement('button');
    installButton.type = 'button';
    installButton.className = 'glassControlButton glassInstallButton';
    installButton.textContent = '⬇ Install';
    installButton.title = 'Install GStreamer Glass Live';
    installButton.setAttribute('aria-label', installButton.title);
    installButton.hidden = true;

    const zoomButton = document.createElement('button');
    zoomButton.type = 'button';
    zoomButton.className = 'glassControlButton glassZoomButton';
    zoomButton.textContent = '↺ 1.0×';
    zoomButton.title = 'Reset video zoom';
    zoomButton.setAttribute('aria-label', zoomButton.title);
    zoomButton.hidden = true;

    const pinButton = document.createElement('button');
    pinButton.type = 'button';
    pinButton.className = 'glassControlButton glassIconButton glassPinButton';
    pinButton.textContent = '📌';
    pinButton.title = 'Pin diagnostics and controls';
    pinButton.setAttribute('aria-label', pinButton.title);
    pinButton.setAttribute('aria-pressed', 'false');

    const fullscreenCtl = document.createElement('button');
    fullscreenCtl.type = 'button';
    fullscreenCtl.className = 'glassControlButton glassIconButton glassFullscreenButton';
    fullscreenCtl.textContent = '⛶';
    fullscreenCtl.title = 'Enter fullscreen';
    fullscreenCtl.setAttribute('aria-label', fullscreenCtl.title);
    fullscreenCtl.setAttribute('aria-pressed', 'false');

    // Keep diagnostics out of the media control bar. Split-audio/signalling
    // state is already available in the stats/debug overlay and DevTools helpers.
    const status = document.createElement('span');
    status.className = 'glassControlStatus';
    status.hidden = true;
    status.setAttribute('aria-hidden', 'true');
    status.textContent = '';

    bar.append(playButton, muteButton, volumeInput, spacer, reconnectButton, routeButton, logoutButton, installButton, zoomButton, pinButton, fullscreenCtl);
    (playerRoot || document.body).appendChild(bar);

    playButton.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      toggleLogicalPause();
    });
    muteButton.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      toggleLogicalMute();
    });
    volumeInput.addEventListener('input', () => {
      const n = Number.parseFloat(volumeInput.value);
      ctl.volume = Number.isFinite(n) ? Math.max(0, Math.min(n, 1)) : 1;
      if (ctl.volume > 0 && ctl.userMuted) ctl.userMuted = false;
      applyLogicalMediaState('volume');
    });
    reconnectButton.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      recordUserInteraction('reconnect-audio');
      splitDisconnectAudio('manual-reconnect');
      setTimeout(() => splitConnectAudio('manual-reconnect'), 150);
    });
    routeButton.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      recordUserInteraction('connection-mode');
      cycleConnectionMode('media-bar');
    });
    logoutButton.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      if (typeof window.GST_GLASS_LOGOUT === 'function') {
        window.GST_GLASS_LOGOUT();
      }
    });
    installButton.addEventListener('click', async (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      recordUserInteraction('pwa-install');
      const promptEvent = ctl.installPrompt;
      if (!promptEvent) return;
      ctl.installPrompt = null;
      updatePlayerControls();
      try {
        await promptEvent.prompt();
        const choice = await promptEvent.userChoice;
        log('PWA install prompt', choice && choice.outcome ? choice.outcome : 'closed');
      } catch (err) {
        log('PWA install prompt failed', err && err.message ? err.message : err);
      }
      updatePlayerControls();
    });
    zoomButton.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      recordUserInteraction('zoom-reset');
      resetVideoZoom('reset');
    });
    pinButton.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      togglePlayerUiPin();
    });
    fullscreenCtl.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      recordUserInteraction('fullscreen-control');
      togglePlayerFullscreen('controller');
    });

    ctl.initialized = true;
    ctl.bar = bar;
    ctl.playButton = playButton;
    ctl.muteButton = muteButton;
    ctl.volumeInput = volumeInput;
    ctl.spacer = spacer;
    ctl.reconnectButton = reconnectButton;
    ctl.routeButton = routeButton;
    ctl.logoutButton = logoutButton;
    ctl.installButton = installButton;
    ctl.zoomButton = zoomButton;
    ctl.pinButton = pinButton;
    ctl.fullscreenButton = fullscreenCtl;
    ctl.status = status;
    updatePlayerControls();
    return ctl;
  }

  function updatePlayerControls() {
    const ctl = ensurePlayerControls();
    const active = true;
    document.body.classList.toggle('hasGlassControls', active);
    document.body.classList.toggle('splitAudioMode', splitAudioEnabled());
    document.body.classList.toggle('uiPinned', !!ctl.uiPinned);
    if (ctl.bar) ctl.bar.hidden = !active;
    if (ctl.playButton) {
      const showPlay = ctl.userPaused || state.manualResumeRequired;
      ctl.playButton.textContent = showPlay ? '▶' : '❚❚';
      ctl.playButton.title = showPlay ? 'Play' : 'Pause';
      ctl.playButton.setAttribute('aria-label', ctl.playButton.title);
    }
    if (ctl.muteButton) {
      ctl.muteButton.textContent = ctl.userMuted ? '🔇' : '🔊';
      ctl.muteButton.title = ctl.userMuted ? 'Unmute' : 'Mute';
      ctl.muteButton.setAttribute('aria-label', ctl.muteButton.title);
    }
    if (ctl.volumeInput && document.activeElement !== ctl.volumeInput) ctl.volumeInput.value = String(ctl.volume);
    if (ctl.reconnectButton) ctl.reconnectButton.hidden = !splitAudioEnabled();
    updateConnectionModeControl();
    if (ctl.installButton) ctl.installButton.hidden = isStandalonePwa() || !ctl.installPrompt;
    updateVideoZoomControl();
    if (ctl.pinButton) {
      ctl.pinButton.classList.toggle('isPinned', !!ctl.uiPinned);
      ctl.pinButton.title = ctl.uiPinned ? 'Unpin diagnostics and controls' : 'Pin diagnostics and controls';
      ctl.pinButton.setAttribute('aria-label', ctl.pinButton.title);
      ctl.pinButton.setAttribute('aria-pressed', ctl.uiPinned ? 'true' : 'false');
    }
    setFullscreenState();
    if (ctl.status) {
      ctl.status.textContent = '';
      ctl.status.hidden = true;
    }
  }

  function invalidateMediaPlay(kind) {
    if (kind === 'video' || kind === 'audio') {
      state.mediaPlayAttempt[kind] = (state.mediaPlayAttempt[kind] || 0) + 1;
    }
  }

  function expectedPlayInterruption(err) {
    const name = String(err && err.name ? err.name : '');
    const message = String(err && err.message ? err.message : err || '').toLowerCase();
    return name === 'AbortError' || message.includes('interrupted by a call to pause') || message.includes('interrupted by a new load request');
  }

  function requestMediaPlayback(element, kind, reason = 'state', retry = 0) {
    if (!element || !element.srcObject || state.controller.userPaused) return;
    if (!element.paused && element.readyState >= 2) return;

    const source = element.srcObject;
    const token = (state.mediaPlayAttempt[kind] || 0) + 1;
    state.mediaPlayAttempt[kind] = token;

    let promise;
    try {
      promise = element.play();
    } catch (err) {
      promise = Promise.reject(err);
    }

    Promise.resolve(promise).catch((err) => {
      const stale = state.mediaPlayAttempt[kind] !== token || element.srcObject !== source || state.controller.userPaused;
      if (stale) return;

      if (expectedPlayInterruption(err)) {
        // pause()/srcObject teardown can legitimately abort an in-flight play().
        // Retry once only if this is still the active source and playback is
        // still desired; never present an autoplay prompt for this race.
        if (retry < 1) {
          setTimeout(() => {
            if (state.mediaPlayAttempt[kind] === token && element.srcObject === source && !state.controller.userPaused && element.paused) {
              requestMediaPlayback(element, kind, `${reason}:abort-retry`, retry + 1);
            }
          }, 80);
        }
        if (jbufDebugEnabled()) log(`${kind} play interrupted`, reason, err && err.message ? err.message : err);
        return;
      }

      const name = String(err && err.name ? err.name : '');
      const message = err && err.message ? err.message : String(err);
      if (name === 'NotAllowedError') {
        setStatus(kind === 'audio' ? 'Click to enable audio' : 'Click to play', message, 'warn');
      } else {
        setStatus(kind === 'audio' ? 'Audio playback error' : 'Video playback error', message, 'bad');
      }
    });
  }

  function applyLogicalMediaState(reason = 'state') {
    const ctl = state.controller;
    ctl.lastAppliedAt = Date.now();
    const splitLike = logicalSplitControlsActive();
    const vol = Math.max(0, Math.min(Number(ctl.volume) || 0, 1));

    try { video.volume = vol; } catch (_) {}
    try { audio.volume = vol; } catch (_) {}

    if (splitLike) {
      // In split/decoupled mode the visible video element is not the authority
      // for audio. Keep it muted and drive audible state through the separate
      // audio element. Native video mute/pause controls cannot see that element.
      video.muted = true;
      video.controls = false;
      audio.muted = !!ctl.userMuted;
    } else {
      video.controls = false;
      video.muted = !!ctl.userMuted;
      audio.muted = true;
    }

    if (ctl.userPaused) {
      invalidateMediaPlay('video');
      invalidateMediaPlay('audio');
      try { video.pause(); } catch (_) {}
      try { audio.pause(); } catch (_) {}
    } else {
      requestMediaPlayback(video, 'video', reason);
      if (splitLike) requestMediaPlayback(audio, 'audio', reason);
    }

    updatePlayerControls();
    syncScreenWakeLock(`media-state:${reason}`, reason === 'gesture' || reason === 'pause-toggle');
  }

  function toggleLogicalPause() {
    if (state.manualResumeRequired && state.streamStateKnown && !state.intentionalStopMarker) {
      state.manualResumeRequired = false;
      state.stopResumeLocked = false;
      state.reconnectAttempts = 0;
      state.splitAudio.reconnectAttempts = 0;
      noteUserGesture(false);
      setStatus('Connecting', 'Starting signaling after user request…', 'warn');
      connect();
      reconcileSplitAudio('manual-play');
      updatePlayerControls();
      return;
    }
    state.controller.userPaused = !state.controller.userPaused;
    if (!state.controller.userPaused) noteUserGesture(false);
    applyLogicalMediaState('pause-toggle');
  }

  function toggleLogicalMute() {
    state.controller.userMuted = !state.controller.userMuted;
    applyLogicalMediaState('mute-toggle');
  }

  function togglePlayerUiPin() {
    const ctl = state.controller;
    ctl.uiPinned = !ctl.uiPinned;
    document.body.classList.toggle('uiPinned', ctl.uiPinned);
    if (ctl.uiPinned) {
      if (playerUiHideTimer) clearTimeout(playerUiHideTimer);
      playerUiHideTimer = null;
      document.body.classList.add('uiActive', 'showStatus');
    } else {
      document.body.classList.remove('uiActive');
      revealPlayerUi('unpin');
    }
    updatePlayerControls();
  }

  function clearSplitAudioMedia(reason = 'clear') {
    invalidateMediaPlay('audio');
    try { audio.pause(); } catch (_) {}
    if (state.audioStream) {
      try { state.audioStream.getTracks().forEach((track) => state.audioStream.removeTrack(track)); } catch (_) {}
    }
    audio.srcObject = null;
    state.audioStream = null;
    if (jbufDebugEnabled()) log('split audio media cleared', reason);
    updatePlayerControls();
  }

  function send(obj, allowBeforeReady = false) {
    if (!state.ws || state.ws.readyState !== WebSocket.OPEN) return false;
    if (!state.ready && !allowBeforeReady && obj.type !== 'setPeerStatus') return false;
    state.ws.send(JSON.stringify(obj));
    return true;
  }

  function stopKeepAlive() {
    if (state.keepAliveTimer) clearInterval(state.keepAliveTimer);
    state.keepAliveTimer = null;
  }

  function startKeepAlive() {
    stopKeepAlive();
    const interval = keepAliveMs();
    if (!interval) return;
    state.keepAliveCount = 0;
    state.lastKeepAliveAt = 0;
    state.keepAliveTimer = setInterval(() => {
      if (!state.ws || state.ws.readyState !== WebSocket.OPEN) return;
      state.keepAliveCount += 1;
      state.lastKeepAliveAt = performance.now();
      send({ type: 'list' }, true);
      if (state.keepAliveCount % 4 === 0) send({ type: 'listConsumers' }, true);
    }, interval);
  }

  function makeRtcConfig() {
    const mode = connectionMode();
    const relayUrl = turnUrl();
    const iceServers = [];
    if (mode !== 'lan') {
      const stun = stunUrl();
      if (stun) iceServers.push({ urls: stun });
    }
    if (relayUrl) {
      const relay = { urls: relayUrl };
      const username = String(query('turnUser') || query('turnUsername') || configValue('turnUsername', '') || '').trim();
      const credential = String(query('turnCredential') || query('turnPassword') || configValue('turnCredential', '') || '').trim();
      if (username) relay.username = username;
      if (credential) relay.credential = credential;
      iceServers.push(relay);
    }
    const config = { iceServers };
    // webrtcsink doesn't gather its own srflx candidate (confirmed repeatedly
    // in testing -- it only ever offers host candidates for itself), so on a
    // genuine WAN/remote client its private host address is the *only*
    // non-relay option it has to offer, and that's unreachable from outside
    // its own LAN. Relay is therefore not a preference here, it's the only
    // path that can work at all for a remote viewer in PROXY mode -- confirmed
    // by testing: removing this forcing broke external connectivity on WAN.
    // (Known remaining gap: this can still fail on networks where the relay
    // allocation itself doesn't work, e.g. some mobile carriers -- that's a
    // TURN-server/reachability question, not something to fix by removing
    // this policy again.)
    if (mode === 'proxy' && relayUrl) config.iceTransportPolicy = 'relay';
    return config;
  }

  function normalizePeer(peer, assumedRole) {
    if (!peer || typeof peer !== 'object') return null;
    const id = peer.peerId || peer.id;
    if (!id || id === state.peerId) return null;
    let roles = Array.isArray(peer.roles) ? [...peer.roles] : [];
    if (assumedRole && !roles.includes(assumedRole)) roles.push(assumedRole);
    return { id, roles, meta: peer.meta || {} };
  }

  function addProducer(peerLike, assumedRole = 'producer') {
    const peer = normalizePeer(peerLike, assumedRole);
    if (!peer || !peer.roles.includes('producer')) return;
    state.producers.set(peer.id, peer);
    autoStartFirstProducer();
  }

  function parseProducerList(msg) {
    state.producers.clear();
    const producers = msg.producers || msg.peers || [];
    if (Array.isArray(producers)) {
      producers.forEach((p) => addProducer(p, 'producer'));
    } else if (producers && typeof producers === 'object') {
      Object.entries(producers).forEach(([id, value]) => addProducer({ peerId: id, ...(value || {}) }, 'producer'));
    }
    if (!state.started && !state.producers.size) {
      setStatus('Waiting for stream', 'Connected to signaling, but no producer is listed yet.', 'warn');
    }
  }

  function autoStartFirstProducer() {
    if (state.started || state.pc || state.sessionId || !state.producers.size) return;
    const selected = selectProducerForKind(state.producers, 'video');
    if (selected) startConsumer(selected.id);
    else if (sharedSignalingEnabled()) setStatus('Waiting for video', 'Shared signaling connected; waiting for the named video producer.', 'warn');
  }

  const RECONNECT_DELAYS_MS = [3000, 6000, 12000, 24000, 30000];

  function scheduleReconnect() {
    if (!signalingAllowedByStreamState()) return;
    clearTimeout(state.reconnectTimer);
    state.reconnectTimer = null;
    if (state.reconnectAttempts < RECONNECT_DELAYS_MS.length) {
      const delay = RECONNECT_DELAYS_MS[state.reconnectAttempts];
      state.reconnectAttempts += 1;
      state.reconnectTimer = setTimeout(connect, delay);
    } else {
      state.manualResumeRequired = true;
      setStatus('Available', 'Automatic reconnect stopped. Press Play to try again.', 'good');
      updatePlayerControls();
    }
  }

  function connect() {
    if (!signalingAllowedByStreamState()) return false;
    clearTimeout(state.reconnectTimer);
    const token = ++state.signalingAttemptToken;
    const candidates = primarySignalingCandidates();
    state.signalingCandidates = [...candidates];
    let candidateIndex = 0;

    const scheduleFullRetry = (detail) => {
      if (token !== state.signalingAttemptToken) return;
      state.ws = null;
      state.ready = false;
      setStatus('Signaling unavailable', detail || 'All signaling routes failed. Retrying…', 'bad');
      scheduleReconnect();
    };

    const tryNextCandidate = (previousFailure = '') => {
      if (token !== state.signalingAttemptToken) return;
      if (candidateIndex >= candidates.length) {
        scheduleFullRetry(previousFailure || 'No usable signaling endpoint is configured.');
        return;
      }

      const url = candidates[candidateIndex++];
      const route = signalingRouteForUrl(url, 'video');
      state.signalingRoute = route;
      state.signalingUrl = url;
      updatePlayerControls();

      const routeLabel = route === 'proxy' ? 'proxy' : (route === 'direct' && connectionMode() === 'auto' ? 'direct fallback' : route);
      const prefix = candidateIndex > 1 && previousFailure ? `${previousFailure} ` : '';
      setStatus(`Connecting via ${routeLabel}…`, `${prefix}${url}`, 'warn');

      let ws;
      let opened = false;
      let advanced = false;
      let timer = null;

      const advance = (reason) => {
        if (advanced || opened || token !== state.signalingAttemptToken) return;
        advanced = true;
        if (timer) clearTimeout(timer);
        if (state.ws === ws) state.ws = null;
        try { if (ws && ws.readyState < WebSocket.CLOSING) ws.close(); } catch (_) {}
        if (candidateIndex < candidates.length) {
          const next = candidates[candidateIndex];
          log('primary signaling route failed; trying fallback', url, '=>', next, reason);
          setTimeout(() => tryNextCandidate(`${routeLabel} failed; trying fallback.`), 0);
        } else {
          log('primary signaling routes exhausted', candidates, reason);
          scheduleFullRetry(`${routeLabel} failed: ${reason}`);
        }
      };

      try {
        ws = new WebSocket(url);
        state.ws = ws;
      } catch (err) {
        advance(err && err.message ? err.message : String(err));
        return;
      }

      timer = setTimeout(() => {
        advance(`connect timeout after ${signalingConnectTimeoutMs()}ms`);
      }, signalingConnectTimeoutMs());

      ws.addEventListener('open', () => {
        if (token !== state.signalingAttemptToken || state.ws !== ws) {
          try { ws.close(); } catch (_) {}
          return;
        }
        opened = true;
        if (timer) clearTimeout(timer);
        state.reconnectAttempts = 0;
        const connectedDetail = route === 'direct' && connectionMode() === 'auto'
          ? `Direct signaling fallback active: ${url}`
          : 'Waiting for producer…';
        setStatus(route === 'direct' && connectionMode() === 'auto' ? 'Connected (direct fallback)' : 'Connected', connectedDetail, 'good');
        startKeepAlive();
        reconcileSplitAudio('primary-ws-open');
        updatePlayerControls();
      });

      ws.addEventListener('close', (ev) => {
        if (timer) clearTimeout(timer);
        if (token !== state.signalingAttemptToken || state.ws !== ws) return;
        if (!opened) {
          advance(`closed before open (${ev.code || 0}${ev.reason ? `: ${ev.reason}` : ''})`);
          return;
        }
        state.ws = null;
        state.ready = false;
        stopKeepAlive();
        stopSession(false, { stopSplitAudio: true, reason: 'primary-ws-close' });
        // An established signaling path disappearing invalidates the cached
        // running state. Do not touch any signaling URL again until a fresh
        // state-file read explicitly permits it.
        state.streamStateKnown = false;
        setStatus('Checking stream state', 'Signaling closed; waiting for state.json.', 'warn');
        fetchStreamStopMarker();
      });

      ws.addEventListener('error', (ev) => {
        if (token !== state.signalingAttemptToken || state.ws !== ws) return;
        log('primary signaling error', route, url, ev);
        if (opened) setStatus('Signaling error', `${routeLabel}: ${url}`, 'bad');
      });

      ws.addEventListener('message', (ev) => {
        if (token !== state.signalingAttemptToken || state.ws !== ws) return;
        let msg;
        try { msg = JSON.parse(ev.data); } catch (err) { log('bad message', err, ev.data); return; }
        handleMessage(msg);
      });
    };

    tryNextCandidate();
  }

  function mediaStreamHasTrack(stream, track) {
    return !!(stream && track && stream.getTracks().some((existing) => existing.id === track.id));
  }

  function resetRenderedMedia(options = {}) {
    const preserveSplitAudio = !!(options && options.preserveSplitAudio && splitAudioEnabled());
    invalidateMediaPlay('video');
    try { video.pause(); } catch (_) {}
    video.srcObject = null;
    state.videoStream = null;
    if (!preserveSplitAudio) {
      invalidateMediaPlay('audio');
      try { audio.pause(); } catch (_) {}
      audio.srcObject = null;
      state.audioStream = null;
    }
    updatePlayerControls();
  }

  function ensureDecoupledStreams() {
    if (!state.videoStream) state.videoStream = new MediaStream();
    if (!state.audioStream) state.audioStream = new MediaStream();
    if (video.srcObject !== state.videoStream) video.srcObject = state.videoStream;
    if (audio.srcObject !== state.audioStream) audio.srcObject = state.audioStream;
    // Keep video media element audio-muted in decoupled/split mode; audio has its own element.
    applyLogicalMediaState('ensure-decoupled-streams');
    return { videoStream: state.videoStream, audioStream: state.audioStream };
  }

  function playRenderedMedia(kind) {
    if (state.controller.userPaused) {
      updatePlayerControls();
      return;
    }
    applyLogicalMediaState(`play-rendered-${kind || 'media'}`);
  }

  function attachTrackToPlayer(track, eventStream = null, reason = 'track') {
    if (!track) return;
    if (track.kind === 'video') markTrackForRealtimeDecode(track);
    const mode = playerAvRenderMode();
    state.activeRenderMode = mode;

    const forceSeparateAudio = splitAudioEnabled() && track.kind === 'audio';

    if (!effectiveDecoupledRenderMode() && !forceSeparateAudio) {
      // Always build one local combined MediaStream. With split MSIDs, each ontrack
      // event carries a different event.streams[0], so assigning eventStream directly
      // would replace video with the later audio-only stream instead of recombining A/V.
      if (!state.videoStream) state.videoStream = new MediaStream();
      if (!mediaStreamHasTrack(state.videoStream, track)) state.videoStream.addTrack(track);
      if (video.srcObject !== state.videoStream) video.srcObject = state.videoStream;
      audio.srcObject = null;
      state.audioStream = null;
      playRenderedMedia(track.kind);
      return;
    }

    const streams = ensureDecoupledStreams();
    if (track.kind === 'video') {
      if (!mediaStreamHasTrack(streams.videoStream, track)) streams.videoStream.addTrack(track);
    } else if (track.kind === 'audio') {
      if (!mediaStreamHasTrack(streams.audioStream, track)) streams.audioStream.addTrack(track);
    }

    playRenderedMedia(track.kind);
    if (track.kind === 'video') scheduleFullscreenRenderRecovery(`track-attach:${reason}`, 120);
    if (jbufDebugEnabled()) log('render attach', mode, track.kind, reason);
  }

  function refreshRenderedTracks(reason = 'refresh') {
    const mode = playerAvRenderMode();
    if (mode === state.activeRenderMode && video.srcObject) return;
    if (!state.pc || typeof state.pc.getReceivers !== 'function') return;
    const tracks = state.pc.getReceivers().map((receiver) => receiver && receiver.track).filter(Boolean);
    if (splitAudioEnabled() && state.splitAudio.pc && typeof state.splitAudio.pc.getReceivers === 'function') {
      state.splitAudio.pc.getReceivers().forEach((receiver) => {
        if (receiver && receiver.track) tracks.push(receiver.track);
      });
    }
    resetRenderedMedia();
    state.activeRenderMode = mode;

    if (!effectiveDecoupledRenderMode()) {
      const stream = new MediaStream();
      tracks.forEach((track) => stream.addTrack(track));
      video.srcObject = stream;
      audio.srcObject = null;
      playRenderedMedia('refresh');
    } else {
      tracks.forEach((track) => attachTrackToPlayer(track, null, reason));
    }

    if (jbufDebugEnabled()) log('render mode refreshed', mode, reason);
  }

  async function startConsumer(peerId) {
    if (!signalingAllowedByStreamState()) return false;
    if (!state.ws || state.ws.readyState !== WebSocket.OPEN) return connect();
    // Only a genuinely fresh start (not our own retry-for-external-candidate
    // call, which sets proxyPairRetrying before invoking this) gets a new
    // retry budget -- otherwise every retry would reset its own cap to zero.
    if (!state.proxyPairRetrying) state.proxyPairRetryCount = 0;
    stopSession(false, { preserveSplitAudio: true });
    state.remotePeerId = peerId;
    state.pendingIce = [];
    state.pendingRemoteIce = [];
    state.started = true;
    beginJbufWatchdogWarmup('primary-start-consumer');
    setStatus('Starting stream…', `Producer ${shortId(peerId)}`, 'warn');

    const pc = new RTCPeerConnection(makeRtcConfig());
    state.pc = pc;
    window.pc = pc;

    pc.addEventListener('connectionstatechange', () => {
      log('pc', pc.connectionState);
      if (pc.connectionState === 'connected') setStatus('Live', state.lastIceProtocol || 'WebRTC connected', 'good');
      if (['failed', 'disconnected', 'closed'].includes(pc.connectionState)) setStatus('Connection interrupted', pc.connectionState, 'bad');
    });

    pc.addEventListener('iceconnectionstatechange', () => {
      log('ice', pc.iceConnectionState);
      if (['connected', 'completed'].includes(pc.iceConnectionState)) setStatus('Live', state.lastIceProtocol || 'ICE connected', 'good');
      if (['failed', 'disconnected'].includes(pc.iceConnectionState)) setStatus('ICE interrupted', pc.iceConnectionState, 'bad');
    });

    pc.addEventListener('icecandidate', (ev) => {
      if (!ev.candidate) return;
      noteOwnPublicIpFromCandidate(ev.candidate.candidate);
      if (connectionMode() === 'proxy' && isLocalOnlyHostIceCandidateLine(ev.candidate.candidate)) return;
      const candidate = applyIceRoutePolicyToCandidate(ev.candidate, 'primary local');
      if (state.sessionId) send({ type: 'peer', sessionId: state.sessionId, ice: candidate }, true);
      else state.pendingIce.push(candidate);
    });

    pc.addEventListener('track', (ev) => {
      beginJbufWatchdogWarmup(`primary-track:${ev.track && ev.track.kind ? ev.track.kind : 'media'}`);
      applyReceiverJitter(ev.receiver, 'track');
      setTimeout(() => applyReceiverJitter(ev.receiver, 'track +250ms', null, true), 250);
      setTimeout(() => applyReceiverJitter(ev.receiver, 'track +1000ms', null, true), 1000);
      const stream = ev.streams && ev.streams[0] ? ev.streams[0] : null;
      attachTrackToPlayer(ev.track, stream, 'pc track');
      document.body.classList.add('playing');
      setFullscreenState();
      setStatus('Live', `${ev.track.kind} track received · ${playerConfigLine()}${adaptiveJitterEnabled() ? ' · adaptive' : ''}`, 'good');
      applyLogicalMediaState('primary-track');
      attemptAutoFullscreen();
    });

    if (state.jitterApplyTimer) clearInterval(state.jitterApplyTimer);
    state.jitterApplyTimer = setInterval(() => applyAllReceiverJitter('periodic', true), 1000);

    startStatsTimer();
    send({ type: 'startSession', peerId }, true);
  }

  function flushIce() {
    if (!state.sessionId || !state.pendingIce.length) return;
    state.pendingIce.splice(0).forEach((ice) => send({ type: 'peer', sessionId: state.sessionId, ice }, true));
  }

  async function handleRemoteSdp(sdp) {
    if (!state.pc) throw new Error('received SDP without active peer connection');
    const pc = state.pc;
    const rawDesc = typeof sdp === 'string' ? { type: 'offer', sdp } : sdp;
    const mappedDesc = injectMappedIceCandidatesIntoDescription(rawDesc, 'primary remote');
    const routedDesc = applyIceRoutePolicyToDescription(mappedDesc, 'primary remote');
    const desc = rewriteRemoteMediaStreamIds(routedDesc, 'primary remote');
    await pc.setRemoteDescription(desc);
    if (state.pc !== pc) return;
    while (state.pendingRemoteIce.length) {
      try { await pc.addIceCandidate(state.pendingRemoteIce.shift()); }
      catch (err) { log('queued addIceCandidate failed', err); }
    }
    if (desc.type === 'offer') {
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      const local = applyIceRoutePolicyToDescription(pc.localDescription, 'primary outbound', true);
      send({
        type: 'peer',
        sessionId: state.sessionId,
        sdp: local.toJSON ? local.toJSON() : { type: local.type, sdp: local.sdp }
      }, true);
    }
  }

  async function handleRemoteIce(ice) {
    if (!state.pc || !ice) return;
    const routedCandidates = expandRemoteIceCandidates(ice, 'primary remote')
      .map((candidate) => applyIceRoutePolicyToCandidate(candidate, 'primary remote'))
      .filter((candidate) => candidate !== null);
    // null means "rejected private candidate", not "end of candidates" --
    // addIceCandidate(null) is a real, distinct signal to the ICE agent and
    // must only fire for an actual end-of-candidates marker.
    if (!routedCandidates.length) return;
    if (!state.pc.remoteDescription) {
      state.pendingRemoteIce.push(...routedCandidates);
      return;
    }
    for (const routedIce of routedCandidates) {
      try { await state.pc.addIceCandidate(routedIce && routedIce.candidate ? routedIce : null); }
      catch (err) { log('addIceCandidate failed', err); }
    }
  }

  function stopStatsTimer() {
    if (state.statsTimer) clearInterval(state.statsTimer);
    state.statsTimer = null;
  }

  function statsOverlayEnabled() {
    const raw = query('stats');
    if (raw !== null) return !['0', 'false', 'off', 'no'].includes(String(raw).toLowerCase());
    return !!configValue('statsOverlay', true);
  }

  function fmtMs(secondsOrMs, alreadyMs = false) {
    const ms = alreadyMs ? Number(secondsOrMs) : Number(secondsOrMs) * 1000;
    if (!Number.isFinite(ms)) return '—';
    if (ms < 10) return `${ms.toFixed(1)}ms`;
    return `${Math.round(ms)}ms`;
  }

  function selectedCandidatePair(stats) {
    let transportPairId = '';
    let legacySelected = null;
    let nominated = null;
    let fallback = null;
    let fallbackScore = -1;

    stats.forEach((report) => {
      if (report.type === 'transport' && report.selectedCandidatePairId) {
        transportPairId = report.selectedCandidatePairId;
      }
      if (report.type !== 'candidate-pair') return;
      if (report.selected === true) legacySelected = report;
      if (!nominated && report.nominated === true && report.state === 'succeeded') nominated = report;
      if (report.state === 'succeeded') {
        const score = (Number(report.bytesReceived) || 0) + (Number(report.bytesSent) || 0);
        if (score > fallbackScore) {
          fallback = report;
          fallbackScore = score;
        }
      }
    });

    return (transportPairId && stats.get(transportPairId)) || legacySelected || nominated || fallback;
  }

  function candidatePairProtocol(stats, pair) {
    if (!pair) return '';
    const local = pair.localCandidateId ? stats.get(pair.localCandidateId) : null;
    const remote = pair.remoteCandidateId ? stats.get(pair.remoteCandidateId) : null;
    return String((local && (local.protocol || local.relayProtocol)) || (remote && (remote.protocol || remote.relayProtocol)) || '').toUpperCase();
  }

  function candidatePairRoute(stats, pair) {
    if (!pair) return '';
    const local = pair.localCandidateId ? stats.get(pair.localCandidateId) : null;
    const remote = pair.remoteCandidateId ? stats.get(pair.remoteCandidateId) : null;
    function label(candidate) {
      if (!candidate) return '';
      const type = String(candidate.candidateType || '').toLowerCase();
      const address = candidate.address || candidate.ip || candidate.ipAddress || '';
      const port = candidate.port || candidate.portNumber || '';
      const endpoint = address ? `${address}${port ? `:${port}` : ''}` : '';
      return [type, endpoint].filter(Boolean).join(' ');
    }
    const left = label(local);
    const right = label(remote);
    return left || right ? `${left || '?'} ↔ ${right || '?'}` : '';
  }

  function candidatePairPathKind(stats, pair) {
    if (!pair) return '';
    const local = pair.localCandidateId ? stats.get(pair.localCandidateId) : null;
    const remote = pair.remoteCandidateId ? stats.get(pair.remoteCandidateId) : null;
    const candidates = [local, remote].filter(Boolean);
    const types = candidates.map((candidate) => String(candidate.candidateType || '').toLowerCase());
    if (types.includes('relay')) return 'TURN RELAY';
    // A peer-reflexive candidate discovered on a private address (multi-homed
    // machine/virtual adapter: a check arrives on a different local interface
    // than the one a candidate was advertised for) is a local-only path just
    // like a private host candidate, not a real external one. Conversely, a
    // host candidate containing a public address is a valid external path and
    // must not be mislabeled as a LAN fallback. Match routeIcePriority.
    const isLocalOnly = (candidate) => {
      const type = String(candidate.candidateType || '').toLowerCase();
      const address = String(candidate.address || candidate.ip || candidate.ipAddress || '');
      return (type === 'host' && (!address || isPrivateIceAddress(address)))
        || (type === 'prflx' && isPrivateIceAddress(address));
    };
    if (candidates.length && candidates.every(isLocalOnly)) {
      return connectionMode() === 'proxy' ? 'PROXY FALLBACK: DIRECT LAN MEDIA' : 'DIRECT LAN';
    }
    return 'DIRECT P2P';
  }

  function candidatePairRtt(pair) {
    if (!pair) return NaN;
    if (Number.isFinite(pair.currentRoundTripTime)) return pair.currentRoundTripTime;
    if (Number.isFinite(pair.totalRoundTripTime) && Number.isFinite(pair.responsesReceived) && pair.responsesReceived > 0) {
      return pair.totalRoundTripTime / pair.responsesReceived;
    }
    return NaN;
  }

  const PROXY_PAIR_RETRY_LIMIT = 4;
  // Stats tick is ~1s (see startStatsTimer); require this many consecutive
  // ticks on a local pair before rerolling, instead of bailing on the very
  // first tick after connecting.
  const PROXY_PAIR_GRACE_TICKS = 5;

  // We can't force webrtcsink's own ICE agent to nominate a particular pair,
  // so this is a verify-and-retry backstop instead of trying to influence the
  // nomination in advance: candidatePairPathKind() already detects "we ended
  // up on a private LAN pair anyway" (it's what produces the PROXY FALLBACK:
  // DIRECT LAN MEDIA status text) -- here that detection actually does
  // something instead of only being cosmetic. A fresh session re-runs the
  // whole gathering/nomination race, giving another roll of the dice at
  // landing on an external pair, bounded so a topology where the external
  // path is genuinely unreachable still ends up connected (just local).
  function retryPrimaryForExternalCandidate() {
    if (state.proxyPairRetrying) return;
    const peerId = state.remotePeerId;
    if (!peerId) return;
    if (state.proxyPairRetryCount >= PROXY_PAIR_RETRY_LIMIT) return;
    state.proxyPairRetryCount += 1;
    state.proxyPairRetrying = true;
    state.proxyPairLocalTicks = 0;
    const attempt = state.proxyPairRetryCount;
    log(`proxy mode nominated a private LAN pair; retrying for an external candidate (${attempt}/${PROXY_PAIR_RETRY_LIMIT})`);
    setStatus('Retrying for external route', `Nominated pair was local; attempt ${attempt}/${PROXY_PAIR_RETRY_LIMIT}`, 'warn');
    stopSession(false, { preserveSplitAudio: true });
    setTimeout(() => {
      // startConsumer's own reset guard checks this flag synchronously at
      // entry -- it must still be true when startConsumer is invoked, or the
      // retry counter gets wiped back to 0 on every single attempt and the
      // cap never actually engages (clearing it first was the bug).
      startConsumer(peerId);
      state.proxyPairRetrying = false;
    }, 300);
  }

  function retrySplitAudioForExternalCandidate() {
    const sa = state.splitAudio;
    if (sa.proxyPairRetrying) return;
    const peerId = sa.remotePeerId;
    if (!peerId) return;
    if (sa.proxyPairRetryCount >= PROXY_PAIR_RETRY_LIMIT) return;
    sa.proxyPairRetryCount += 1;
    sa.proxyPairRetrying = true;
    sa.proxyPairLocalTicks = 0;
    const attempt = sa.proxyPairRetryCount;
    log(`proxy mode nominated a private LAN pair for split audio; retrying for an external candidate (${attempt}/${PROXY_PAIR_RETRY_LIMIT})`);
    splitStopSession(false);
    setTimeout(() => {
      splitStartConsumer(peerId);
      sa.proxyPairRetrying = false;
    }, 300);
  }

  function measuredInboundBitrate(scopedReports) {
    let totalBps = 0;
    let measured = 0;
    const activeKeys = new Set();
    (scopedReports || []).forEach((entry) => {
      const report = entry && entry.report;
      if (!report || !Number.isFinite(report.bytesReceived)) return;
      const key = `${entry.scope || 'pc'}:${report.id || report.ssrc || report.kind || measured}`;
      const timestamp = Number.isFinite(report.timestamp) ? report.timestamp : performance.now();
      activeKeys.add(key);
      const previous = state.inboundBitrateSamples.get(key);
      if (previous && report.bytesReceived >= previous.bytes && timestamp > previous.timestamp) {
        const seconds = (timestamp - previous.timestamp) / 1000;
        if (seconds > 0) {
          totalBps += ((report.bytesReceived - previous.bytes) * 8) / seconds;
          measured += 1;
        }
      }
      state.inboundBitrateSamples.set(key, { bytes: report.bytesReceived, timestamp });
    });
    [...state.inboundBitrateSamples.keys()].forEach((key) => {
      if (!activeKeys.has(key)) state.inboundBitrateSamples.delete(key);
    });
    return measured > 0 ? totalBps : NaN;
  }

  function fmtBitrate(bitsPerSecond) {
    if (!Number.isFinite(bitsPerSecond)) return 'bitrate —';
    if (bitsPerSecond >= 1000000) return `RX ${(bitsPerSecond / 1000000).toFixed(2)} Mbps`;
    return `RX ${Math.round(bitsPerSecond / 1000)} kbps`;
  }

  function renderStatsOverlay(lines) {
    if (!statsOverlay) return;
    if (!statsOverlayEnabled()) {
      statsOverlay.style.display = 'none';
      return;
    }
    statsOverlay.style.display = '';
    statsOverlay.textContent = lines.filter(Boolean).join('\n');
  }

  function handleJbufWatchdog(kind, windowMs, avgMs) {
    const mode = jbufWatchdogMode();
    if (mode === 'Off') return '';
    const maxMs = jbufMaxMs();
    const value = Number.isFinite(windowMs) && windowMs > 0 ? windowMs : avgMs;
    if (!Number.isFinite(value)) return '';
    const key = kind || 'media';
    const warmupLeft = jbufWatchdogWarmupRemainingMs();
    if (warmupLeft > 0) {
      if (!state.jbufHighTicksByKind) state.jbufHighTicksByKind = {};
      state.jbufHighTicksByKind[key] = 0;
      state.jbufHighTicks = 0;
      state.jbufReconnectPending = false;
      return '';
    }
    if (!state.jbufHighTicksByKind) state.jbufHighTicksByKind = {};
    if (value > maxMs) state.jbufHighTicksByKind[key] = (state.jbufHighTicksByKind[key] || 0) + 1;
    else state.jbufHighTicksByKind[key] = 0;
    state.jbufHighTicks = state.jbufHighTicksByKind[key] || 0;
    if (state.jbufHighTicks <= 0) return '';
    const label = `${String(key).toUpperCase()} JBUF RISING ${Math.round(value)}ms > ${maxMs}ms (${state.jbufHighTicks}/${jbufTrendWindowTicks()})`;
    setStatus('JBUF rising', label, 'warn');
    if (mode === 'Auto-reconnect viewer' && state.jbufHighTicks >= jbufTrendWindowTicks() && !state.jbufReconnectPending) {
      const peerId = state.remotePeerId;
      state.jbufReconnectPending = true;
      log('jbuf watchdog reconnect', label, peerId ? shortId(peerId) : 'no producer');
      setStatus('Reconnecting viewer', label, 'warn');
      setTimeout(() => {
        state.jbufReconnectPending = false;
        if (peerId && state.ws && state.ws.readyState === WebSocket.OPEN) {
          stopSession(true);
          startConsumer(peerId);
        }
      }, 250);
    }
    return label;
  }

  function getInboundJbufLine(kind, inbound) {
    const target = (state.currentJitterMsByKind && Number.isFinite(state.currentJitterMsByKind[kind])) ? state.currentJitterMsByKind[kind] : receiverJitterMs(kind);
    if (!inbound) return `${kind} jbuf — target ${target}ms`;

    if (Number.isFinite(inbound.jitterBufferDelay) && Number.isFinite(inbound.jitterBufferEmittedCount) && inbound.jitterBufferEmittedCount > 0) {
      const avg = inbound.jitterBufferDelay / inbound.jitterBufferEmittedCount;
      const avgMs = avg * 1000;
      let windowMs = NaN;
      const lastJbuf = state.lastJbufStatsByKind[kind];
      if (lastJbuf && inbound.jitterBufferEmittedCount > lastJbuf.count) {
        const dDelay = Math.max(0, inbound.jitterBufferDelay - lastJbuf.delay);
        const dCount = Math.max(1, inbound.jitterBufferEmittedCount - lastJbuf.count);
        windowMs = (dDelay / dCount) * 1000;
      }
      state.lastJbufStatsByKind[kind] = { delay: inbound.jitterBufferDelay, count: inbound.jitterBufferEmittedCount };
      state.latestJbufStatsByKind[kind] = { avgMs, windowMs, valueMs: Number.isFinite(windowMs) ? windowMs : avgMs, target, updatedAt: performance.now() };
      const watchdog = handleJbufWatchdog(kind, windowMs, avgMs);
      const windowText = Number.isFinite(windowMs) ? ` win ${fmtMs(windowMs, true)}` : '';
      const warmupLeft = jbufWatchdogWarmupRemainingMs();
      const warmupText = (jbufWatchdogMode() !== 'Off' && warmupLeft > 0) ? ` warmup ${Math.ceil(warmupLeft / 1000)}s` : '';
      const warnText = watchdog ? ' ⚠' : '';
      return `${kind} jbuf avg ${fmtMs(avg)}${windowText} target ${target}ms max ${jbufMaxMs()}ms${warmupText}${warnText}`;
    }

    return `${kind} jbuf target ${target}ms`;
  }

  function splitAudioSoftRecover(reason = 'watchdog') {
    if (!splitPlayerSyncEnabled()) return false;
    const sa = state.splitAudio;
    const now = performance.now();
    if (now - (sa.lastRecoverAt || 0) < 3000) return false;
    sa.lastRecoverAt = now;
    sa.recoveryCount = (sa.recoveryCount || 0) + 1;
    sa.status = `soft-recover:${reason}`;
    sa.syncHealth = `soft recover ${reason}`;
    try {
      const stream = audio.srcObject;
      if (stream) {
        invalidateMediaPlay('audio');
        audio.pause();
        audio.srcObject = null;
        try { audio.load(); } catch (_) {}
        audio.srcObject = stream;
      }
      applyLogicalMediaState(`split-audio-soft-recover:${reason}`);
      updatePlayerControls();
      log('split audio soft recover', reason);
      return true;
    } catch (err) {
      sa.lastError = err && err.message ? err.message : String(err);
      return false;
    }
  }

  function splitAudioReconnectRecover(reason = 'watchdog') {
    if (!splitPlayerSyncEnabled()) return false;
    const sa = state.splitAudio;
    const now = performance.now();
    if (now - (sa.lastRecoverAt || 0) < 5000) return false;
    sa.lastRecoverAt = now;
    sa.recoveryCount = (sa.recoveryCount || 0) + 1;
    sa.status = `reconnect:${reason}`;
    sa.syncHealth = `reconnect ${reason}`;
    log('split audio watchdog reconnect', reason);
    try { splitDisconnectAudio(`watchdog:${reason}`); } catch (_) {}
    setTimeout(() => splitConnectAudio(`watchdog:${reason}`), 500);
    updatePlayerControls();
    return true;
  }

  function updateSplitAudioHealth(inboundAudio, inboundVideo) {
    if (!splitAudioEnabled()) return 'split sync off';
    const sa = state.splitAudio;
    const mode = splitPlayerSyncMode();
    const now = performance.now();
    const warmupLeft = splitAudioWarmupRemainingMs();
    const videoJ = state.latestJbufStatsByKind.video;
    const audioJ = state.latestJbufStatsByKind.audio;
    const hasOffset = !!(videoJ && audioJ && Number.isFinite(videoJ.valueMs) && Number.isFinite(audioJ.valueMs));
    if (hasOffset) {
      sa.lastAvOffsetMs = Math.max(0, audioJ.valueMs - videoJ.valueMs);
      updateSplitAudioOffsetBaseline(sa.lastAvOffsetMs, warmupLeft <= 0);
    }

    if (mode === 'Off / free-run') {
      sa.syncHealth = 'free-run';
      return splitSyncStatusLine();
    }

    if (warmupLeft > 0) {
      if (Number.isFinite(sa.lastAvOffsetMs) && sa.lastAvOffsetMs > liveEdgeUnlearnedOffsetAllowanceMs()) {
        sa.syncHealth = `implausible startup offset +${Math.round(sa.lastAvOffsetMs)}ms`;
      } else {
        sa.syncHealth = `warming up ${Math.ceil(warmupLeft / 1000)}s`;
      }
      sa.lastHealthyAt = now;
      sa.stallTicks = 0;
      sa.offsetHighTicks = 0;
      if (inboundAudio) {
        const packets = Number.isFinite(inboundAudio.packetsReceived) ? inboundAudio.packetsReceived : 0;
        const bytes = Number.isFinite(inboundAudio.bytesReceived) ? inboundAudio.bytesReceived : 0;
        const emitted = Number.isFinite(inboundAudio.jitterBufferEmittedCount) ? inboundAudio.jitterBufferEmittedCount : 0;
        sa.lastInboundStats = { packets, bytes, emitted, at: now };
      }
      return splitSyncStatusLine();
    }

    let audioMoving = false;
    if (inboundAudio) {
      const packets = Number.isFinite(inboundAudio.packetsReceived) ? inboundAudio.packetsReceived : 0;
      const bytes = Number.isFinite(inboundAudio.bytesReceived) ? inboundAudio.bytesReceived : 0;
      const emitted = Number.isFinite(inboundAudio.jitterBufferEmittedCount) ? inboundAudio.jitterBufferEmittedCount : 0;
      const last = sa.lastInboundStats;
      if (!last || packets > last.packets || bytes > last.bytes || emitted > last.emitted) {
        audioMoving = true;
        sa.lastHealthyAt = now;
        sa.stallTicks = 0;
      } else {
        sa.stallTicks = (sa.stallTicks || 0) + 1;
      }
      sa.lastInboundStats = { packets, bytes, emitted, at: now };
    }

    const track = audio.srcObject && audio.srcObject.getAudioTracks ? audio.srcObject.getAudioTracks()[0] : null;
    const trackBad = !!(track && track.readyState && track.readyState !== 'live');
    const elementStalled = !!(audio.srcObject && !state.controller.userPaused && (audio.paused || audio.readyState < 2 || trackBad));
    const staleFor = now - (sa.lastHealthyAt || now);

    if (elementStalled) {
      sa.syncHealth = trackBad ? 'track ended' : 'audio element stalled';
      splitAudioSoftRecover(sa.syncHealth.replace(/\s+/g, '-'));
      return splitSyncStatusLine();
    }

    if (inboundAudio && !audioMoving && staleFor > splitAudioStallMs()) {
      sa.syncHealth = `audio stats stale ${Math.round(staleFor)}ms`;
      splitAudioReconnectRecover('stats-stale');
      return splitSyncStatusLine();
    }

    if (splitSoftSyncEnabled() && Number.isFinite(sa.lastAvOffsetMs)) {
      const baselineReady = Number.isFinite(sa.avOffsetBaselineMs) && !!sa.avOffsetBaselineLocked;
      const driftMs = Number.isFinite(sa.avOffsetDeltaMs) ? sa.avOffsetDeltaMs : NaN;
      if (!baselineReady) {
        sa.offsetHighTicks = 0;
        sa.syncHealth = `learning offset baseline ${Math.max(0, sa.avOffsetBaselineSamples || 0)}/${splitAvBaselineLearnTicks()}`;
        return splitSyncStatusLine();
      }
      if (Number.isFinite(driftMs) && driftMs > splitAvOffsetWarnMs()) {
        sa.offsetHighTicks = (sa.offsetHighTicks || 0) + 1;
        sa.syncHealth = `audio drift +${Math.round(driftMs)}ms over baseline`;
        // Soft-sync does not delay video. If the audio side drifts too far
        // above its learned/configured healthy offset, reset only split audio.
        if (sa.offsetHighTicks >= 5) {
          splitAudioReconnectRecover('offset-drift-high');
          sa.offsetHighTicks = 0;
          resetSplitAudioOffsetBaseline('post-offset-reconnect');
        }
        return splitSyncStatusLine();
      }
    }

    sa.offsetHighTicks = 0;
    sa.syncHealth = inboundAudio ? 'healthy' : 'waiting-audio-stats';
    return splitSyncStatusLine();
  }

  function startStatsTimer() {
    stopStatsTimer();
    resetLiveEdgeAverage('stats-start');
    state.statsTimer = setInterval(async () => {
      if (!state.pc || !['connected', 'completed'].includes(state.pc.iceConnectionState)) return;
      try {
        const stats = await state.pc.getStats();
        let selected = null;
        let inboundVideo = null;
        let inboundAudio = null;
        const scopedInboundReports = [];
        stats.forEach((report) => {
          if (report.type === 'inbound-rtp') {
            scopedInboundReports.push({ scope: 'primary', report });
            if (report.kind === 'video' || report.mediaType === 'video') inboundVideo = report;
            if (report.kind === 'audio' || report.mediaType === 'audio') inboundAudio = report;
          }
        });
        selected = selectedCandidatePair(stats);
        applyAllReceiverJitter('stats tick', true);
        let protoLine = state.lastIceProtocol || 'ICE media: —';
        let rttLine = 'RTT —';
        let measuredRttMs = NaN;
        let bitrateLine = 'bitrate —';
        let availableBitrate = NaN;
        if (selected) {
          const proto = candidatePairProtocol(stats, selected);
          const mediaRoute = candidatePairRoute(stats, selected);
          const pathKind = candidatePairPathKind(stats, selected);
          if (connectionMode() === 'proxy' && pathKind === 'PROXY FALLBACK: DIRECT LAN MEDIA') {
            state.proxyPairLocalTicks += 1;
            // Give the ICE agent a few more seconds on the LAN pair before
            // giving up on it -- a slower external/relay check can still
            // complete and take over as the selected pair on its own,
            // without needing a full reconnect roll of the dice.
            if (state.proxyPairLocalTicks >= PROXY_PAIR_GRACE_TICKS) retryPrimaryForExternalCandidate();
          } else if (pathKind) {
            state.proxyPairRetryCount = 0;
            state.proxyPairLocalTicks = 0;
          }
          const formattedProto = proto || mediaRoute || pathKind ? `ICE media: ${[pathKind, proto, mediaRoute].filter(Boolean).join(' · ')}` : '';
          if (formattedProto && formattedProto !== state.lastIceProtocol) {
            state.lastIceProtocol = formattedProto;
            setStatus('Live', state.lastIceProtocol, 'good');
            // Explicit, always-on (not gated behind jbufDebugEnabled) so the
            // actual local/remote IPs of the nominated pair always show up in
            // the console -- this is exactly what's needed to tell "using a
            // real external candidate" apart from "fell back to something
            // else" without having to read the on-screen status text.
            log(`primary nominated pair: ${mediaRoute || '(unknown)'}${pathKind ? ` · ${pathKind}` : ''}`);
          }
          protoLine = state.lastIceProtocol || protoLine;
          const rtt = candidatePairRtt(selected);
          if (Number.isFinite(rtt)) {
            measuredRttMs = rtt * 1000;
            rttLine = `RTT ${fmtMs(rtt)}`;
          }
          availableBitrate = Number(selected.availableIncomingBitrate || selected.availableOutgoingBitrate);
        }
        let fpsLine = 'FPS —';
        let measuredFps = NaN;
        let lossLine = 'loss —';
        let jitterLine = 'jitter —';
        let decodeLine = '';
        let videoJbufLine = getInboundJbufLine('video', inboundVideo);
        let audioJbufLine = getInboundJbufLine('audio', inboundAudio);
        if (inboundVideo) {
          const now = inboundVideo.timestamp || performance.now();
          const frames = Number.isFinite(inboundVideo.framesDecoded) ? inboundVideo.framesDecoded : 0;
          if (state.lastStatsVideo && frames >= state.lastStatsVideo.frames) {
            const dt = Math.max(1, now - state.lastStatsVideo.ts) / 1000;
            const fps = (frames - state.lastStatsVideo.frames) / dt;
            if (Number.isFinite(fps)) { measuredFps = fps; fpsLine = `FPS ${fps.toFixed(1)}`; }
          }
          state.lastStatsVideo = { ts: now, frames };
          const jitterMs = Number.isFinite(inboundVideo.jitter) ? inboundVideo.jitter * 1000 : 0;
          jitterLine = `jitter ${fmtMs(jitterMs, true)}`;
          const lost = Number.isFinite(inboundVideo.packetsLost) ? inboundVideo.packetsLost : 0;
          const received = Number.isFinite(inboundVideo.packetsReceived) ? inboundVideo.packetsReceived : 0;
          lossLine = `loss ${lost}/${received}`;
          const dropped = Number.isFinite(inboundVideo.framesDropped) ? inboundVideo.framesDropped : 0;
          const freezes = Number.isFinite(inboundVideo.freezeCount) ? inboundVideo.freezeCount : 0;
          decodeLine = `decoded ${frames} dropped ${dropped} freezes ${freezes}`;
          if (adaptiveJitterEnabled()) {
            const minMs = adaptiveJitterMinMs();
            const maxMs = adaptiveJitterMaxMs();
            if (!state.currentJitterMs) state.currentJitterMs = minMs;
            const last = state.lastInboundVideo;
            const lostDelta = last ? Math.max(0, lost - last.lost) : 0;
            const recvDelta = last ? Math.max(0, received - last.received) : 0;
            const lossRatio = recvDelta > 0 ? lostDelta / recvDelta : 0;
            state.lastInboundVideo = { lost, received };
            let next = state.currentJitterMs;
            if (lostDelta > 0 || lossRatio > 0.01 || jitterMs > Math.max(30, state.currentJitterMs * 0.45)) {
              next = Math.min(maxMs, Math.max(next + 30, Math.ceil(jitterMs * 2.0 + 30)));
              state.adaptiveStableTicks = 0;
            } else if (jitterMs < Math.max(10, state.currentJitterMs * 0.18)) {
              state.adaptiveStableTicks += 1;
              if (state.adaptiveStableTicks >= 4) {
                next = Math.max(minMs, next - 10);
                state.adaptiveStableTicks = 0;
              }
            } else {
              state.adaptiveStableTicks = 0;
            }
            if (next !== state.currentJitterMs) {
              setReceiverJitter(next, `adaptive jitter=${Math.round(jitterMs)}ms lossDelta=${lostDelta}`);
              setStatus('Live', `${state.lastIceProtocol || 'WebRTC connected'} · jitter hint ${next}ms adaptive`, 'good');
            }
          }
        }
        if (splitAudioEnabled() && state.splitAudio.pc && ['connected', 'completed'].includes(state.splitAudio.pc.iceConnectionState)) {
          try {
            const audioStats = await state.splitAudio.pc.getStats();
            let splitInboundAudio = null;
            audioStats.forEach((report) => {
              if (report.type === 'inbound-rtp' && (report.kind === 'audio' || report.mediaType === 'audio')) {
                splitInboundAudio = report;
                scopedInboundReports.push({ scope: 'split-audio', report });
              }
            });
            if (splitInboundAudio) {
              inboundAudio = splitInboundAudio;
              audioJbufLine = getInboundJbufLine('audio', inboundAudio);
            }
            const splitSelected = selectedCandidatePair(audioStats);
            if (splitSelected) {
              const splitPathKind = candidatePairPathKind(audioStats, splitSelected);
              const splitRouteLine = candidatePairRoute(audioStats, splitSelected);
              if (splitRouteLine && splitRouteLine !== state.splitAudio.lastRouteLine) {
                state.splitAudio.lastRouteLine = splitRouteLine;
                log(`split audio nominated pair: ${splitRouteLine}${splitPathKind ? ` · ${splitPathKind}` : ''}`);
              }
              if (connectionMode() === 'proxy' && splitPathKind === 'PROXY FALLBACK: DIRECT LAN MEDIA') {
                state.splitAudio.proxyPairLocalTicks += 1;
                if (state.splitAudio.proxyPairLocalTicks >= PROXY_PAIR_GRACE_TICKS) retrySplitAudioForExternalCandidate();
              } else if (splitPathKind) {
                state.splitAudio.proxyPairRetryCount = 0;
                state.splitAudio.proxyPairLocalTicks = 0;
              }
            }
          } catch (err) {
            state.splitAudio.lastError = err && err.message ? err.message : String(err);
          }
        }

        const rxBitrate = measuredInboundBitrate(scopedInboundReports);
        if (Number.isFinite(rxBitrate)) bitrateLine = fmtBitrate(rxBitrate);
        else if (Number.isFinite(availableBitrate)) bitrateLine = `${Math.round(availableBitrate / 1000)} kbps avail`;

        if (inboundAudio) {
          const audioJitterMs = Number.isFinite(inboundAudio.jitter) ? inboundAudio.jitter * 1000 : 0;
          const audioLost = Number.isFinite(inboundAudio.packetsLost) ? inboundAudio.packetsLost : 0;
          const audioReceived = Number.isFinite(inboundAudio.packetsReceived) ? inboundAudio.packetsReceived : 0;
          audioJbufLine += ` · jitter ${fmtMs(audioJitterMs, true)} · loss ${audioLost}/${audioReceived}`;
        }

        const splitSyncLine = updateSplitAudioHealth(inboundAudio, inboundVideo);
        const deSynced = splitIsDesynced();
        if (deSynced !== state.liveEdgeFaultActive) {
          state.liveEdgeFaultActive = deSynced;
          resetLiveEdgeAverage(deSynced ? 'desync-enter' : 'desync-clear');
        }
        const liveEdgeMs = estimateLiveEdgeMs(measuredRttMs);
        const liveEdge = liveEdgeDescriptor(liveEdgeMs, deSynced);
        state.liveEdgeState = liveEdge.state;
        const compactStatusKey = `${liveEdge.label}:${liveEdge.kind}`;
        if (state.lastCompactStatus !== compactStatusKey) {
          state.lastCompactStatus = compactStatusKey;
          setStatus(liveEdge.label, '', liveEdge.kind);
        }

        renderStatsOverlay([
          liveEdgeLine(liveEdgeMs, liveEdge),
          signalingKeepAliveLine(),
          screenWakeLockLine(),
          `${protoLine} · ${rttLine} · ${bitrateLine}`,
          playerConfigLine(),
          `video ${fpsLine} · ${jitterLine} · ${lossLine} · ${decodeLine}`,
          `${videoJbufLine} · recovery ${configValue('recoveryMode', 'RTX only')} · queue ${configValue('senderQueueMode', 'Leaky live')} ${configValue('senderQueueCapMs', 0)}ms`,
          splitAudioSummaryLine(),
          splitSyncLine,
          inboundAudio ? audioJbufLine : ''
        ]);
      } catch (err) {
        if (jbufDebugEnabled()) log('stats tick failed', err);
      }
    }, 1000);
  }

  function stopSession(notify = true, options = {}) {
    if (notify && state.sessionId) send({ type: 'endSession', sessionId: state.sessionId }, true);
    stopStatsTimer();
    if (state.jitterApplyTimer) clearInterval(state.jitterApplyTimer);
    state.jitterApplyTimer = null;
    if (state.pc) { try { state.pc.close(); } catch (_) {} }
    state.pc = null;
    state.sessionId = null;
    state.remotePeerId = null;
    state.pendingIce = [];
    state.pendingRemoteIce = [];
    state.started = false;
    state.lastIceProtocol = '';
    state.receivers.clear();
    state.currentJitterMs = 0;
    state.currentJitterMsByKind = { audio: null, video: null };
    state.lastInboundVideo = null;
    state.lastInboundAudio = null;
    state.lastStatsVideo = null;
    state.inboundBitrateSamples.clear();
    resetLiveEdgeAverage('session-stop');
    state.liveEdgeState = 'unknown';
    state.liveEdgeFaultActive = false;
    state.lastCompactStatus = '';
    state.lastJbufStats = null;
    state.lastJbufStatsByKind = { audio: null, video: null };
    state.latestJbufStatsByKind = { audio: null, video: null };
    state.jbufHighTicks = 0;
    state.jbufHighTicksByKind = { audio: 0, video: 0 };
    state.jbufWatchdogWarmupUntil = 0;
    state.jbufWatchdogWarmupReason = '';
    renderStatsOverlay(['stats pending']);
    resetRenderedMedia({ preserveSplitAudio: options && options.preserveSplitAudio });
    state.activeRenderMode = '';
    document.body.classList.remove('playing', 'fsWanted', 'fsBlocked', 'uiActive', 'statusAlert');
    syncScreenWakeLock('session-stop');
    if (playerUiHideTimer) clearTimeout(playerUiHideTimer);
    playerUiHideTimer = null;
    if (options && options.stopSplitAudio) {
      splitDisconnectAudio(options.reason || 'primary-stopped');
    }
    setFullscreenState();
    updatePlayerControls();
  }

  function handleMessage(msg) {
    switch (msg.type) {
      case 'welcome':
        state.peerId = msg.peerId || state.peerId;
        send({
          type: 'setPeerStatus',
          roles: ['listener'],
          meta: { name: 'GStreamer Glass Simple Player' },
          peerId: state.peerId
        }, true);
        break;
      case 'peerStatusChanged': {
        if (msg.peerId === state.peerId || msg.id === state.peerId) {
          if (Array.isArray(msg.roles) && msg.roles.includes('listener')) {
            state.ready = true;
            send({ type: 'list' }, true);
            send({ type: 'listConsumers' }, true);
          }
        } else {
          const peer = normalizePeer(msg);
          if (peer && peer.roles.includes('producer')) addProducer(peer, 'producer');
        }
        break;
      }
      case 'list':
        parseProducerList(msg);
        break;
      case 'listConsumers':
        break;
      case 'sessionStarted':
        state.sessionId = msg.sessionId || state.sessionId;
        if (msg.peerId) state.remotePeerId = msg.peerId;
        flushIce();
        break;
      case 'peer':
        if (msg.sessionId && state.sessionId && msg.sessionId !== state.sessionId) return;
        Promise.resolve()
          .then(() => msg.sdp ? handleRemoteSdp(msg.sdp) : null)
          .then(() => msg.ice ? handleRemoteIce(msg.ice) : null)
          .then(flushIce)
          .catch((err) => setStatus('WebRTC error', err.message, 'bad'));
        break;
      case 'endSession':
        if (!msg.sessionId || msg.sessionId === state.sessionId) {
          stopSession(false, { stopSplitAudio: true, reason: 'primary-endSession' });
          setStatus('Stream ended', 'Waiting for producer…', 'warn');
          send({ type: 'list' }, true);
        }
        break;
      case 'error':
        setStatus('Signaling error', msg.details || msg.error || JSON.stringify(msg), 'bad');
        break;
    }
  }

  function handleVideoActivation(ev) {
    if (Date.now() < state.videoZoom.suppressTapUntil) {
      ev.preventDefault();
      ev.stopPropagation();
      return;
    }
    if (state.manualResumeRequired) {
      ev.preventDefault();
      ev.stopPropagation();
      toggleLogicalPause();
      return;
    }
    noteUserGesture(true);
  }
  video.addEventListener('click', handleVideoActivation);
  video.addEventListener('touchend', handleVideoActivation, { passive: false });
  video.addEventListener('play', () => {
    if (!state.controller.userPaused) applyLogicalMediaState('native-video-play');
    syncScreenWakeLock('native-video-play', true);
  });
  video.addEventListener('pause', () => {
    if (logicalSplitControlsActive() && !state.controller.userPaused && !video.ended && document.visibilityState !== 'hidden') updatePlayerControls();
    syncScreenWakeLock('native-video-pause');
  });
  audio.addEventListener('play', () => updatePlayerControls());
  audio.addEventListener('pause', () => {
    updatePlayerControls();
    // A teardown clears/replaces srcObject before this deferred check runs.
    // If the same live split-audio source remains unexpectedly paused, resume
    // it without misclassifying the pause/play race as an autoplay block.
    const source = audio.srcObject;
    setTimeout(() => {
      if (source && audio.srcObject === source && logicalSplitControlsActive() && !state.controller.userPaused && audio.paused) {
        requestMediaPlayback(audio, 'audio', 'unexpected-pause');
      }
    }, 100);
  });
  setupVideoPinchZoom();
  audio.addEventListener('volumechange', () => {
    if (logicalSplitControlsActive()) {
      state.controller.userMuted = !!audio.muted;
      state.controller.volume = Number.isFinite(audio.volume) ? audio.volume : state.controller.volume;
      updatePlayerControls();
    }
  });
  window.addEventListener('beforeinstallprompt', (ev) => {
    // Chromium supplies this event only after the manifest/app meets its
    // installability checks. Holding it lets the media bar offer installation
    // without forcing a browser prompt on page load.
    ev.preventDefault();
    state.controller.installPrompt = ev;
    updatePlayerControls();
    revealPlayerUi('pwa-install-ready', 5000);
  });
  window.addEventListener('appinstalled', () => {
    state.controller.installPrompt = null;
    updatePlayerControls();
    log('PWA installed');
  });
  if (window.matchMedia) {
    const displayMode = window.matchMedia('(display-mode: standalone)');
    if (displayMode.addEventListener) displayMode.addEventListener('change', () => updatePlayerControls());
  }
  ensurePlayerControls();
  applyLogicalMediaState('startup');
  if (fullscreenButton) {
    fullscreenButton.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      recordUserInteraction('prominent-fullscreen');
      togglePlayerFullscreen('prominent-button');
    });
    fullscreenButton.addEventListener('touchend', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      recordUserInteraction('prominent-fullscreen-touch');
      togglePlayerFullscreen('prominent-button-touch');
    }, { passive: false });
  }

  document.addEventListener('fullscreenchange', () => { setFullscreenState(); applyVideoZoom(state.videoZoom.scale, state.videoZoom.x, state.videoZoom.y, 'fullscreenchange'); revealPlayerUi('fullscreenchange'); syncScreenWakeLock('fullscreenchange', true); scheduleFullscreenRenderRecovery('fullscreenchange'); });
  document.addEventListener('webkitfullscreenchange', () => { setFullscreenState(); applyVideoZoom(state.videoZoom.scale, state.videoZoom.x, state.videoZoom.y, 'webkitfullscreenchange'); revealPlayerUi('webkitfullscreenchange'); syncScreenWakeLock('webkitfullscreenchange', true); scheduleFullscreenRenderRecovery('webkitfullscreenchange'); });
  video.addEventListener('webkitbeginfullscreen', () => { setFullscreenState(); applyVideoZoom(state.videoZoom.scale, state.videoZoom.x, state.videoZoom.y, 'webkitbeginfullscreen'); revealPlayerUi('webkitbeginfullscreen'); syncScreenWakeLock('webkitbeginfullscreen', true); scheduleFullscreenRenderRecovery('webkitbeginfullscreen'); });
  video.addEventListener('webkitendfullscreen', () => { setFullscreenState(); applyVideoZoom(state.videoZoom.scale, state.videoZoom.x, state.videoZoom.y, 'webkitendfullscreen'); revealPlayerUi('webkitendfullscreen'); syncScreenWakeLock('webkitendfullscreen', true); });
  window.addEventListener('orientationchange', () => {
    setTimeout(() => {
      setFullscreenState();
      applyVideoZoom(state.videoZoom.scale, state.videoZoom.x, state.videoZoom.y, 'orientationchange');
      syncScreenWakeLock('orientationchange', true);
      if (document.body.classList.contains('playing') && matchMedia('(orientation: landscape)').matches) {
        attemptAutoFullscreen();
      }
    }, 250);
  });

  video.addEventListener('loadedmetadata', () => scheduleFullscreenRenderRecovery('loadedmetadata', 100));
  video.addEventListener('canplay', () => scheduleFullscreenRenderRecovery('canplay', 100));
  video.addEventListener('playing', () => {
    if (typeof video.requestVideoFrameCallback === 'function') {
      try { video.requestVideoFrameCallback(() => noteVideoFramePresented('playing')); } catch (_) {}
    } else {
      noteVideoFramePresented('playing-no-rvfc');
    }
  });
  video.addEventListener('stalled', () => scheduleFullscreenRenderRecovery('stalled', 250));
  video.addEventListener('emptied', cancelFullscreenRenderRecovery);

  document.addEventListener('pointermove', () => revealPlayerUi('pointermove'), { passive: true });
  document.addEventListener('pointerdown', () => revealPlayerUi('pointerdown'), { passive: true });
  document.addEventListener('touchstart', () => revealPlayerUi('touchstart'), { passive: true });
  document.addEventListener('keydown', () => revealPlayerUi('keydown'));
  document.addEventListener('focusin', () => revealPlayerUi('focusin'));
  window.addEventListener('resize', () => applyVideoZoom(state.videoZoom.scale, state.videoZoom.x, state.videoZoom.y, 'resize'));
  // A PWA relaunched from its home-screen icon after being swiped away is
  // not guaranteed to be a fresh process/script execution -- Android/Chrome
  // can instead resume a frozen, previously-loaded renderer as-is (same DOM,
  // same JS state, same possibly-stale config.configReloadTimer), showing
  // whatever the page looked like when it was backgrounded rather than
  // re-running the auth/redirect checks a true fresh load would. This is
  // exactly why "logged out, closed the PWA, reopened it" could land back
  // on the player instead of staying on login -- nothing ever re-validated
  // the session against the resumed page. visibilitychange and pageshow are
  // the standard signals for "this page is back, possibly stale, worth
  // re-checking" (pageshow specifically fires on bfcache/frozen-page
  // restores) -- restarting the whole config/stream-state/auth poll loop
  // (not just a one-off check) on both also recovers from the interval
  // itself having been frozen/killed during the background period.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') { syncScreenWakeLock('visibility-visible', true); scheduleFullscreenRenderRecovery('visibility-visible', 200); startConfigReloadTimer(); }
    else syncScreenWakeLock('visibility-hidden');
  });
  window.addEventListener('pageshow', (event) => {
    syncScreenWakeLock('pageshow', true);
    scheduleFullscreenRenderRecovery('pageshow', 200);
    if (event.persisted) {
      // event.persisted means the browser has confirmed this is a genuine
      // bfcache restore (cached document AND cached JS state), not a fresh
      // load -- nothing about whatever is currently running, however stale
      // it might be, can be trusted to self-correct from in here. A hard
      // reload forces a real fresh fetch of the document, which the
      // no-store headers on it now guarantee re-hits the auth gate rather
      // than resuming whatever was cached.
      location.reload();
      return;
    }
    startConfigReloadTimer();
  });
  window.addEventListener('focus', () => { syncScreenWakeLock('window-focus', true); scheduleFullscreenRenderRecovery('window-focus', 200); });


  function splitSend(obj, allowBeforeReady = false) {
    const sa = state.splitAudio;
    if (!sa.ws || sa.ws.readyState !== WebSocket.OPEN) return false;
    if (!sa.ready && !allowBeforeReady && obj.type !== 'setPeerStatus') return false;
    sa.ws.send(JSON.stringify(obj));
    return true;
  }

  function splitStopKeepAlive() {
    const sa = state.splitAudio;
    if (sa.keepAliveTimer) clearInterval(sa.keepAliveTimer);
    sa.keepAliveTimer = null;
  }

  function splitStartKeepAlive(reason = 'open') {
    const sa = state.splitAudio;
    splitStopKeepAlive();
    const interval = keepAliveMs();
    if (!interval) return;
    sa.keepAliveCount = 0;
    sa.lastKeepAliveAt = 0;
    sa.keepAliveTimer = setInterval(() => {
      if (!sa.ws || sa.ws.readyState !== WebSocket.OPEN) return;
      sa.keepAliveCount += 1;
      sa.lastKeepAliveAt = performance.now();
      splitSend({ type: 'list' }, true);
      if (sa.keepAliveCount % 4 === 0) splitSend({ type: 'listConsumers' }, true);
      if (jbufDebugEnabled()) log('split audio keepalive', reason, sa.keepAliveCount);
    }, interval);
  }

  function signalingKeepAliveLine() {
    const primaryState = state.ws ? ['connecting', 'open', 'closing', 'closed'][state.ws.readyState] || String(state.ws.readyState) : 'no-ws';
    const primaryKa = state.keepAliveTimer ? String(state.keepAliveCount || 0) : 'off';
    if (!splitAudioEnabled()) {
      return `${connectionModeStatusLine()} · KA ${primaryKa} (${primaryState})`;
    }
    const sa = state.splitAudio;
    const audioState = sa.ws ? ['connecting', 'open', 'closing', 'closed'][sa.ws.readyState] || String(sa.ws.readyState) : 'no-ws';
    const audioKa = sa.keepAliveTimer ? String(sa.keepAliveCount || 0) : 'off';
    if (sharedSignalingEnabled()) {
      return `${connectionModeStatusLine()} · shared signaling · KA V${primaryKa}/A${audioKa} (${primaryState}/${audioState})`;
    }
    let audioEndpoint = 'audio endpoint';
    try { audioEndpoint = new URL(splitAudioWsUrl(), location.href).host || audioEndpoint; } catch (_) {}
    return `${connectionModeStatusLine()} · KA video ${primaryKa} (${primaryState}) · audio ${audioEndpoint} KA ${audioKa} (${audioState})`;
  }

  function splitAudioSummaryLine() {
    if (!splitAudioEnabled()) return '';
    const sa = state.splitAudio || {};
    const pcState = sa.pc ? (sa.pc.iceConnectionState || sa.pc.connectionState || 'pc') : 'no-pc';
    const producers = sa.producers ? sa.producers.size : 0;
    const track = sa.lastTrackKind || 'waiting';
    const error = sa.lastError ? ` · error ${sa.lastError}` : '';
    return `audio path ${sa.status || 'idle'} · ${pcState} · track ${track} · producers ${producers}${error}`;
  }

  function splitNormalizePeer(peer, assumedRole) {
    if (!peer || typeof peer !== 'object') return null;
    const id = peer.peerId || peer.id;
    if (!id || id === state.splitAudio.peerId) return null;
    let roles = Array.isArray(peer.roles) ? [...peer.roles] : [];
    if (assumedRole && !roles.includes(assumedRole)) roles.push(assumedRole);
    return { id, roles, meta: peer.meta || {} };
  }

  function splitStartFirstProducer() {
    const sa = state.splitAudio;
    if (sa.pc || sa.sessionId || !sa.producers.size) return;
    const selected = selectProducerForKind(sa.producers, 'audio');
    if (selected) {
      sa.status = 'audio-producer-found';
      splitStartConsumer(selected.id);
    } else if (sharedSignalingEnabled()) {
      sa.status = 'waiting-audio-producer';
    }
  }

  function splitAddProducer(peerLike, assumedRole = 'producer') {
    const peer = splitNormalizePeer(peerLike, assumedRole);
    if (!peer || !peer.roles.includes('producer')) return;
    state.splitAudio.producers.set(peer.id, peer);
    state.splitAudio.status = `producer ${peer.id}`;
    splitStartFirstProducer();
  }

  function splitParseProducerList(msg) {
    const sa = state.splitAudio;
    sa.producers.clear();
    const producers = msg.producers || msg.peers || [];
    if (Array.isArray(producers)) producers.forEach((p) => splitAddProducer(p, 'producer'));
    else if (producers && typeof producers === 'object') Object.entries(producers).forEach(([id, value]) => splitAddProducer({ peerId: id, ...(value || {}) }, 'producer'));
  }

  async function splitStartConsumer(peerId) {
    const sa = state.splitAudio;
    if (!sa.ws || sa.ws.readyState !== WebSocket.OPEN) return;
    if (!sa.proxyPairRetrying) sa.proxyPairRetryCount = 0;
    splitStopSession(false);
    sa.status = 'starting-consumer';
    sa.remotePeerId = peerId;
    sa.pendingIce = [];
    sa.pendingRemoteIce = [];
    const pc = new RTCPeerConnection(makeRtcConfig());
    sa.pc = pc;
    window.audioPc = pc;

    pc.addEventListener('icecandidate', (ev) => {
      if (!ev.candidate) return;
      noteOwnPublicIpFromCandidate(ev.candidate.candidate);
      if (connectionMode() === 'proxy' && isLocalOnlyHostIceCandidateLine(ev.candidate.candidate)) return;
      const candidate = applyIceRoutePolicyToCandidate(ev.candidate, 'split audio local');
      if (sa.sessionId) splitSend({ type: 'peer', sessionId: sa.sessionId, ice: candidate }, true);
      else sa.pendingIce.push(candidate);
    });

    pc.addEventListener('track', (ev) => {
      applyReceiverJitter(ev.receiver, 'split audio track');
      setTimeout(() => applyReceiverJitter(ev.receiver, 'split audio track +250ms', null, true), 250);
      setTimeout(() => applyReceiverJitter(ev.receiver, 'split audio track +1000ms', null, true), 1000);
      state.splitAudio.status = 'track-received';
      state.splitAudio.lastTrackKind = ev.track && ev.track.kind ? ev.track.kind : 'track';
      state.splitAudio.trackReceivedAt = performance.now();
      beginWatchdogWarmup('split-track-received');
      attachTrackToPlayer(ev.track, null, 'split audio pc track');
      document.body.classList.add('playing');
      setStatus('Live', `split audio ${ev.track.kind} track received · ${playerConfigLine()}`, 'good');
      applyLogicalMediaState('split-audio-track');
      updatePlayerControls();
    });

    splitSend({ type: 'startSession', peerId }, true);
  }

  function splitFlushIce() {
    const sa = state.splitAudio;
    if (!sa.sessionId || !sa.pendingIce.length) return;
    sa.pendingIce.splice(0).forEach((ice) => splitSend({ type: 'peer', sessionId: sa.sessionId, ice }, true));
  }

  async function splitHandleRemoteSdp(sdp) {
    const sa = state.splitAudio;
    if (!sa.pc) throw new Error('split audio SDP without active peer connection');
    const pc = sa.pc;
    const rawDesc = typeof sdp === 'string' ? { type: 'offer', sdp } : sdp;
    const mappedDesc = injectMappedIceCandidatesIntoDescription(rawDesc, 'split audio remote');
    const desc = applyIceRoutePolicyToDescription(mappedDesc, 'split audio remote');
    await pc.setRemoteDescription(desc);
    if (sa.pc !== pc) return;
    while (sa.pendingRemoteIce.length) {
      try { await pc.addIceCandidate(sa.pendingRemoteIce.shift()); }
      catch (err) { log('queued split audio addIceCandidate failed', err); }
    }
    if (desc.type === 'offer') {
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      const local = applyIceRoutePolicyToDescription(pc.localDescription, 'split audio outbound', true);
      splitSend({ type: 'peer', sessionId: sa.sessionId, sdp: local.toJSON ? local.toJSON() : { type: local.type, sdp: local.sdp } }, true);
    }
  }

  async function splitHandleRemoteIce(ice) {
    const sa = state.splitAudio;
    if (!sa.pc || !ice) return;
    const routedCandidates = expandRemoteIceCandidates(ice, 'split audio remote')
      .map((candidate) => applyIceRoutePolicyToCandidate(candidate, 'split audio remote'))
      .filter((candidate) => candidate !== null);
    if (!routedCandidates.length) return;
    if (!sa.pc.remoteDescription) {
      sa.pendingRemoteIce.push(...routedCandidates);
      return;
    }
    for (const routedIce of routedCandidates) {
      try { await sa.pc.addIceCandidate(routedIce && routedIce.candidate ? routedIce : null); }
      catch (err) { log('split audio addIceCandidate failed', err); }
    }
  }

  function splitStopSession(notify = true, clearMedia = true) {
    const sa = state.splitAudio;
    if (notify && sa.sessionId) splitSend({ type: 'endSession', sessionId: sa.sessionId }, true);
    if (sa.pc) {
      try { sa.pc.getReceivers().forEach((receiver) => { if (receiver && receiver.track) receiver.track.stop(); }); } catch (_) {}
      try { sa.pc.close(); } catch (_) {}
    }
    sa.pc = null;
    sa.sessionId = null;
    sa.remotePeerId = null;
    sa.pendingIce = [];
    sa.pendingRemoteIce = [];
    sa.lastTrackKind = '';
    sa.lastInboundStats = null;
    sa.stallTicks = 0;
    sa.offsetHighTicks = 0;
    sa.trackReceivedAt = 0;
    sa.warmupUntil = 0;
    if (clearMedia) clearSplitAudioMedia('split-stop-session');
    updatePlayerControls();
  }

  function splitHandleMessage(msg) {
    const sa = state.splitAudio;
    switch (msg.type) {
      case 'welcome':
        sa.peerId = msg.peerId || sa.peerId;
        sa.status = 'welcome';
        splitSend({ type: 'setPeerStatus', roles: ['listener'], meta: { name: 'GStreamer Glass Split Audio Listener' }, peerId: sa.peerId }, true);
        setTimeout(() => splitRequestProducerList('welcome+250ms'), 250);
        break;
      case 'peerStatusChanged':
        if (msg.peerId === sa.peerId || msg.id === sa.peerId) {
          if (Array.isArray(msg.roles) && msg.roles.includes('listener')) { sa.ready = true; sa.status = 'listener-ready'; splitRequestProducerList('listener-ready'); }
        } else {
          const peer = splitNormalizePeer(msg);
          if (peer && peer.roles.includes('producer')) splitAddProducer(peer, 'producer');
        }
        break;
      case 'list': sa.status = 'list'; splitParseProducerList(msg); if (!sa.producers.size) setTimeout(() => splitRequestProducerList('empty-list-retry'), 1000); break;
      case 'sessionStarted': sa.sessionId = msg.sessionId || sa.sessionId; if (msg.peerId) sa.remotePeerId = msg.peerId; sa.status = 'session-started'; splitFlushIce(); break;
      case 'peer':
        if (msg.sessionId && sa.sessionId && msg.sessionId !== sa.sessionId) return;
        Promise.resolve().then(() => msg.sdp ? splitHandleRemoteSdp(msg.sdp) : null).then(() => msg.ice ? splitHandleRemoteIce(msg.ice) : null).then(splitFlushIce).catch((err) => log('split audio WebRTC error', err));
        break;
      case 'endSession': if (!msg.sessionId || msg.sessionId === sa.sessionId) splitStopSession(false); break;
      case 'error': sa.status = 'error'; sa.lastError = String(msg.details || msg.error || JSON.stringify(msg)); log('split audio signaling error', msg.details || msg.error || msg); break;
    }
    updatePlayerControls();
  }

  function splitDisconnectAudio(reason = 'disabled') {
    const sa = state.splitAudio;
    sa.attemptToken += 1;
    if (sa.reconnectTimer) { clearTimeout(sa.reconnectTimer); sa.reconnectTimer = null; }
    if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
    splitStopKeepAlive();
    sa.status = reason;
    sa.ready = false;
    splitStopSession(true);
    if (sa.ws) { try { sa.ws.close(); } catch (_) {} }
    sa.ws = null;
    sa.url = '';
    sa.route = '';
    sa.candidates = [];
    sa.producers.clear();
    clearSplitAudioMedia(reason);
    updatePlayerControls();
  }

  function splitRequestProducerList(reason = 'manual') {
    const sa = state.splitAudio;
    if (!sa.ws || sa.ws.readyState !== WebSocket.OPEN) return false;
    log('split audio list producers', reason);
    splitSend({ type: 'list' }, true);
    splitSend({ type: 'listConsumers' }, true);
    return true;
  }

  function reconcileSplitAudio(reason = 'reconcile') {
    if (!splitAudioEnabled()) {
      if (state.splitAudio.ws || state.splitAudio.pc) splitDisconnectAudio('disabled');
      updatePlayerControls();
      applyLogicalMediaState('split-disabled');
      return false;
    }
    return splitConnectAudio(reason);
  }

  function scheduleSplitReconnect() {
    const sa = state.splitAudio;
    if (!signalingAllowedByStreamState()) return;
    clearTimeout(sa.reconnectTimer);
    sa.reconnectTimer = null;
    if (sa.reconnectAttempts < RECONNECT_DELAYS_MS.length) {
      const delay = RECONNECT_DELAYS_MS[sa.reconnectAttempts];
      sa.reconnectAttempts += 1;
      sa.reconnectTimer = setTimeout(() => splitConnectAudio('retry'), delay);
    } else {
      sa.status = 'reconnect-stopped';
    }
  }

  function splitConnectAudio(reason = 'connect') {
    if (!signalingAllowedByStreamState()) return false;
    if (!splitAudioEnabled()) return false;
    const sa = state.splitAudio;
    const candidates = splitAudioSignalingCandidates();
    if (!candidates.length) {
      sa.status = 'no-url';
      sa.lastError = 'missing split audio signaling URL/port';
      log('split audio disabled: missing signaling candidates', window.GST_GLASS_CONFIG || {});
      updatePlayerControls();
      return false;
    }

    if (sa.ws && (sa.ws.readyState === WebSocket.OPEN || sa.ws.readyState === WebSocket.CONNECTING)) {
      const primaryDirectRequiresDirectAudio = connectionMode() === 'auto' && state.signalingRoute === 'direct' && sa.route !== 'direct';
      if (candidates.includes(sa.url) && !primaryDirectRequiresDirectAudio) return true;
      log('split audio reconnecting for candidate change', sa.url, '=>', candidates);
      splitStopKeepAlive();
      try { sa.ws.close(); } catch (_) {}
      sa.ws = null;
      splitStopSession(false);
    }

    if (sa.reconnectTimer) { clearTimeout(sa.reconnectTimer); sa.reconnectTimer = null; }
    if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
    splitStopKeepAlive();
    const token = ++sa.attemptToken;
    sa.candidates = [...candidates];
    let candidateIndex = 0;

    const retryAllLater = (detail) => {
      if (token !== sa.attemptToken) return;
      sa.ws = null;
      sa.ready = false;
      sa.status = 'reconnecting';
      sa.lastError = detail || 'all split audio signaling routes failed';
      updatePlayerControls();
      scheduleSplitReconnect();
    };

    const tryNextCandidate = (previousFailure = '') => {
      if (token !== sa.attemptToken || !splitAudioEnabled()) return;
      if (candidateIndex >= candidates.length) {
        retryAllLater(previousFailure);
        return;
      }

      const url = candidates[candidateIndex++];
      const route = signalingRouteForUrl(url, 'audio');
      sa.url = url;
      sa.route = route;
      sa.status = 'connecting';
      sa.lastError = previousFailure;
      sa.connectStartedAt = performance.now();
      sa.trackReceivedAt = 0;
      sa.lastInboundStats = null;
      beginWatchdogWarmup(`split-connect:${reason}`);
      log('split audio connecting', route, url, reason);
      updatePlayerControls();

      let ws;
      let opened = false;
      let advanced = false;

      const advance = (failure) => {
        if (advanced || opened || token !== sa.attemptToken) return;
        advanced = true;
        if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
        if (sa.ws === ws) sa.ws = null;
        try { if (ws && ws.readyState < WebSocket.CLOSING) ws.close(); } catch (_) {}
        if (candidateIndex < candidates.length) {
          log('split audio signaling route failed; trying fallback', url, '=>', candidates[candidateIndex], failure);
          setTimeout(() => tryNextCandidate(`${route} failed; trying fallback`), 0);
        } else {
          log('split audio signaling routes exhausted', candidates, failure);
          retryAllLater(`${route} failed: ${failure}`);
        }
      };

      try {
        ws = new WebSocket(url);
        sa.ws = ws;
      } catch (err) {
        advance(err && err.message ? err.message : String(err));
        return;
      }

      sa.connectTimer = setTimeout(() => {
        advance(`connect timeout after ${signalingConnectTimeoutMs()}ms`);
      }, signalingConnectTimeoutMs());

      ws.addEventListener('open', () => {
        if (token !== sa.attemptToken || sa.ws !== ws) {
          try { ws.close(); } catch (_) {}
          return;
        }
        opened = true;
        if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
        sa.ready = false;
        sa.reconnectAttempts = 0;
        sa.status = route === 'direct' && connectionMode() === 'auto' ? 'ws-open-direct-fallback' : 'ws-open';
        sa.lastError = '';
        beginWatchdogWarmup('split-ws-open');
        log('split audio signaling connected', route, url);
        updatePlayerControls();
        splitStartKeepAlive('ws-open');
        setTimeout(() => splitRequestProducerList('open+250ms'), 250);
        setTimeout(() => splitRequestProducerList('open+1000ms'), 1000);
      });

      ws.addEventListener('close', (ev) => {
        if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
        if (token !== sa.attemptToken || sa.ws !== ws) return;
        if (!opened) {
          advance(`closed before open (${ev.code || 0}${ev.reason ? `: ${ev.reason}` : ''})`);
          return;
        }
        const shouldReconnect = splitAudioEnabled() && sa.url === url;
        sa.ready = false;
        sa.status = shouldReconnect ? 'reconnecting' : 'closed';
        sa.lastError = ev && ev.reason ? ev.reason : '';
        splitStopKeepAlive();
        splitStopSession(false);
        log('split audio signaling closed', route, url, ev.code, ev.reason || '', shouldReconnect ? 'retrying' : 'not retrying');
        updatePlayerControls();
        if (shouldReconnect) scheduleSplitReconnect();
      });

      ws.addEventListener('error', (ev) => {
        if (token !== sa.attemptToken || sa.ws !== ws) return;
        log('split audio signaling error', route, url, ev);
        if (opened) {
          sa.status = 'error';
          sa.lastError = 'WebSocket error';
          updatePlayerControls();
        }
      });

      ws.addEventListener('message', (ev) => {
        if (token !== sa.attemptToken || sa.ws !== ws) return;
        let msg;
        try { msg = JSON.parse(ev.data); } catch (err) { log('split audio bad message', err, ev.data); return; }
        if (jbufDebugEnabled()) log('split audio msg', msg.type, msg);
        splitHandleMessage(msg);
      });
    };

    tryNextCandidate();
    return true;
  }

  window.addEventListener('beforeunload', () => {
    releaseScreenWakeLock('unload');
    stopConfigReloadTimer();
    stopKeepAlive();
    stopSession(true);
    splitDisconnectAudio('unload');
  });

  setFullscreenState();
  window.GstGlassJbuf = {
    targets: () => ({
      audioMs: receiverJitterMs('audio'),
      videoMs: receiverJitterMs('video'),
      maxMs: jbufMaxMs(),
      genericMs: playerJitterMs(),
      watchdog: jbufWatchdogMode(),
      debug: jbufDebugEnabled(),
      statsOverlay: statsOverlayEnabled(),
      avRenderMode: playerAvRenderMode(),
      separateHtmlMediaElements: playerSeparateHtmlMediaElements(),
      avPipelineMode: avPipelineMode(),
      splitAudioWsUrl: splitAudioWsUrl(),
      splitAudioSignalingCandidates: splitAudioSignalingCandidates(),
      splitAudioSignalingRoute: state.splitAudio.route || '',
      splitAudioSignalingPort: splitAudioSignalingPort(),
      sharedSignaling: sharedSignalingEnabled(),
      splitPlayerSyncMode: splitPlayerSyncMode(),
      splitAudioStallSeconds: splitAudioStallMs() / 1000,
      splitAvOffsetWarnMs: splitAvOffsetWarnMs(),
      splitAvOffsetBaselineMs: splitAvOffsetBaselineConfiguredMs(),
      splitAvBaselineLearnTicks: splitAvBaselineLearnTicks(),
      splitAudioStatus: splitAudioStatusLine(),
      splitSyncStatus: splitSyncStatusLine(),
      watchdogWarmupMs: watchdogWarmupMs(),
      jbufWatchdogWarmupRemainingMs: jbufWatchdogWarmupRemainingMs(),
      primaryWsUrl: primaryWsUrlForSplit(),
      configVersion: (window.GST_GLASS_CONFIG || {}).version,
      configWrittenUtc: (window.GST_GLASS_CONFIG || {}).writtenUtc,
      configSource: (window.GST_GLASS_CONFIG || {}).source
    }),
    apply: () => applyAllReceiverJitter('console', false),
    receivers: () => [...state.receivers].map((receiver) => ({
      kind: receiverKind(receiver),
      jitterBufferTarget: 'jitterBufferTarget' in receiver ? receiver.jitterBufferTarget : undefined,
      playoutDelayHint: 'playoutDelayHint' in receiver ? receiver.playoutDelayHint : undefined
    }))
  };

  window.GstGlassSplitAudio = {
    status: () => ({
      enabled: splitAudioEnabled(),
      mode: avPipelineMode(),
      url: splitAudioWsUrl(),
      candidates: splitAudioSignalingCandidates(),
      route: state.splitAudio.route || '',
      primaryUrl: primaryWsUrlForSplit(),
      port: splitAudioSignalingPort(),
      sharedSignaling: sharedSignalingEnabled(),
      primaryKeepAliveEnabled: !!state.keepAliveTimer,
      primaryKeepAliveCount: state.keepAliveCount || 0,
      primaryLastKeepAliveAt: state.lastKeepAliveAt || 0,
      keepAliveEnabled: !!state.splitAudio.keepAliveTimer,
      keepAliveCount: state.splitAudio.keepAliveCount || 0,
      lastKeepAliveAt: state.splitAudio.lastKeepAliveAt || 0,
      state: splitAudioStatusLine(),
      sync: splitSyncStatusLine(),
      syncMode: splitPlayerSyncMode(),
      avOffsetMs: state.splitAudio.lastAvOffsetMs,
      avOffsetBaselineMs: state.splitAudio.avOffsetBaselineMs,
      avOffsetDeltaMs: state.splitAudio.avOffsetDeltaMs,
      avOffsetBaselineLocked: state.splitAudio.avOffsetBaselineLocked,
      avOffsetBaselineSamples: state.splitAudio.avOffsetBaselineSamples,
      warmupMs: splitAudioWarmupMs(),
      warmupRemainingMs: splitAudioWarmupRemainingMs(),
      watchdogWarmupMs: watchdogWarmupMs(),
      jbufWatchdogWarmupRemainingMs: jbufWatchdogWarmupRemainingMs(),
      raw: state.splitAudio
    }),
    connect: () => splitConnectAudio('console'),
    disconnect: () => splitDisconnectAudio('console'),
    list: () => splitRequestProducerList('console'),
    pc: () => state.splitAudio.pc,
    ws: () => state.splitAudio.ws
  };

  window.GstGlassSplitSync = {
    mode: splitPlayerSyncMode,
    status: () => ({
      enabled: splitPlayerSyncEnabled(),
      mode: splitPlayerSyncMode(),
      softSync: splitSoftSyncEnabled(),
      status: splitSyncStatusLine(),
      avOffsetMs: state.splitAudio.lastAvOffsetMs,
      audioStallMs: splitAudioStallMs(),
      warmupMs: splitAudioWarmupMs(),
      warmupRemainingMs: splitAudioWarmupRemainingMs(),
      offsetWarnMs: splitAvOffsetWarnMs(),
      offsetBaselineMs: state.splitAudio.avOffsetBaselineMs,
      offsetDeltaMs: state.splitAudio.avOffsetDeltaMs,
      offsetBaselineLocked: state.splitAudio.avOffsetBaselineLocked,
      offsetBaselineSamples: state.splitAudio.avOffsetBaselineSamples,
      offsetBaselineConfiguredMs: splitAvOffsetBaselineConfiguredMs(),
      recoveries: state.splitAudio.recoveryCount || 0,
      lastAudioStats: state.splitAudio.lastInboundStats,
      health: state.splitAudio.syncHealth,
      audioElement: { paused: audio.paused, muted: audio.muted, readyState: audio.readyState, srcObject: !!audio.srcObject }
    }),
    softRecover: (reason = 'manual') => splitAudioSoftRecover(reason),
    reconnectAudio: (reason = 'manual') => splitAudioReconnectRecover(reason),
    beginWarmup: (reason = 'manual') => beginWatchdogWarmup(reason)
  };

  window.GstGlassPlayer = {
    play: () => {
      if (state.manualResumeRequired) toggleLogicalPause();
      else { state.controller.userPaused = false; applyLogicalMediaState('console-play'); }
    },
    pause: () => { state.controller.userPaused = true; applyLogicalMediaState('console-pause'); },
    mute: () => { state.controller.userMuted = true; applyLogicalMediaState('console-mute'); },
    unmute: () => { state.controller.userMuted = false; applyLogicalMediaState('console-unmute'); },
    volume: (value) => { const n = Number(value); if (Number.isFinite(n)) state.controller.volume = Math.max(0, Math.min(n, 1)); applyLogicalMediaState('console-volume'); },
    route: (mode) => setConnectionMode(mode, 'console'),
    state: () => ({ paused: state.controller.userPaused, muted: state.controller.userMuted, volume: state.controller.volume, connectionMode: connectionMode(), mediaRoutePolicy: mediaRoutePolicyLine(), signalingRoute: state.signalingRoute, signalingUrl: state.signalingUrl, signalingCandidates: [...state.signalingCandidates], signalingTransport: signalingTransportStatusLine(), screenWakeLock: screenWakeLockLine(), splitAudio: splitAudioStatusLine(), splitSync: splitSyncStatusLine(), videoPaused: video.paused, audioPaused: audio.paused, videoMuted: video.muted, audioMuted: audio.muted, ownPublicIp: state.ownPublicIp })
  };

  startConfigReloadTimer();
  registerPwaServiceWorker();

  if (jbufDebugEnabled()) {
    log('player config', playerConfigLine(), window.GST_GLASS_CONFIG || {});
  }

  updatePlayerControls();
  setStatus('Checking stream state', 'Waiting for stream state before connecting.', 'warn');
})();

// audio jbuf video jbuf GstGlassJbuf AV render decoupled media elements split av pipelines split audio player controller dual watchdog warmup split offset baseline PWA install service worker pinch zoom pan proxy WSS direct ICE
