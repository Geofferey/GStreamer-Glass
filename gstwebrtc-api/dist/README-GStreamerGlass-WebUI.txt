GStreamer Glass Direct WebRTC Web UI
Version: 3.7.52f45-honest-video-sender-queue

Android screen wake lock:
- Holds an explicit Screen Wake Lock while the live video is playing, covering
  both windowed playback and the Android-safe custom player fullscreen mode.
- Reacquires the lock after fullscreen enter/exit, orientation changes,
  pageshow/focus, and the hidden-to-visible transition Android Chromium may
  produce while changing fullscreen surfaces or waking the screen.
- Releases the lock on user pause, stream stop, page hiding, and unload.
- The stats overlay and GstGlassPlayer.state() report `screen wake active`,
  `released`, `denied`, or `unsupported` for diagnosis.
- Enabled by default through screenWakeLock. Optional URL opt-out:
  `?wakeLock=0`, `?screenWakeLock=0`, or `?keepAwake=0`.
- The browser API requires a secure context (HTTPS or localhost). The player
  keeps working normally when the API is unavailable; only keep-awake is lost.

Route-aware ICE candidate priority:
- PROXY remains anchored to the WSS address derived from the domain/address in
  the browser address bar (or the explicit proxyWs override).
- PROXY assigns public srflx/prflx/relay candidates higher signaled priority
  than host candidates in both SDP and trickle ICE, encouraging the same public
  pair observed before LAN detection was introduced.
- LAN assigns host candidates highest priority and disables local STUN.
- AUTO leaves native ICE candidate priorities untouched.
- Host candidates are retained at low priority in PROXY rather than deleted,
  preventing the complete LAN connection failure seen with strict filtering.
- A private pair selected only after the public path fails is explicitly shown
  as `PROXY FALLBACK: DIRECT LAN MEDIA`.

Original route-switch lifecycle restored:
- Comparing against f21 showed that its AUTO/LAN/PROXY switch completely
  restarted signaling, primary media, split-audio signaling, and split-audio
  media. Later builds only replaced the PeerConnections on the existing socket.
- Every mode change now performs the same complete teardown/reconnect as f21,
  so selecting PROXY behaves like selecting it and refreshing the page.
- ICE candidates remain unfiltered, matching the implementation that produced
  the observed public srflx-to-srflx pair.
- Browser signaling remains proxy-safe WSS; private-IP ws:// probing is not
  restored.

PROXY mode on the same LAN:
- Restores normal ICE host candidates because forcing the public/STUN path from
  inside the LAN fails on routers without NAT hairpin support.
- PROXY means the signaling socket uses the proxy WSS route. WebRTC media is a
  separate ICE flow and may correctly optimize to a direct LAN candidate pair.
- Stats now put the signaling route first and label this case as
  `DIRECT LAN MEDIA (signaling remains PROXY WSS)` to prevent ambiguity.
- Off-LAN mobile viewers naturally use public ICE. Forcing relayed media on LAN
  requires a TURN server; HAProxy only proxies HTTP/WebSocket signaling.

Safe AUTO / LAN / PROXY selector:
- Restores the AUTO/LAN/PROXY switch to the full-width media bar and persists
  the selected mode in the browser.
- Switching mode recreates both the primary and split-audio PeerConnections,
  preventing an old LAN candidate pair from surviving a switch to PROXY.
- All three modes keep browser signaling on the page/proxy WSS endpoint. None
  opens ws:// to a private LAN address, so the selector does not reintroduce
  mixed-content or Chromium Local Network Access issues.
- AUTO uses normal ICE selection with STUN.
- LAN disables STUN and uses host candidates for LAN-preferred ICE.
- PROXY uses relay-only ICE when a TURN URL is configured. Without TURN, media
  uses normal ICE and may remain direct LAN while signaling stays on proxy WSS.
- Optional URL/config controls: route=auto|lan|proxy, turnUrl, turnUsername,
  and turnCredential. DevTools also supports GstGlassPlayer.route('proxy').

Proxy-safe signaling and direct LAN media:
- Removes all automatic browser connections to ws:// private-IP signaling ports
  and all Local Network Access probes.
- An HTTPS viewer always opens wss:// to the page/proxy host. HAProxy can still
  terminate TLS and forward ordinary ws:// to Glass on its backend network.
- An insecure explicit ?ws= URL is ignored when the page itself is HTTPS.
- WebRTC media continues to negotiate independently through ICE. A host address
  such as 10.0.0.25:49433 is a media candidate—not the signaling WebSocket.
