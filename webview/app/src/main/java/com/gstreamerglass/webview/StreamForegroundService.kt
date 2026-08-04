package com.gstreamerglass.webview

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import java.net.URL

private const val TAG = "GlassViewerSvc"
private const val CHANNEL_ID = "stream_playback"
private const val NOTIFICATION_ID = 1
private const val ACTION_TOGGLE_PLAYBACK = "com.gstreamerglass.webview.action.TOGGLE_PLAYBACK"

// Keeps the process alive (exempt from Doze/background restrictions) so the WebView's
// stream keeps playing when the app is fully backgrounded, and surfaces play/pause
// controls in the status bar via a MediaSession-backed notification.
class StreamForegroundService : Service() {

    inner class LocalBinder : Binder() {
        val service: StreamForegroundService get() = this@StreamForegroundService
    }

    private val binder = LocalBinder()
    private var wakeLock: PowerManager.WakeLock? = null
    private lateinit var mediaSession: MediaSession
    private var isPlaying = false
    private var title = "Glass2Glass"
    private var artist = ""
    private var artworkUrl: String? = null
    private var artworkBitmap: Bitmap? = null

    // Set by MainActivity so the notification's play/pause button can drive the page's <video>.
    var onPlayPauseAction: ((Boolean) -> Unit)? = null

    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "onBind")
        return binder
    }

    override fun onCreate() {
        super.onCreate()
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GlassViewer:stream")
            .apply {
                setReferenceCounted(false)
                acquire()
            }
        mediaSession = MediaSession(this, "GlassViewer").apply {
            setPlaybackState(playbackState())
            isActive = true
            // Without this, system-driven controls (PiP overlay, Bluetooth AVRCP, Assistant)
            // that dispatch through the session rather than our notification's PendingIntent
            // are silent no-ops - they only show up, they don't do anything.
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() {
                    Log.d(TAG, "MediaSession.Callback.onPlay")
                    invokePlayPause(true)
                }

                override fun onPause() {
                    Log.d(TAG, "MediaSession.Callback.onPause")
                    invokePlayPause(false)
                }
            })
        }
    }

    private fun invokePlayPause(play: Boolean) {
        onPlayPauseAction?.invoke(play)
            ?: Log.w(TAG, "onPlayPauseAction is null - MainActivity never bound, control is a no-op")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action} onPlayPauseAction=${onPlayPauseAction != null}")
        if (intent?.action == ACTION_TOGGLE_PLAYBACK) {
            val target = !isPlaying
            Log.d(TAG, "toggle requested, isPlaying=$isPlaying -> invoking target=$target")
            invokePlayPause(target)
        }
        postNotification()
        return START_STICKY
    }

    fun updatePlaybackState(playing: Boolean) {
        Log.d(TAG, "updatePlaybackState playing=$playing")
        isPlaying = playing
        mediaSession.setPlaybackState(playbackState())
        postNotification()
    }

    // Mirrors the page's own navigator.mediaSession.metadata (title/artist/artwork) into the
    // native notification instead of hardcoding an image, so it matches what the PWA shows.
    fun updateMetadata(newTitle: String, newArtist: String, newArtworkUrl: String?) {
        Log.d(TAG, "updateMetadata title=$newTitle artist=$newArtist artworkUrl=$newArtworkUrl")
        title = newTitle.ifBlank { "Glass2Glass" }
        artist = newArtist
        if (newArtworkUrl == artworkUrl) {
            applyMetadata()
            return
        }
        artworkUrl = newArtworkUrl
        if (newArtworkUrl == null) {
            artworkBitmap = null
            applyMetadata()
            return
        }
        Thread {
            val bitmap = try {
                URL(newArtworkUrl).openStream().use { BitmapFactory.decodeStream(it) }
            } catch (e: Exception) {
                Log.w(TAG, "artwork fetch failed for $newArtworkUrl", e)
                null
            }
            Handler(Looper.getMainLooper()).post {
                if (newArtworkUrl == artworkUrl) {
                    artworkBitmap = bitmap
                    applyMetadata()
                }
            }
        }.start()
    }

    private fun applyMetadata() {
        mediaSession.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .apply { artworkBitmap?.let { putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, it) } }
                .build()
        )
        postNotification()
    }

    private fun playbackState() = PlaybackState.Builder()
        .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE)
        .setState(
            if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
            PlaybackState.PLAYBACK_POSITION_UNKNOWN,
            1f
        )
        .build()

    override fun onDestroy() {
        mediaSession.isActive = false
        mediaSession.release()
        wakeLock?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }

    private fun postNotification() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val toggleIntent = Intent(this, StreamForegroundService::class.java).setAction(ACTION_TOGGLE_PLAYBACK)
        val togglePendingIntent = PendingIntent.getService(
            this, 0, toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val playPauseAction = Notification.Action.Builder(
            if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
            if (isPlaying) "Pause" else "Play",
            togglePendingIntent
        ).build()

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Stream playback", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(title)
            .setContentText(artist.ifBlank { if (isPlaying) "Playing" else "Paused" })
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(artworkBitmap)
            .setContentIntent(openApp)
            .setOngoing(true)
            .addAction(playPauseAction)
            .setStyle(Notification.MediaStyle().setMediaSession(mediaSession.sessionToken).setShowActionsInCompactView(0))
            .build()
    }
}
