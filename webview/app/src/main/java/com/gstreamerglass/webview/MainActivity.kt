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
import android.net.http.SslError
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageView
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

private const val TAG = "GlassViewerJS"
private const val PREFS_NAME = "glass2glass"
private const val KEY_SERVER_URL = "server_url"
private const val KEY_SERVER_INSECURE = "server_insecure"
private const val OFFLINE_URL = "file:///android_asset/offline.html"
private const val RETRY_DELAY_MS = 10000L

// Only used when the user has explicitly opted into "self-signed certificate" for a specific
// saved server (local installs without a real CA-signed cert). Scoped to individual connections
// below, never installed as the process-wide default SSL context.
private fun trustAllSslContext(): SSLContext {
    val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
        override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
    })
    return SSLContext.getInstance("TLS").apply { init(null, trustAll, SecureRandom()) }
}

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
    private var connected = false
    private var insecureMode = false
    private var serverUrl: String? = null
    private var pendingLoadFailed = false
    private val retryHandler = Handler(Looper.getMainLooper())
    private val retryRunnable = Runnable { serverUrl?.let { webView.loadUrl(it) } }

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
        fun setAutoPipEnabled(enabled: Boolean) {
            runOnUiThread { setAutoEnterPip(enabled) }
        }

        @JavascriptInterface
        fun onMediaMetadata(title: String, artist: String, artworkUrl: String) {
            runOnUiThread { streamService?.updateMetadata(title, artist, artworkUrl.ifBlank { null }) }
        }

        @JavascriptInterface
        fun onServerUrlSubmitted(url: String, insecure: Boolean) {
            runOnUiThread { verifyAndConnect(url, insecure) }
        }
    }

    // Fetched natively rather than via JS fetch() from the setup page: that's a file:// origin
    // hitting an arbitrary cross-origin host, which CORS would likely block even against a
    // real Glass server, since a self-hosted instance has no reason to send permissive CORS
    // headers on its HTML. Both the player page and its login page (if auth is required)
    // contain "GStreamer Glass" regardless of auth state, so this works either way.
    private fun verifyAndConnect(url: String, insecure: Boolean) {
        Thread {
            val verified = try {
                (URL(url).openConnection() as HttpURLConnection).run {
                    if (insecure && this is HttpsURLConnection) {
                        sslSocketFactory = trustAllSslContext().socketFactory
                        hostnameVerifier = HostnameVerifier { _, _ -> true }
                    }
                    connectTimeout = 8000
                    readTimeout = 8000
                    instanceFollowRedirects = true
                    inputStream.bufferedReader().use { reader ->
                        val buffer = CharArray(8192)
                        val text = StringBuilder()
                        while (text.length < 65536 && !text.contains("GStreamer Glass", ignoreCase = true)) {
                            val read = reader.read(buffer)
                            if (read == -1) break
                            text.append(buffer, 0, read)
                        }
                        text.contains("GStreamer Glass", ignoreCase = true)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "server verification failed for $url", e)
                false
            }
            runOnUiThread {
                if (verified) {
                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                        .putString(KEY_SERVER_URL, url)
                        .putBoolean(KEY_SERVER_INSECURE, insecure)
                        .apply()
                    connectToServer(url, insecure)
                } else {
                    webView.evaluateJavascript(
                        "window.__glassViewerSetupError && window.__glassViewerSetupError('Could not find a GStreamer Glass server at that address.');",
                        null
                    )
                }
            }
        }.start()
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
        showSquareSplashOverlay()

        // Chrome/WebView caps content to the display's default refresh rate unless a View
        // explicitly asks for more (Android 15+ adaptive refresh rate API).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            webView.requestedFrameRate = 120f
        }

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        // Default is true, which blocks any script/autoplay-attribute-triggered playback
        // until a real touch gesture happens in the WebView - the live stream should start
        // the moment the app opens, not require a tap first.
        webView.settings.mediaPlaybackRequiresUserGesture = false
        webView.addJavascriptInterface(WebMediaBridge(), "GlassViewer")
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                // A 503/404 still returns a response body at serverUrl, so onPageFinished
                // below can't tell "loaded" from "loaded but errored" by URL alone - reset this
                // at the start of every navigation and let onReceivedError/onReceivedHttpError
                // flip it if this particular attempt turns out to fail.
                pendingLoadFailed = false
                view?.evaluateJavascript(MEDIA_BRIDGE_JS, null)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                // A real page load succeeded - drop any retry left over from a prior failure
                // instead of letting it fire a redundant reload later.
                if (url == serverUrl && !pendingLoadFailed) retryHandler.removeCallbacks(retryRunnable)
            }

            // Only bypasses cert validation when the user explicitly opted into "self-signed
            // certificate" for this saved server (local installs without a real CA-signed
            // cert) - default behavior (reject) is unchanged otherwise.
            override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler, error: SslError) {
                if (insecureMode) {
                    Log.w(TAG, "proceeding past SSL error (self-signed cert opt-in): $error")
                    handler.proceed()
                } else {
                    super.onReceivedSslError(view, handler, error)
                }
            }

            // The "can't reach the server at all" case - DNS/connect/timeout failures on the
            // main navigation. Not sub-resource errors (a missing favicon shouldn't show the
            // offline page), and not while still on the setup page (verifyAndConnect already
            // has its own error handling for that).
            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                super.onReceivedError(view, request, error)
                if (isMainFrameFailure(request)) {
                    Log.w(TAG, "main frame load failed: $error")
                    pendingLoadFailed = true
                    showOfflineAndRetry()
                }
            }

            // The other half: reached the server, but it answered with an error status - a
            // proxy returning 502/503 while the backend stream is down, a 404 from a stale/wrong
            // path, etc. Same recovery either way from the user's perspective.
            override fun onReceivedHttpError(view: WebView?, request: WebResourceRequest?, errorResponse: WebResourceResponse?) {
                super.onReceivedHttpError(view, request, errorResponse)
                if (isMainFrameFailure(request)) {
                    Log.w(TAG, "main frame http error: ${errorResponse?.statusCode}")
                    pendingLoadFailed = true
                    showOfflineAndRetry()
                }
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
            }
        }
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val savedUrl = prefs.getString(KEY_SERVER_URL, null)
        if (savedUrl != null) {
            connectToServer(savedUrl, prefs.getBoolean(KEY_SERVER_INSECURE, false))
        } else {
            webView.loadUrl("file:///android_asset/setup.html")
        }
    }

    // Only reachable once a server URL is known (already saved, or just entered on the setup
    // page) - no point claiming "streaming in the background" in the notification before then.
    // Guarded against running twice: a double-tap on the setup page's Connect button before it
    // navigates away would otherwise bindService() a second time on the same connection.
    private fun connectToServer(url: String, insecure: Boolean) {
        if (connected) return
        connected = true
        insecureMode = insecure
        serverUrl = url
        webView.loadUrl(url)
        requestNotificationPermissionIfNeeded()
        requestPhoneStatePermissionIfNeeded()
        startStreamService()
        boundToService = bindService(Intent(this, StreamForegroundService::class.java), serviceConnection, Context.BIND_AUTO_CREATE)
        setAutoEnterPip(true)
    }

    private fun isMainFrameFailure(request: WebResourceRequest?): Boolean =
        connected && request?.isForMainFrame == true && request.url.toString() != OFFLINE_URL

    private fun showOfflineAndRetry() {
        webView.loadUrl(OFFLINE_URL)
        retryHandler.removeCallbacks(retryRunnable)
        retryHandler.postDelayed(retryRunnable, RETRY_DELAY_MS)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    override fun onDestroy() {
        retryHandler.removeCallbacks(retryRunnable)
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

    // onUserLeaveHint()/enterPip() below only fires while the activity is still resumed (Home
    // button, switching apps) - by the time the user opens Recents and swipes the task away,
    // the activity is already backgrounded, so that manual call never gets a chance to run for
    // that specific gesture. Auto-enter (Android 12+) is the system doing the transition itself
    // rather than us reacting to a callback, which is what actually covers swipe-away - the
    // same mechanism a PWA's Chrome-hosted video relies on for the same smooth transition.
    // Defaults on in connectToServer(); the web app's own "Enable auto PiP" viewer setting
    // (player.js, defaults true too) confirms/overrides it once the page loads, via
    // WebMediaBridge.setAutoPipEnabled - android.webkit.WebView has no way to expose this
    // Activity-level API to the page on its own.
    private fun setAutoEnterPip(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setPictureInPictureParams(PictureInPictureParams.Builder().setAutoEnterEnabled(enabled).build())
        }
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            enterPictureInPictureMode(PictureInPictureParams.Builder().build())
        }
    }

    // Our own square, uncropped splash - the system's own splash icon slot (API 31+) always
    // draws a hardcoded circular backdrop no theme attribute can reshape (values-v31/themes.xml
    // deliberately doesn't set windowSplashScreenAnimatedIcon at all). drawable-nodpi/splash_icon
    // is a dedicated 512px asset so this is never upscaled/blurred the way the OS's own splash
    // icon sizing was.
    private fun showSquareSplashOverlay() {
        val sizePx = (220 * resources.displayMetrics.density).toInt()
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(getColor(R.color.ic_launcher_background))
            addView(
                ImageView(this@MainActivity).apply {
                    setImageResource(R.drawable.splash_icon)
                    scaleType = ImageView.ScaleType.CENTER_INSIDE
                },
                FrameLayout.LayoutParams(sizePx, sizePx, Gravity.CENTER)
            )
        }
        addContentView(overlay, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        overlay.postDelayed({ (overlay.parent as? ViewGroup)?.removeView(overlay) }, 1500)
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

    private fun requestPhoneStatePermissionIfNeeded() {
        if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.READ_PHONE_STATE), 2)
        }
    }

    // requestPhoneStatePermissionIfNeeded() fires before the user has answered the dialog, so
    // the service's own attempt to start listening (in its onCreate, which runs around the same
    // time) can miss a permission that gets granted moments later - retry once it lands.
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 2 && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            streamService?.startListeningForCalls()
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Without this the system draws its own translucent gray protection scrim behind
            // the status/nav bars whenever they're transiently revealed (swipe-to-peek) or
            // shown, to guarantee icon contrast regardless of app content - setStatusBarColor/
            // setNavigationBarColor are full no-ops on Android 15+ (targetSdk 35, confirmed by
            // testing) so they can't fix this, but these contrast-enforcement toggles are a
            // separate mechanism that still works for the persistently-shown state (the
            // transient swipe-peek scrim's color is system-controlled with no app-level API to
            // override it - a platform limitation, not something left unfixed here).
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
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

    private fun showSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(true)
            window.insetsController?.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }
    }
}