- The stats overlay now separates `signaling proxy WSS proxy-host` from
  `ICE media: DIRECT LAN`, `DIRECT P2P`, or `TURN RELAY`, including candidate
  endpoints when the browser exposes them.
- Forcing WebRTC media through a proxy requires a TURN relay and relay-only ICE
  policy. HAProxy's HTTP/WebSocket forwarding does not relay WebRTC UDP media.

Video pinch zoom:
- Pinch directly on the video to zoom continuously from 1x through 4x.
- Drag with one finger while zoomed to pan around the picture; movement is
  clamped so the transformed video cannot be dragged completely off-screen.
- A reset button showing the current zoom appears in the media bar only while
  zoomed. Pinch/pan completion suppresses the synthetic tap so it cannot
  accidentally toggle fullscreen.
- Zoom is re-constrained across rotation, resize, and fullscreen transitions.
- Optional URL/config override: videoZoomMax or zoomMax (2x through 8x).

Progressive Web App:
- Adds a portable relative-scope web manifest and service worker so /live/ can
  be installed as GStreamer Glass Live when served over HTTPS (or localhost).
- Uses the supplied Glass2Glass Streamer artwork for standard and Android-safe
  maskable 192px/512px icons.
- Shows an Install button in the media bar only when the browser reports that
  the player is installable; it disappears after installation/in standalone.
- Caches only the player shell for offline launch. gstglass-config.js remains
  network-only so signaling endpoints and live settings cannot become stale.
- Firefox and browsers without a programmatic install prompt can still use
  their normal browser menu installation flow when supported.

Audio, keepalive, and RTC stats fixes:
- Ignores expected AbortError play/pause races instead of falsely reporting
  "Click to enable audio" and retries once when the same live source remains.
- Only genuine browser autoplay rejection now produces the enable-audio prompt.
- Detects current ICE candidate pairs through transport.selectedCandidatePairId,
  with legacy, nominated, and active-pair fallbacks.
- Calculates actual receive bitrate from inbound RTP byte deltas.
- Shows primary/video and split-audio signaling keepalive counters plus whether
  the listener sockets use shared or separate signaling endpoints.

Full-width media controls:
- Replaces the floating pill with a conventional full-width bottom control bar.
- Provides play/pause, mute, volume, split-audio reconnect, diagnostic pin, and
  enter/exit fullscreen controls in every playback topology.
- Pin keeps the media bar, status overlay, stats, and debug link visible until
  explicitly unpinned.
- Fullscreen follows browser state, exits correctly, and continues using the
  Android-safe container fullscreen path.

Player UI auto-hide:
- Normal controls, stats, links, and informational overlays are completely
  invisible while playback is active and the interface is idle.
- Pointer, touch, keyboard, or focus interaction reveals them for 2.2 seconds.
- Paused controls and connection/error alerts remain visible and usable.

Android Chromium fullscreen latency fix:
- Fullscreens the complete player container instead of the video element.
- Avoids Android Chromium's native video fullscreen surface, whose post-WebRTC
  render queue can add perceived latency without changing JBUF/RTC statistics.
- Leaves Windows and Firefox fullscreen behavior unchanged.

Adds support for the opt-in unified A/V publisher laboratory topology.

In this mode, independent video and audio capture/encoding gst-launch processes publish encoded RTP over localhost to a third publisher process. That publisher owns one webrtcsink instance with video_0 and audio_0, so the browser consumes one producer and one PeerConnection.

The player intentionally treats this topology as a normal single-producer session and does not open the separate split-audio WebSocket. Existing split two-producer, shared-signalling, separate-signalling, keepalive, free-run, and watchdog behavior is unchanged when the experimental checkbox is off.


Live Edge / overlay cleanup (f29):
- Stats overlay headline shows receiver-side LIVE EDGE estimate in ms with 🟢/🟡/🔴.
- Defaults: green <= 50 ms, yellow <= 120 ms, red > 120 ms; query/config overrides liveEdgeGreenMs and liveEdgeYellowMs.
- Compact Glass overlay shows only Live, Delayed, or De-synced while media is playing.
- Shared signaling is represented once rather than as two signaling ports/listeners.
- Bitrate, ICE route, RTT, FPS, loss, jitter buffers, queue/recovery, A/V skew/sync health, decode/drop/freeze counts, keepalive and wake-lock diagnostics remain in Stats overlay.


