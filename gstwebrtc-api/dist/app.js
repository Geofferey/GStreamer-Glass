(() => {
  const $ = (id) => document.getElementById(id);
  const wsUrl = $('wsUrl');
  const stunUrl = $('stunUrl');
  const connectBtn = $('connectBtn');
  const keepAliveSec = $('keepAliveSec');
  const refreshBtn = $('refreshBtn');
  const stopBtn = $('stopBtn');
  const producerList = $('producerList');
  const video = $('video');
  const logBox = $('log');
  const status = $('status');
  const localPeer = $('localPeer');
  const remotePeer = $('remotePeer');
  const sessionIdEl = $('sessionId');
  const pcState = $('pcState');
  const iceState = $('iceState');

  const state = {
    ws: null,
    peerId: null,
    ready: false,
    producers: new Map(),
    pc: null,
    sessionId: null,
    remotePeerId: null,
    pendingIce: [],
    autoStarted: false,
    statsTimer: null,
    keepAliveTimer: null,
    keepAliveCount: 0
  };

  function getQueryParam(name) {
    try { return new URLSearchParams(location.search).get(name); } catch (_) { return null; }
  }

  function defaultWs() {
    const explicit = getQueryParam('ws') || getQueryParam('signaling') || getQueryParam('signal');
    if (explicit) return explicit;

    const hostParam = getQueryParam('signalHost') || getQueryParam('host');
    const portParam = getQueryParam('signalPort') || getQueryParam('port');
    const host = hostParam || (location.hostname && location.hostname !== '0.0.0.0' ? location.hostname : '127.0.0.1');
    const port = portParam || '8189';
    const schemeParam = getQueryParam('signalScheme') || getQueryParam('scheme');
    const scheme = schemeParam || (location.protocol === 'https:' ? 'wss' : 'ws');
    return `${scheme}://${host}:${port}`;
  }

  function defaultKeepAliveSeconds() {
    const value = getQueryParam('keepalive') || getQueryParam('ka') || '15';
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) && parsed >= 0 ? Math.min(parsed, 300) : 15;
  }

  function getKeepAliveMs() {
    const parsed = Number.parseInt(keepAliveSec && keepAliveSec.value ? keepAliveSec.value : '15', 10);
    if (!Number.isFinite(parsed) || parsed <= 0) return 0;
    return Math.max(5, Math.min(parsed, 300)) * 1000;
  }

  function stopKeepAlive() {
    if (state.keepAliveTimer) clearInterval(state.keepAliveTimer);
    state.keepAliveTimer = null;
  }

  function startKeepAlive() {
    stopKeepAlive();
    const interval = getKeepAliveMs();
    if (!interval) {
      log('websocket keepalive disabled', 'warn');
      return;
    }
    state.keepAliveTimer = setInterval(() => {
      if (!state.ws || state.ws.readyState !== WebSocket.OPEN) return;
      state.keepAliveCount += 1;
      // Browser JavaScript cannot send native WebSocket ping frames. Use a
      // valid signalling-protocol request so HAProxy sees real bidirectional
      // traffic without annoying the GStreamer signalling server.
      send({ type: 'list' }, true);
      if (state.keepAliveCount % 4 === 0) send({ type: 'listConsumers' }, true);
      log(`keepalive tick ${state.keepAliveCount} (${interval / 1000}s)`);
    }, interval);
    log(`websocket keepalive enabled every ${interval / 1000}s`);
  }

  function log(message, level = 'info') {
    const stamp = new Date().toLocaleTimeString();
    logBox.textContent += `[${stamp}] ${level.toUpperCase()} ${message}\n`;
    logBox.scrollTop = logBox.scrollHeight;
  }

  function setStatus(text, cls) {
    status.textContent = text;
    status.className = `status ${cls}`;
  }

  function shortId(id) {
    if (!id) return '—';
    return id.length > 12 ? `${id.slice(0, 8)}…${id.slice(-4)}` : id;
  }

  function updateSessionUi() {
    localPeer.textContent = shortId(state.peerId);
    remotePeer.textContent = shortId(state.remotePeerId);
    sessionIdEl.textContent = shortId(state.sessionId);
    pcState.textContent = state.pc ? state.pc.connectionState : '—';
    iceState.textContent = state.pc ? state.pc.iceConnectionState : '—';
  }

  function send(obj, allowBeforeReady = false) {
    if (!state.ws || state.ws.readyState !== WebSocket.OPEN) {
      log(`cannot send ${obj.type}; websocket is not open`, 'warn');
      return false;
    }
    if (!state.ready && !allowBeforeReady && obj.type !== 'setPeerStatus') {
      log(`delaying/ignoring ${obj.type}; listener is not ready yet`, 'warn');
      return false;
    }
    state.ws.send(JSON.stringify(obj));
    log(`→ ${obj.type} ${obj.peerId ? '(' + shortId(obj.peerId) + ')' : ''}`);
    return true;
  }

  function normalizePeer(peer, assumedRole) {
    if (!peer || typeof peer !== 'object') return null;
    const id = peer.peerId || peer.id;
    if (!id || id === state.peerId) return null;
    let roles = Array.isArray(peer.roles) ? [...peer.roles] : [];
    if (assumedRole && !roles.includes(assumedRole)) roles.push(assumedRole);
    return {
      id,
      roles,
      meta: peer.meta || {}
    };
  }

  function producerName(peer) {
    const meta = peer && peer.meta;
    if (meta && typeof meta === 'object') {
      return meta.name || meta.title || meta.label || peer.id;
    }
    if (typeof meta === 'string') return meta;
    return peer.id;
  }

  function maybeAutoStart() {
    if (state.autoStarted || state.pc || state.sessionId || !state.producers.size) return;
    const first = [...state.producers.values()][0];
    if (!first) return;
    state.autoStarted = true;
    log(`auto-viewing first producer ${shortId(first.id)}`);
    startConsumer(first.id);
  }

  function renderProducers() {
    producerList.innerHTML = '';
    if (!state.producers.size) {
      producerList.className = 'producerList empty';
      producerList.textContent = 'No producers yet.';
      return;
    }
    producerList.className = 'producerList';
    [...state.producers.values()].forEach((peer) => {
      const row = document.createElement('div');
      row.className = 'producer';
      const text = document.createElement('div');
      const name = document.createElement('div');
      name.className = 'producerName';
      name.textContent = producerName(peer);
      const id = document.createElement('div');
      id.className = 'producerId';
      id.textContent = peer.id;
      text.appendChild(name);
      text.appendChild(id);
      const btn = document.createElement('button');
      btn.textContent = state.remotePeerId === peer.id ? 'Viewing' : 'View';
      btn.addEventListener('click', () => startConsumer(peer.id));
      row.appendChild(text);
      row.appendChild(btn);
      producerList.appendChild(row);
    });
    maybeAutoStart();
  }

  function addProducer(peerLike, assumedRole = 'producer') {
    const peer = normalizePeer(peerLike, assumedRole);
    if (!peer || !peer.roles.includes('producer')) return;
    state.producers.set(peer.id, peer);
    renderProducers();
  }

  function removeProducer(peerId) {
    if (state.producers.delete(peerId)) renderProducers();
    if (state.remotePeerId === peerId) stopSession(false);
  }

  function parseProducerList(msg) {
    state.producers.clear();
    const producers = msg.producers || msg.peers || [];
    if (Array.isArray(producers)) {
      producers.forEach((p) => addProducer(p, 'producer'));
    } else if (producers && typeof producers === 'object') {
      Object.entries(producers).forEach(([id, value]) => addProducer({ peerId: id, ...(value || {}) }, 'producer'));
    }
    renderProducers();
    log(`producer list updated: ${state.producers.size}`);
  }

  function connect() {
    if (state.ws && state.ws.readyState === WebSocket.OPEN) {
      refreshStreams();
      return;
    }

    const url = wsUrl.value.trim() || defaultWs();
    setStatus('connecting', 'warn');
    state.ready = false;
    state.ws = new WebSocket(url);

    state.ws.addEventListener('open', () => {
      setStatus('connected', 'online');
      log(`websocket connected: ${url}`);
      startKeepAlive();
    });

    state.ws.addEventListener('close', () => {
      state.ready = false;
      stopKeepAlive();
      setStatus('offline', 'offline');
      log('websocket closed', 'warn');
    });

    state.ws.addEventListener('error', () => {
      setStatus('error', 'offline');
      log('websocket error', 'error');
    });

    state.ws.addEventListener('message', (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        log(`← ${msg.type}`);
        handleMessage(msg);
      } catch (err) {
        log(`bad signaling message: ${err.message}`, 'error');
      }
    });
  }

  function refreshStreams() {
    send({ type: 'list' }, true);
    send({ type: 'listConsumers' }, true);
  }

  function makeRtcConfig() {
    const stun = stunUrl.value.trim();
    return stun ? { iceServers: [{ urls: stun }] } : { iceServers: [] };
  }

  async function startConsumer(peerId) {
    if (!state.ws || state.ws.readyState !== WebSocket.OPEN) {
      connect();
      return;
    }
    stopSession(false);
    state.remotePeerId = peerId;
    state.pendingIce = [];
    updateSessionUi();

    const pc = new RTCPeerConnection(makeRtcConfig());
    state.pc = pc;

    pc.addEventListener('connectionstatechange', () => {
      updateSessionUi();
      renderProducers();
      log(`peer connection: ${pc.connectionState}`);
    });
    pc.addEventListener('iceconnectionstatechange', () => {
      updateSessionUi();
      log(`ice connection: ${pc.iceConnectionState}`);
    });
    pc.addEventListener('icegatheringstatechange', () => log(`ice gathering: ${pc.iceGatheringState}`));
    pc.addEventListener('icecandidate', (ev) => {
      if (!ev.candidate) return;
      const candidate = ev.candidate.toJSON ? ev.candidate.toJSON() : ev.candidate;
      if (state.sessionId) {
        send({ type: 'peer', sessionId: state.sessionId, ice: candidate }, true);
      } else {
        state.pendingIce.push(candidate);
      }
    });
    pc.addEventListener('track', (ev) => {
      const stream = ev.streams && ev.streams[0] ? ev.streams[0] : new MediaStream([ev.track]);
      video.srcObject = stream;
      video.play().catch((err) => log(`video play blocked: ${err.message}`, 'warn'));
      log(`received ${ev.track.kind} track`);
    });

    startStatsTimer();
    log(`requesting session with producer ${peerId}`);
    send({ type: 'startSession', peerId }, true);
  }

  function flushIce() {
    if (!state.sessionId || !state.pendingIce.length) return;
    state.pendingIce.splice(0).forEach((ice) => send({ type: 'peer', sessionId: state.sessionId, ice }, true));
  }

  async function handleRemoteSdp(sdp) {
    if (!state.pc) throw new Error('received SDP without active peer connection');
    const desc = typeof sdp === 'string' ? { type: 'offer', sdp } : sdp;
    await state.pc.setRemoteDescription(desc);
    log(`remote SDP: ${desc.type}`);

    if (desc.type === 'offer') {
      const answer = await state.pc.createAnswer();
      await state.pc.setLocalDescription(answer);
      const local = state.pc.localDescription;
      send({
        type: 'peer',
        sessionId: state.sessionId,
        sdp: local.toJSON ? local.toJSON() : { type: local.type, sdp: local.sdp }
      }, true);
      log('answer sent');
    }
  }

  async function handleRemoteIce(ice) {
    if (!state.pc || !ice) return;
    try {
      await state.pc.addIceCandidate(ice.candidate ? ice : null);
      log('remote ICE candidate added');
    } catch (err) {
      log(`addIceCandidate failed: ${err.message}`, 'warn');
    }
  }

  function stopStatsTimer() {
    if (state.statsTimer) clearInterval(state.statsTimer);
    state.statsTimer = null;
  }

  function startStatsTimer() {
    stopStatsTimer();
    state.statsTimer = setInterval(async () => {
      if (!state.pc || !['connected', 'completed'].includes(state.pc.iceConnectionState)) return;
      try {
        const stats = await state.pc.getStats();
        let selected = null;
        stats.forEach((report) => {
          if (report.type === 'candidate-pair' && report.selected) selected = report;
        });
        if (!selected) return;
        const local = stats.get(selected.localCandidateId);
        const remote = stats.get(selected.remoteCandidateId);
        if (local || remote) {
          const proto = (local && local.protocol) || (remote && remote.protocol) || 'unknown';
          log(`selected ICE pair protocol=${proto} local=${local ? local.address + ':' + local.port : '?'} remote=${remote ? remote.address + ':' + remote.port : '?'}`);
        }
      } catch (_) {}
    }, 3000);
  }

  function stopSession(notify = true) {
    if (notify && state.sessionId) {
      send({ type: 'endSession', sessionId: state.sessionId }, true);
    }
    stopStatsTimer();
    if (state.pc) {
      try { state.pc.close(); } catch (_) {}
    }
    state.pc = null;
    state.sessionId = null;
    state.remotePeerId = null;
    state.pendingIce = [];
    video.srcObject = null;
    updateSessionUi();
    renderProducers();
  }

  function handleMessage(msg) {
    switch (msg.type) {
      case 'welcome':
        state.peerId = msg.peerId || state.peerId;
        localPeer.textContent = shortId(state.peerId);
        send({
          type: 'setPeerStatus',
          roles: ['listener'],
          meta: { name: 'GStreamer Glass Browser Viewer' },
          peerId: state.peerId
        }, true);
        break;

      case 'peerStatusChanged': {
        if (msg.peerId === state.peerId || msg.id === state.peerId) {
          if (Array.isArray(msg.roles) && msg.roles.includes('listener')) {
            state.ready = true;
            refreshStreams();
          }
        } else {
          const peer = normalizePeer(msg);
          if (peer && peer.roles.includes('producer')) {
            addProducer(peer, 'producer');
          } else if (peer) {
            removeProducer(peer.id);
          }
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
        updateSessionUi();
        flushIce();
        break;

      case 'peer':
        if (msg.sessionId && state.sessionId && msg.sessionId !== state.sessionId) return;
        Promise.resolve()
          .then(() => msg.sdp ? handleRemoteSdp(msg.sdp) : null)
          .then(() => msg.ice ? handleRemoteIce(msg.ice) : null)
          .then(flushIce)
          .catch((err) => log(`peer handling failed: ${err.message}`, 'error'));
        break;

      case 'endSession':
        if (!msg.sessionId || msg.sessionId === state.sessionId) stopSession(false);
        break;

      case 'error':
        log(`server error: ${msg.details || msg.error || JSON.stringify(msg)}`, 'error');
        break;

      default:
        log(`unhandled message: ${JSON.stringify(msg)}`);
        break;
    }
  }

  wsUrl.value = defaultWs();
  if (keepAliveSec) keepAliveSec.value = String(defaultKeepAliveSeconds());
  connectBtn.addEventListener('click', connect);
  refreshBtn.addEventListener('click', refreshStreams);
  stopBtn.addEventListener('click', () => stopSession(true));
  window.addEventListener('beforeunload', () => {
    stopKeepAlive();
    stopSession(true);
  });
  renderProducers();
  updateSessionUi();
  log('viewer v3.7.24 loaded; signalling defaults to TCP/WebSocket 8189; media should negotiate separately over UDP through ICE');
  log(`default signalling URL: ${wsUrl.value}`);
  log(`default keepalive interval: ${keepAliveSec ? keepAliveSec.value : '15'}s`);
  if (wsUrl.value.includes(':8443')) log('8443 detected. This usually means a stale query string, stale browser cache, or old saved UI value. Expected signalling port is 8189.', 'warn');
  if (wsUrl.value.startsWith('wss://')) log('Using WSS. HAProxy must terminate TLS before forwarding clear WebSocket traffic to GStreamer, or configure GStreamer signalling cert/key.', 'warn');
})();
