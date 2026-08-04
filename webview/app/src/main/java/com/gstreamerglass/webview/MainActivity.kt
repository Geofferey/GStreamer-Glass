package com.gstreamerglass.webview

import android.Manifest
import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient

private const val TAG = "GlassViewerJS"
private const val PREFS_NAME = "glass2glass"
private const val KEY_SERVER_URL = "server_url"

// Bridges the page's PiP button and play/pause state into native Android APIs, since
// android.webkit.WebView doesn't implement the Web PiP or Media Session APIs itself (that
// glue only exists in the Chrome app, not the WebView engine).
//
// The page's own on-screen controls (both the custom Glass overlay and native <video controls>)
// can reliably play/pause the MediaStream-backed <video>, so we drive playback through
// window.GstGlassPlayer.play()/.pause() - its real controller - rather than poking the raw
// element directly, and log each step so failures show up in logcat instead of just "nothing
// happened".
private const val MEDIA_BRIDGE_JS = """
(function() {
  if (window.__glassViewerBridgeInstalled) return;
  window.__glassViewerBridgeInstalled = true;
  console.log('[glassviewer] bridge installing');

  try {
    Object.defineProperty(document, 'pictureInPictureEnabled', {
      get: function() { return true; },
      configurable: true
    });
  } catch (e) {}

  try {
    if (window.HTMLVideoElement) {
      HTMLVideoElement.prototype.requestPictureInPicture = function() {
        if (window.GlassViewer) window.GlassViewer.requestPip();
        return Promise.resolve();
      };
    }
  } catch (e) {}

  var activeMedia = null;
  function report(el) {
    if (!el || (el.tagName !== 'VIDEO' && el.tagName !== 'AUDIO')) return;
    activeMedia = el;
    console.log('[glassviewer] playback state changed, paused=' + el.paused);
    if (window.GlassViewer) window.GlassViewer.onPlaybackState(!el.paused);
  }
  document.addEventListener('play', function(e) { report(e.target); }, true);
  document.addEventListener('pause', function(e) { report(e.target); }, true);

  window.__glassViewerPlay = function() {
    console.log('[glassviewer] play requested, GstGlassPlayer=' + !!window.GstGlassPlayer);
    if (window.GstGlassPlayer && typeof window.GstGlassPlayer.play === 'function') window.GstGlassPlayer.play();
    else if (activeMedia) activeMedia.play();
  };
  window.__glassViewerPause = function() {
    console.log('[glassviewer] pause requested, GstGlassPlayer=' + !!window.GstGlassPlayer);
    if (window.GstGlassPlayer && typeof window.GstGlassPlayer.pause === 'function') window.GstGlassPlayer.pause();
    else if (activeMedia) activeMedia.pause();
  };

  // window.GstGlassPlayer only exists once the page's own script has run (after our
  // onPageStarted injection), so poll briefly instead of assuming it's there yet.
  var readyAttempts = 0;
  var readyTimer = setInterval(function() {
    readyAttempts++;
    if (window.GstGlassPlayer && typeof window.GstGlassPlayer.notificationAnchor === 'function') {
      clearInterval(readyTimer);
      console.log('[glassviewer] GstGlassPlayer ready after ' + readyAttempts + ' attempts, enabling notification anchor');
      window.GstGlassPlayer.notificationAnchor(true);
    } else if (readyAttempts > 100) {
      clearInterval(readyTimer);
      console.log('[glassviewer] GstGlassPlayer never became ready');
    }
  }, 100);

  // Stops decoding/rendering the remote video track while backgrounded (and not in PiP,
  // where the video is still visible) to save CPU/battery, without touching audio - disabling
  // a MediaStreamTrack is the standard way to pause a WebRTC video feed without tearing down
  // the connection or affecting other tracks on the same stream.
  window.__glassViewerSetVideoRendering = function(enabled) {
    console.log('[glassviewer] setVideoRendering ' + enabled);
    document.querySelectorAll('video').forEach(function(v) {
      var stream = v.srcObject;
      if (stream && typeof stream.getVideoTracks === 'function') {
        stream.getVideoTracks().forEach(function(track) { track.enabled = enabled; });
      }
    });
  };

  // This WebView build doesn't implement navigator.mediaSession at all (not just the
  // constructor - the instance itself is undefined), so the page's own setupMediaSession()
  // silently bails out and there is nothing to intercept. Compute the same artwork URL it
  // would have used (./icons/gstreamer-glass-512.png relative to document.baseURI) directly
  // instead, once the page has actually set its title.
  window.addEventListener('load', function() {
    if (!window.GlassViewer) return;
    try {
      var art = new URL('./icons/gstreamer-glass-512.png', document.baseURI).href;
      var title = document.title || 'GStreamer Glass Live';
      var artist = location.host || location.hostname || 'Local viewer';
      console.log('[glassviewer] metadata computed title=' + title + ' art=' + art);
      window.GlassViewer.onMediaMetadata(title, artist, art);
    } catch (e) {
      console.log('[glassviewer] metadata computation failed: ' + e);
    }
  });
})();
"""

class MainActivity : Activity() {

