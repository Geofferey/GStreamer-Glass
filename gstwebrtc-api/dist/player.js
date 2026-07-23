(() => {
  const FRONTEND_VERSION = '3.7.52f40-separate-mediastreams';
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
    producers: new Map(),
    started: false,
    reconnectTimer: null,
    keepAliveTimer: null,
    keepAliveCount: 0,
    lastKeepAliveAt: 0,
    signalingAttemptToken: 0,
    connectionModeOverride: '',
    signalingRoute: 'proxy',
    signalingUrl: '',
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
    splitAudio: { ws: null, pc: null, sessionId: null, peerId: null, remotePeerId: null, pendingIce: [], producers: new Map(), ready: false, url: '', status: 'idle', reconnectTimer: null, connectTimer: null, keepAliveTimer: null, keepAliveCount: 0, lastKeepAliveAt: 0, lastError: '', lastTrackKind: '', lastInboundStats: null, lastHealthyAt: 0, lastRecoverAt: 0, recoveryCount: 0, stallTicks: 0, offsetHighTicks: 0, lastAvOffsetMs: NaN, syncHealth: 'free-run', connectStartedAt: 0, trackReceivedAt: 0, warmupUntil: 0, avOffsetBaselineMs: NaN, avOffsetBaselineSamples: 0, avOffsetBaselineLocked: false, avOffsetDeltaMs: NaN, avOffsetBaselineReason: 'none' },
    controller: { userPaused: false, userMuted: false, volume: 1, uiPinned: false, initialized: false, installPrompt: null, bar: null, playButton: null, muteButton: null, volumeInput: null, spacer: null, reconnectButton: null, routeButton: null, installButton: null, zoomButton: null, pinButton: null, fullscreenButton: null, status: null, lastAppliedAt: 0 }
  };

  function isStandalonePwa() {
    return !!(window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
  }

  function registerPwaServiceWorker() {
    if (!('serviceWorker' in navigator) || !window.isSecureContext) return;
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
      state.lastConfigSignature = sig;
      window.GST_GLASS_CONFIG = cfg;
      const nextGrouping = mediaStreamGroupingSignature();
      if (jbufDebugEnabled()) log('config reloaded', reason, playerConfigLine(), cfg);
      applyAllReceiverJitter('config reload', true);
      refreshRenderedTracks('config reload');
      reconcileSplitAudio('config reload');
      updatePlayerControls();
      applyLogicalMediaState('config reload');
      if (previousGrouping !== nextGrouping && state.pc) {
        log('MediaStream grouping changed; restarting WebRTC session', previousGrouping, '→', nextGrouping);
        restartConnectionForMode('mediastream-grouping-change');
      }
      return true;
    } catch (err) {
      if (jbufDebugEnabled()) log('config reload failed', err);
      return false;
    }
  }

  function startConfigReloadTimer() {
    state.lastConfigSignature = configSignature(window.GST_GLASS_CONFIG || {});
    if (state.configReloadTimer) clearInterval(state.configReloadTimer);
    state.configReloadTimer = setInterval(() => reloadRuntimeConfig('poll'), 1000);
    setTimeout(() => reloadRuntimeConfig('startup'), 250);
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

  function proxyWsUrl() {
    const explicit = query('proxyWs') || query('proxySignal') || query('proxySignaling');
    if (explicit) {
      const normalized = normalizeWsUrl(explicit) || explicit;
      try {
        const parsed = new URL(normalized, location.href);
        if (location.protocol === 'https:' && parsed.protocol === 'ws:') parsed.protocol = 'wss:';
        return trimWsUrl(parsed.toString());
      } catch (_) { return normalized; }
    }
    const host = query('signalHost') || query('host') || (location.hostname && location.hostname !== '0.0.0.0' ? location.hostname : '127.0.0.1');
    const port = query('signalPort') || query('videoSignalingPort') || query('port') || String(configValue('videoSignalingPort', configValue('signalingPort', 8189)));
    const scheme = location.protocol === 'https:' ? 'wss' : (query('signalScheme') || query('scheme') || 'ws');
    return `${scheme}://${host}:${port}`;
  }

  function defaultWs() {
    try {
      if (state.ws && state.ws.url) return state.ws.url;
    } catch (_) {}
    const exact = query('ws') || query('signaling') || query('signal');
    if (exact) {
      const normalized = normalizeWsUrl(exact) || exact;
      try {
        const parsed = new URL(normalized, location.href);
        if (!(location.protocol === 'https:' && parsed.protocol === 'ws:')) return normalized;
        log('ignoring insecure explicit signaling URL on HTTPS page', normalized);
      } catch (_) {}
    }
    return proxyWsUrl();
  }

  function normalizeConnectionMode(value) {
    const mode = String(value || '').trim().toLowerCase();
    if (['lan', 'local', 'direct'].includes(mode)) return 'lan';
    if (['proxy', 'remote', 'relay'].includes(mode)) return 'proxy';
    return 'auto';
  }

  function connectionMode() {
    if (state.connectionModeOverride) return normalizeConnectionMode(state.connectionModeOverride);
    const fromQuery = query('route') || query('mode') || query('connectionMode');
    if (fromQuery) return normalizeConnectionMode(fromQuery);
    try {
      const saved = localStorage.getItem('gstglass-connection-mode') || localStorage.getItem('gstglass-signaling-route');
      if (saved) return normalizeConnectionMode(saved);
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

  function routeIcePriority(type, originalPriority) {
    const mode = connectionMode();
    const candidateType = String(type || '').toLowerCase();
    const original = Number.parseInt(originalPriority, 10);
    const componentBits = Number.isFinite(original) ? original & 0xff : 1;
    if (mode === 'proxy') {
      if (candidateType === 'relay') return 2130706176 + componentBits;
      if (candidateType === 'srflx' || candidateType === 'prflx') return 2122317568 + componentBits;
      if (candidateType === 'host') return 256 + componentBits;
    }
    if (mode === 'lan') {
      if (candidateType === 'host') return 2130706176 + componentBits;
      if (candidateType === 'srflx' || candidateType === 'prflx' || candidateType === 'relay') return 256 + componentBits;
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
    parts[3] = String(routeIcePriority(parts[typIndex + 1], parts[3]));
    return `${hasAttributePrefix ? 'a=' : ''}${parts.join(' ')}`;
  }

  function applyIceRoutePolicyToCandidate(candidate, scope = 'primary') {
    if (!candidate || connectionMode() === 'auto') return candidate;
    const init = typeof candidate.toJSON === 'function' ? candidate.toJSON() : candidate;
    if (!init || typeof init !== 'object' || !init.candidate) return candidate;
    const rewritten = rewriteIceCandidatePriority(init.candidate);
    if (rewritten === init.candidate) return init;
    if (jbufDebugEnabled()) log(`${scope} applied ${connectionMode()} ICE candidate priority`);
    return { ...init, candidate: rewritten };
  }

  function applyIceRoutePolicyToDescription(description, scope = 'primary') {
    if (!description || connectionMode() === 'auto' || !description.sdp) return description;
    let changed = 0;
    const sdp = String(description.sdp).split(/\r?\n/).map((line) => {
      if (!/^a=candidate:/i.test(line)) return line;
      const rewritten = rewriteIceCandidatePriority(line);
      if (rewritten !== line) changed += 1;
      return rewritten;
    }).join('\r\n');
    if (changed && jbufDebugEnabled()) log(`${scope} reprioritized ${changed} embedded ICE candidate(s) for ${connectionMode()}`);
    return { type: description.type, sdp };
  }

  function stunUrl() {
    const value = query('stun');
    if (value === '0' || value === 'none' || value === 'off') return '';
    return value || 'stun:stun.l.google.com:19302';
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
    // Mirror the exact same source of truth as the normal/video WebRTC socket.
    // This preserves ?ws=, ?signalHost=, ?signalPort=, ?signalScheme=, proxy paths,
    // and any future primary-signalling override instead of reconstructing from location.
    try {
      if (state.ws && state.ws.url) return state.ws.url;
    } catch (_) {}
    return defaultWs();
  }

  function buildSplitWsFromPrimary(port) {
    if (!port) return '';
    const primary = primaryWsUrlForSplit();
    try {
      const u = new URL(primary, location.href);
      u.port = String(port);
      return trimWsUrl(u.toString());
    } catch (err) {
      log('split audio could not mirror primary WS URL; falling back to page host', primary, err);
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

  function splitAudioWsUrl() {
    if (sharedSignalingEnabled()) return trimWsUrl(primaryWsUrlForSplit());
    const explicit = query('splitAudioWs') || query('audioWs') || String(configValue('splitAudioWsUrl', ''));
    const normalized = normalizeWsUrl(explicit);
    const cfgPort = splitAudioSignalingPort();
    const mirrored = buildSplitWsFromPrimary(cfgPort);

    if (normalized) {
      try {
        const u = new URL(normalized, location.href);
        const pageIsLoopback = isLoopbackHostName(location.hostname);
        const targetIsLoopback = isLoopbackHostName(u.hostname);
        const derivedPort = Number.parseInt(u.port || String(cfgPort || ''), 10);

        // Old configs could write ws://127.0.0.1:8190. That works only when
        // the browser is on the streamer. On proxied/FQDN pages, mirror the
        // primary signalling socket and only swap 8189 -> 8190.
        if (targetIsLoopback && !pageIsLoopback) {
          const rebuilt = buildSplitWsFromPrimary(derivedPort || cfgPort);
          log('split audio ignoring loopback WS URL for proxied page', normalized, '=>', rebuilt);
          return rebuilt;
        }

        // Never let a secure viewer open a browser-side ws:// socket, including
        // private-IP split-audio overrides. Mirror the already-secure primary
        // proxy URL instead. HAProxy may still forward this WSS connection to
        // the ordinary WS backend listener.
        if (location.protocol === 'https:' && u.protocol === 'ws:') {
          const rebuilt = buildSplitWsFromPrimary(derivedPort || cfgPort);
          log('split audio ignoring insecure browser WS URL on HTTPS page', normalized, '=>', rebuilt);
          return rebuilt;
        }

        return trimWsUrl(normalized);
      } catch (err) {
        log('split audio invalid explicit WS URL; mirroring primary WS URL', normalized, err);
      }
    }

    return mirrored;
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
    const url = splitAudioWsUrl() || 'no-url';
    const pcState = sa.pc ? (sa.pc.iceConnectionState || sa.pc.connectionState || 'pc') : 'no-pc';
    const wsState = sa.ws ? ['connecting', 'open', 'closing', 'closed'][sa.ws.readyState] || String(sa.ws.readyState) : 'no-ws';
    const producerCount = sa.producers ? sa.producers.size : 0;
    const err = sa.lastError ? ` err ${sa.lastError}` : '';
    const track = sa.lastTrackKind ? ` track ${sa.lastTrackKind}` : '';
    const ka = sa.keepAliveTimer ? ` ka ${sa.keepAliveCount || 0}` : '';
    return `${sa.status || 'idle'} ${wsState}/${pcState} producers ${producerCount} ${url}${track}${ka}${err}`;
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
    const route = state.signalingRoute === 'explicit' ? 'explicit' : 'proxy';
    return `signaling ${route} ${scheme} ${host}`;
  }

  function connectionModeStatusLine() {
    return `mode ${connectionMode().toUpperCase()} · ${signalingTransportStatusLine()} · ${mediaRoutePolicyLine()}`;
  }

  function updateConnectionModeControl() {
    const button = state.controller.routeButton;
    if (!button) return;
    const mode = connectionMode();
    button.textContent = mode.toUpperCase();
    button.classList.toggle('isLan', mode === 'lan');
    button.classList.toggle('isProxy', mode === 'proxy');
    button.setAttribute('aria-label', `Connection mode ${mode}. Activate to switch mode.`);
    button.setAttribute('aria-pressed', mode === 'auto' ? 'false' : 'true');
    button.title = `Connection mode: ${mode.toUpperCase()}\n${signalingTransportStatusLine()}\n${mediaRoutePolicyLine()}\nActivate to switch AUTO → LAN → PROXY.`;
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
    connect();
  }

  function setConnectionMode(mode, reason = 'control') {
    const next = normalizeConnectionMode(mode);
    const previous = connectionMode();
    state.connectionModeOverride = next;
    try {
      localStorage.setItem('gstglass-connection-mode', next);
      localStorage.setItem('gstglass-signaling-route', next);
    } catch (_) {}
    updateConnectionModeControl();
    if (next === previous) return next;
    setStatus(`Connection mode: ${next.toUpperCase()}`, `${signalingTransportStatusLine()} · ${mediaRoutePolicyLine()}`, 'warn');
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

    bar.append(playButton, muteButton, volumeInput, spacer, reconnectButton, routeButton, installButton, zoomButton, pinButton, fullscreenCtl);
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
      ctl.playButton.textContent = ctl.userPaused ? '▶' : '❚❚';
      ctl.playButton.title = ctl.userPaused ? 'Play' : 'Pause';
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

  function connect() {
    clearTimeout(state.reconnectTimer);
    const token = ++state.signalingAttemptToken;
    const url = defaultWs();
    state.signalingRoute = trimWsUrl(url) === trimWsUrl(proxyWsUrl()) ? 'proxy' : 'explicit';
    state.signalingUrl = url;
    updatePlayerControls();
    setStatus('Connecting via proxy…', url, 'warn');

    let ws;
    try {
      ws = new WebSocket(url);
      state.ws = ws;
    } catch (err) {
      state.ws = null;
      setStatus('Proxy signaling blocked', err && err.message ? err.message : String(err), 'bad');
      state.reconnectTimer = setTimeout(connect, 3000);
      return;
    }

    ws.addEventListener('open', () => {
      if (token !== state.signalingAttemptToken || state.ws !== ws) {
        try { ws.close(); } catch (_) {}
        return;
      }
      setStatus('Connected', 'Waiting for producer…', 'good');
      startKeepAlive();
      reconcileSplitAudio('primary-ws-open');
      updatePlayerControls();
    });

    ws.addEventListener('close', () => {
      if (token !== state.signalingAttemptToken || state.ws !== ws) return;
      state.ws = null;
      state.ready = false;
      stopKeepAlive();
      stopSession(false, { stopSplitAudio: true, reason: 'primary-ws-close' });
      setStatus('Disconnected', 'Reconnecting proxy signaling socket…', 'bad');
      state.reconnectTimer = setTimeout(connect, 3000);
    });

    ws.addEventListener('error', () => {
      if (token !== state.signalingAttemptToken || state.ws !== ws) return;
      setStatus('Proxy signaling error', 'Check WSS/HAProxy/forwarding.', 'bad');
    });

    ws.addEventListener('message', (ev) => {
      if (token !== state.signalingAttemptToken || state.ws !== ws) return;
      let msg;
      try { msg = JSON.parse(ev.data); } catch (err) { log('bad message', err, ev.data); return; }
      handleMessage(msg);
    });
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
    if (!state.ws || state.ws.readyState !== WebSocket.OPEN) return connect();
    stopSession(false, { preserveSplitAudio: true });
    state.remotePeerId = peerId;
    state.pendingIce = [];
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
    const rawDesc = typeof sdp === 'string' ? { type: 'offer', sdp } : sdp;
    const routedDesc = applyIceRoutePolicyToDescription(rawDesc, 'primary remote');
    const desc = rewriteRemoteMediaStreamIds(routedDesc, 'primary remote');
    await state.pc.setRemoteDescription(desc);
    if (desc.type === 'offer') {
      const answer = await state.pc.createAnswer();
      await state.pc.setLocalDescription(answer);
      const local = applyIceRoutePolicyToDescription(state.pc.localDescription, 'primary outbound');
      send({
        type: 'peer',
        sessionId: state.sessionId,
        sdp: local.toJSON ? local.toJSON() : { type: local.type, sdp: local.sdp }
      }, true);
    }
  }

  async function handleRemoteIce(ice) {
    if (!state.pc || !ice) return;
    const routedIce = applyIceRoutePolicyToCandidate(ice, 'primary remote');
    try { await state.pc.addIceCandidate(routedIce && routedIce.candidate ? routedIce : null); }
    catch (err) { log('addIceCandidate failed', err); }
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
    const addresses = candidates.map((candidate) => String(candidate.address || candidate.ip || candidate.ipAddress || ''));
    const privateAddress = addresses.some((address) => /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|fc|fd|fe80:)/i.test(address));
    if (types.length && types.every((type) => type === 'host') && privateAddress) {
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
          const formattedProto = proto || mediaRoute || pathKind ? `ICE media: ${[pathKind, proto, mediaRoute].filter(Boolean).join(' · ')}` : '';
          if (formattedProto && formattedProto !== state.lastIceProtocol) {
            state.lastIceProtocol = formattedProto;
            setStatus('Live', state.lastIceProtocol, 'good');
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
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') { syncScreenWakeLock('visibility-visible', true); scheduleFullscreenRenderRecovery('visibility-visible', 200); }
    else syncScreenWakeLock('visibility-hidden');
  });
  window.addEventListener('pageshow', () => { syncScreenWakeLock('pageshow', true); scheduleFullscreenRenderRecovery('pageshow', 200); });
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
    splitStopSession(false);
    sa.status = 'starting-consumer';
    sa.remotePeerId = peerId;
    sa.pendingIce = [];
    const pc = new RTCPeerConnection(makeRtcConfig());
    sa.pc = pc;
    window.audioPc = pc;

    pc.addEventListener('icecandidate', (ev) => {
      if (!ev.candidate) return;
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
    const rawDesc = typeof sdp === 'string' ? { type: 'offer', sdp } : sdp;
    const desc = applyIceRoutePolicyToDescription(rawDesc, 'split audio remote');
    await sa.pc.setRemoteDescription(desc);
    if (desc.type === 'offer') {
      const answer = await sa.pc.createAnswer();
      await sa.pc.setLocalDescription(answer);
      const local = applyIceRoutePolicyToDescription(sa.pc.localDescription, 'split audio outbound');
      splitSend({ type: 'peer', sessionId: sa.sessionId, sdp: local.toJSON ? local.toJSON() : { type: local.type, sdp: local.sdp } }, true);
    }
  }

  async function splitHandleRemoteIce(ice) {
    const sa = state.splitAudio;
    if (!sa.pc || !ice) return;
    const routedIce = applyIceRoutePolicyToCandidate(ice, 'split audio remote');
    try { await sa.pc.addIceCandidate(routedIce && routedIce.candidate ? routedIce : null); } catch (err) { log('split audio addIceCandidate failed', err); }
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
    if (sa.reconnectTimer) { clearTimeout(sa.reconnectTimer); sa.reconnectTimer = null; }
    if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
    splitStopKeepAlive();
    sa.status = reason;
    sa.ready = false;
    splitStopSession(true);
    if (sa.ws) { try { sa.ws.close(); } catch (_) {} }
    sa.ws = null;
    sa.url = '';
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

  function splitConnectAudio(reason = 'connect') {
    if (!splitAudioEnabled()) return false;
    const sa = state.splitAudio;
    const url = splitAudioWsUrl();
    if (!url) {
      sa.status = 'no-url';
      sa.lastError = 'missing split audio WS URL/port';
      log('split audio disabled: missing WS URL/port', window.GST_GLASS_CONFIG || {});
      updatePlayerControls();
      return false;
    }

    if (sa.ws && (sa.ws.readyState === WebSocket.OPEN || sa.ws.readyState === WebSocket.CONNECTING)) {
      if (sa.url === url) return true;
      log('split audio reconnecting for URL change', sa.url, '=>', url);
      splitStopKeepAlive();
      try { sa.ws.close(); } catch (_) {}
      sa.ws = null;
      splitStopSession(false);
    }

    if (sa.reconnectTimer) { clearTimeout(sa.reconnectTimer); sa.reconnectTimer = null; }
    splitStopKeepAlive();
    sa.url = url;
    sa.status = 'connecting';
    sa.lastError = '';
    sa.connectStartedAt = performance.now();
    sa.trackReceivedAt = 0;
    sa.lastInboundStats = null;
    beginWatchdogWarmup(`split-connect:${reason}`);
    log('split audio connecting', url, reason);
    updatePlayerControls();
    try {
      sa.ws = new WebSocket(url);
      if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
      sa.connectTimer = setTimeout(() => {
        if (sa.ws && sa.ws.readyState === WebSocket.CONNECTING) {
          sa.status = 'connect-timeout';
          sa.lastError = `WebSocket still CONNECTING after 7000ms; URL=${url}; primary=${primaryWsUrlForSplit()}`;
          log('split audio WebSocket connect timeout', url, 'primary', primaryWsUrlForSplit());
        }
      }, 7000);
    } catch (err) {
      sa.status = 'error';
      sa.lastError = err && err.message ? err.message : String(err);
      log('split audio WebSocket create failed', url, err);
      return false;
    }

    sa.ws.addEventListener('open', () => {
      if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
      sa.ready = false;
      sa.status = 'ws-open';
      sa.lastError = '';
      beginWatchdogWarmup('split-ws-open');
      log('split audio signaling connected', url);
      updatePlayerControls();
      splitStartKeepAlive('ws-open');
      setTimeout(() => splitRequestProducerList('open+250ms'), 250);
      setTimeout(() => splitRequestProducerList('open+1000ms'), 1000);
    });
    sa.ws.addEventListener('close', (ev) => {
      if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
      const shouldReconnect = splitAudioEnabled() && sa.url === url;
      sa.ready = false;
      sa.status = shouldReconnect ? 'reconnecting' : 'closed';
      sa.lastError = ev && ev.reason ? ev.reason : '';
      splitStopKeepAlive();
      splitStopSession(false);
      log('split audio signaling closed', url, ev.code, ev.reason || '', shouldReconnect ? 'retrying' : 'not retrying');
      updatePlayerControls();
      if (shouldReconnect) sa.reconnectTimer = setTimeout(() => splitConnectAudio('retry'), 1500);
    });
    sa.ws.addEventListener('error', (ev) => {
      if (sa.connectTimer) { clearTimeout(sa.connectTimer); sa.connectTimer = null; }
      sa.status = 'error';
      sa.lastError = 'WebSocket error';
      log('split audio signaling error', url, ev);
      updatePlayerControls();
    });
    sa.ws.addEventListener('message', (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch (err) { log('split audio bad message', err, ev.data); return; }
      if (jbufDebugEnabled()) log('split audio msg', msg.type, msg);
      splitHandleMessage(msg);
    });
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
    play: () => { state.controller.userPaused = false; applyLogicalMediaState('console-play'); },
    pause: () => { state.controller.userPaused = true; applyLogicalMediaState('console-pause'); },
    mute: () => { state.controller.userMuted = true; applyLogicalMediaState('console-mute'); },
    unmute: () => { state.controller.userMuted = false; applyLogicalMediaState('console-unmute'); },
    volume: (value) => { const n = Number(value); if (Number.isFinite(n)) state.controller.volume = Math.max(0, Math.min(n, 1)); applyLogicalMediaState('console-volume'); },
    route: (mode) => setConnectionMode(mode, 'console'),
    state: () => ({ paused: state.controller.userPaused, muted: state.controller.userMuted, volume: state.controller.volume, connectionMode: connectionMode(), mediaRoutePolicy: mediaRoutePolicyLine(), signalingRoute: state.signalingRoute, signalingUrl: state.signalingUrl, signalingTransport: signalingTransportStatusLine(), screenWakeLock: screenWakeLockLine(), splitAudio: splitAudioStatusLine(), splitSync: splitSyncStatusLine(), videoPaused: video.paused, audioPaused: audio.paused, videoMuted: video.muted, audioMuted: audio.muted })
  };

  startConfigReloadTimer();
  registerPwaServiceWorker();

  if (jbufDebugEnabled()) {
    log('player config', playerConfigLine(), window.GST_GLASS_CONFIG || {});
  }

  updatePlayerControls();
  connect();
  reconcileSplitAudio('startup');
})();

// audio jbuf video jbuf GstGlassJbuf AV render decoupled media elements split av pipelines split audio player controller dual watchdog warmup split offset baseline PWA install service worker pinch zoom pan proxy WSS direct ICE