Fullscreen blank-video recovery:
- Verifies that the browser actually presents a video frame after track attach, fullscreen transitions, visibility restore, and orientation changes.
- If WebRTC remains live but the fullscreen compositor surface is blank, re-attaches only the existing video MediaStream. This does not renegotiate the peer connection or interrupt split audio.
- Uses requestVideoFrameCallback when available rather than trusting readyState or jitter-buffer statistics alone.

Hardware decode path:
- Keeps WebRTC video directly attached to the native HTML video element and marks the remote track as motion content.
- This is the browser path capable of hardware decoding. Browser WebRTC APIs do not provide a portable switch to force hardware decode; final decoder selection is controlled by the browser, OS, codec, and device.

Corrected Live Edge estimate (f31):
- Live Edge now represents excess receiver holdback rather than total path latency.
- Formula: max(0, video JBUF window + split A/V drift beyond learned baseline - RTT).
- Normal learned A/V offset is not penalized.
- Removed received-minus-decoded frame backlog from the estimate because cumulative decode counters produced false red delay states.

Rolling-average Live Edge (f32):
- The headline Live Edge value is now a five-second rolling average rather than a one-second instantaneous sample.
- Each sample is max(0, video JBUF window + positive A/V drift above the learned baseline - RTT).
- RTT, the learned A/V offset, and ordinary jitter around the expected floor do not count as excess latency.
- The player averages those non-negative excess samples over the active window, so one-second WIN/RTT jitter does not flip the headline state.
- The Stats overlay labels the metric as LIVE EDGE AVG and shows the active averaging window.
- Query/config override: liveEdgeAverageSec (1-30 seconds, default 5).



Live Edge split-audio guard (f33):
- Live Edge no longer ignores a catastrophic raw audio/video offset merely
  because the automatic baseline is still warming up or unlocked.
- Before a baseline is learned, the larger of JBUF max and the configured split
  A/V drift warning is treated as the expected startup allowance.
- Excess beyond that allowance contributes to the rolling Live Edge average
  immediately and forces the compact state to De-synced.
- Automatic baseline learning rejects implausibly large offsets instead of
  teaching the player that a one-second audio lead is normal.
- Entering or clearing a hard de-sync resets the five-second rolling window so
  stale healthy samples cannot hide the current condition.


f34 application controls
------------------------
- Player tab exposes Live avg sec (1-30), Green <= ms, and Yellow <= ms.
- Values persist in the GStreamer Glass application settings and are written to gstglass-config.js.
- Debug URL overrides include the same Live Edge settings.
- Watchdog warmup now accepts 0-600 seconds; the browser no longer clamps it to 60 seconds.


3.7.52f40 - Separate MediaStreams experiment
- Transport option: Combined A/V MediaStream (default) or Separate audio/video MediaStreams (experimental).
- Separate mode is intentionally player-side SDP rewriting; the gst-launch pipeline remains one producer/PeerConnection.
- Video and audio MediaStream IDs are configurable. Existing MediaStreamTrack IDs are preserved.
- The player uses separate video/audio HTML elements in this mode so it does not recombine the tracks after SDP separation.


3.7.52f44 - Explicit HTML media-element toggle
- Player tab now exposes Separate video and audio HTML media elements as a checkbox.
- A/V MediaStream grouping (SDP/MSID) and HTML element rendering are independent.
- Turning the checkbox off recombines received audio/video tracks into one MediaStream on the video element, even when the SDP uses separate MSIDs.
- Turning it on renders video and audio through distinct HTML media elements.
- Existing f40-f42 settings with separate MSIDs migrate to enabled once to preserve the previously forced behavior.
- Physical split WebRTC producers still force separate elements because they use independent PeerConnections; unified publisher remains toggleable.

3.7.52f44 - AV1 parser bypass restored
- Restores the Direct GST WebRTC AV1 av1parse bypass lost during branch merging.
- Uses minimal AV1 main-profile caps for Direct GST WebRTC and WHIP.
- Preserves f43 MSID and separate HTML media-element controls.


3.7.52f45 - Honest video sender queue
- Moves Encoded sender queue mode and Queue cap ms from Transport to the Video tab.
- Removes hidden 40 ms and 80 ms fallbacks from Small cushion and Non-leaky modes.
- Queue cap 0 now always emits max-size-time=0; presets must set any desired nonzero cap visibly.
- Queue mode still controls buffer count and leak behavior only.