    private lateinit var webView: WebView
    private var streamService: StreamForegroundService? = null
    private var fullscreenView: View? = null
    private var boundToService = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            Log.d(TAG, "service connected")
            val service = (binder as StreamForegroundService.LocalBinder).service
            streamService = service
            service.onPlayPauseAction = { play ->
                Log.d(TAG, "onPlayPauseAction invoked, play=$play")
                webView.post {
                    webView.evaluateJavascript(
                        if (play) "window.__glassViewerPlay && window.__glassViewerPlay();"
                        else "window.__glassViewerPause && window.__glassViewerPause();"
                    ) { result -> Log.d(TAG, "evaluateJavascript result=$result") }
                }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "service disconnected")
            streamService = null
        }
    }

    private inner class WebMediaBridge {
        @JavascriptInterface
        fun onPlaybackState(playing: Boolean) {
            runOnUiThread { streamService?.updatePlaybackState(playing) }
        }

        @JavascriptInterface
        fun requestPip() {
            runOnUiThread { enterPip() }
        }

        @JavascriptInterface
        fun onMediaMetadata(title: String, artist: String, artworkUrl: String) {
            runOnUiThread { streamService?.updateMetadata(title, artist, artworkUrl.ifBlank { null }) }
        }

        @JavascriptInterface
        fun onServerUrlSubmitted(url: String) {
            runOnUiThread {
                getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putString(KEY_SERVER_URL, url).apply()
                connectToServer(url)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Pre-Android 15 fallback: older hint APIs, superseded by requestedFrameRate below
        // but still honored, so this covers 120Hz panels on API 23-34 too. preferredDisplayModeId
        // (exact mode match) wins over preferredRefreshRate when both are set and a mode is found;
        // preferredRefreshRate stays as the fallback if no matching mode is found.
        window.attributes = window.attributes.apply {
            preferredRefreshRate = 120f
            preferredHighRefreshRateMode()?.let { preferredDisplayModeId = it }
        }

        webView = WebView(this)
        setContentView(webView)
        hideSystemBars()

        // Chrome/WebView caps content to the display's default refresh rate unless a View
        // explicitly asks for more (Android 15+ adaptive refresh rate API).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            webView.requestedFrameRate = 120f
        }

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.addJavascriptInterface(WebMediaBridge(), "GlassViewer")
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                view?.evaluateJavascript(MEDIA_BRIDGE_JS, null)
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            // Without this, WebView briefly shows its own stock gray-play-button placeholder
            // for any <video> lacking a poster attribute, before the first frame is ready.
            override fun getDefaultVideoPoster(): Bitmap =
                Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)

            // Surfaces the injected script's console.log calls in logcat under our tag,
            // instead of the default chromium tag, so bridge failures are easy to find.
            override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                Log.d(TAG, "${message.message()} [${message.sourceId()}:${message.lineNumber()}]")
                return true
            }

            // WebView only honors the page's Fullscreen API (any element, not just <video>)
            // if the host app implements this pair to host the view Chromium hands over.
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                if (fullscreenView != null) {
                    callback.onCustomViewHidden()
                    return
                }
                fullscreenView = view
                addContentView(
                    view,
                    ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                )
                hideSystemBars()
            }

            override fun onHideCustomView() {
                (fullscreenView?.parent as? ViewGroup)?.removeView(fullscreenView)
                fullscreenView = null
                hideSystemBars()
            }
        }
        val savedUrl = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(KEY_SERVER_URL, null)
        if (savedUrl != null) {
            connectToServer(savedUrl)
        } else {
            webView.loadUrl("file:///android_asset/setup.html")
        }
    }

    // Only reachable once a server URL is known (already saved, or just entered on the setup
    // page) - no point claiming "streaming in the background" in the notification before then.
    private fun connectToServer(url: String) {
        webView.loadUrl(url)
        requestNotificationPermissionIfNeeded()
        startStreamService()
        boundToService = bindService(Intent(this, StreamForegroundService::class.java), serviceConnection, Context.BIND_AUTO_CREATE)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    override fun onDestroy() {
        if (boundToService) unbindService(serviceConnection)
        stopService(Intent(this, StreamForegroundService::class.java))
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        enterPip()
    }

    // onStop only fires when nothing of the activity is visible - entering PiP keeps it
    // STARTED (the small window is still on screen), so this only catches "fully backgrounded,
    // not in PiP" (PiP dismissed, PiP unsupported on this device, etc.) without needing to
    // separately track PiP state.
    override fun onStop() {
        super.onStop()
        setVideoRendering(false)
    }

    override fun onStart() {
        super.onStart()
        setVideoRendering(true)
    }

    private fun setVideoRendering(enabled: Boolean) {
        webView.evaluateJavascript("window.__glassViewerSetVideoRendering && window.__glassViewerSetVideoRendering($enabled);", null)
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            enterPictureInPictureMode(PictureInPictureParams.Builder().build())
        }
    }

    // Picks the highest-refresh-rate mode at the display's current resolution, so we don't
    // accidentally request a mode that also changes resolution.
    private fun preferredHighRefreshRateMode(): Int? {
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
        else @Suppress("DEPRECATION") windowManager.defaultDisplay
        val currentMode = display?.mode ?: return null
        return display.supportedModes
            .filter { it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight }
            .maxByOrNull { it.refreshRate }
            ?.takeIf { it.refreshRate > currentMode.refreshRate }
            ?.modeId
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    private fun startStreamService() {
        val intent = Intent(this, StreamForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun hideSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                )
        }
    }
}
