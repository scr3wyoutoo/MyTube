package com.dev.mytube

import android.content.Context
import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.view.TextureView
import android.view.View
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

@UnstableApi
class AndroidMedia3VideoPlayer(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, Player.Listener {
    companion object {
        const val CHANNEL = "flutter_browser_app/android_media3_video_player"
        const val VIEW_TYPE = "flutter_browser_app/android_media3_video_view"
    }

    private val applicationContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())
    private var player: ExoPlayer? = null
    private var attachedTextureView: TextureView? = null
    private var loadId = 0
    private var expectedDurationMs = 0L
    private var completedForLoad = false
    private var released = false
    private var tickerRunning = false

    private val positionTicker = object : Runnable {
        override fun run() {
            tickerRunning = false
            val current = player ?: return
            if (released) return
            sendState()
            if (current.isPlaying || current.playbackState == Player.STATE_BUFFERING) {
                scheduleTicker()
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    fun createViewFactory(): PlatformViewFactory =
        object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
            override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                return Media3TexturePlatformView(context, this@AndroidMedia3VideoPlayer)
            }
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "load" -> {
                    load(call)
                    result.success(null)
                }
                "play" -> {
                    requirePlayer().play()
                    result.success(null)
                }
                "pause" -> {
                    requirePlayer().pause()
                    result.success(null)
                }
                "seek" -> {
                    val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                    val current = requirePlayer()
                    val target = positionMs.coerceAtLeast(0L)
                    current.seekTo(target)
                    if (current.duration <= 0 || target < current.duration) {
                        completedForLoad = false
                    }
                    result.success(null)
                }
                "setVolume" -> {
                    val volume = call.argument<Number>("volume")?.toFloat() ?: 1f
                    requirePlayer().volume = volume.coerceIn(0f, 1f)
                    result.success(null)
                }
                "stop" -> {
                    stop(clearMedia = true)
                    result.success(null)
                }
                "dispose" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error(
                "android_media3_${call.method}_failed",
                error.message ?: error.javaClass.simpleName,
                error.stackTraceToString(),
            )
        }
    }

    private fun load(call: MethodCall) {
        val requestedLoadId = call.argument<Number>("loadId")?.toInt()
            ?: throw IllegalArgumentException("loadId fehlt")
        val videoUrl = call.argument<String>("videoUrl")
            ?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("videoUrl fehlt")
        val audioUrl = call.argument<String>("audioUrl")?.takeIf { it.isNotBlank() }
        val isHls = call.argument<Boolean>("isHls") == true
        val positionMs = call.argument<Number>("positionMs")?.toLong()
        val play = call.argument<Boolean>("play") == true
        val volume = call.argument<Number>("volume")?.toFloat() ?: 1f
        val headers = stringMap(call.argument<Map<*, *>>("headers"))

        loadId = requestedLoadId
        expectedDurationMs = call.argument<Number>("expectedDurationMs")?.toLong() ?: 0L
        completedForLoad = false
        val current = requirePlayer()
        current.stop()
        current.clearMediaItems()
        current.volume = volume.coerceIn(0f, 1f)
        current.playWhenReady = play
        val mediaSource = buildMediaSource(
            videoUrl = videoUrl,
            audioUrl = audioUrl,
            isHls = isHls,
            headers = headers,
        )
        if (positionMs == null) {
            current.setMediaSource(mediaSource)
        } else {
            current.setMediaSource(mediaSource, positionMs.coerceAtLeast(0L))
        }
        current.prepare()
        sendState()
        scheduleTicker()
    }

    private fun buildMediaSource(
        videoUrl: String,
        audioUrl: String?,
        isHls: Boolean,
        headers: Map<String, String>,
    ): MediaSource {
        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(headers)
        val videoItemBuilder = MediaItem.Builder().setUri(videoUrl)
        if (isHls) {
            videoItemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
        }
        val videoItem = videoItemBuilder.build()
        val videoSource = if (isHls) {
            HlsMediaSource.Factory(dataSourceFactory).createMediaSource(videoItem)
        } else {
            ProgressiveMediaSource.Factory(dataSourceFactory).createMediaSource(videoItem)
        }
        if (audioUrl == null) return videoSource

        val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory).createMediaSource(
            MediaItem.Builder().setUri(audioUrl).build(),
        )
        return MergingMediaSource(
            true,
            true,
            videoSource,
            audioSource,
        )
    }

    private fun requirePlayer(): ExoPlayer {
        check(!released) { "Media3-Player wurde bereits freigegeben" }
        return player ?: ExoPlayer.Builder(applicationContext).build().also { created ->
            created.addListener(this)
            created.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                true,
            )
            created.setHandleAudioBecomingNoisy(true)
            attachedTextureView?.let(created::setVideoTextureView)
            player = created
            updateKeepScreenOn(created)
        }
    }

    fun attachTextureView(view: TextureView) {
        if (attachedTextureView === view) return
        attachedTextureView?.let { old ->
            old.keepScreenOn = false
            player?.clearVideoTextureView(old)
        }
        attachedTextureView = view
        player?.setVideoTextureView(view)
        updateKeepScreenOn()
    }

    fun detachTextureView(view: TextureView) {
        if (attachedTextureView !== view) return
        view.keepScreenOn = false
        player?.clearVideoTextureView(view)
        attachedTextureView = null
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        sendState()
        if (playbackState == Player.STATE_READY) {
            channel.invokeMethod("ready", mapOf("loadId" to loadId))
        } else if (playbackState == Player.STATE_ENDED && !completedForLoad) {
            completedForLoad = true
            channel.invokeMethod("completed", mapOf("loadId" to loadId))
        }
        scheduleTicker()
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        sendState()
        scheduleTicker()
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        sendState()
        scheduleTicker()
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        sendState()
    }

    override fun onPlayerError(error: PlaybackException) {
        channel.invokeMethod(
            "error",
            mapOf(
                "loadId" to loadId,
                "message" to (error.message ?: error.errorCodeName),
                "errorCode" to error.errorCode,
                "errorCodeName" to error.errorCodeName,
                "cause" to (error.cause?.stackTraceToString() ?: ""),
            ),
        )
        sendState()
    }

    private fun sendState() {
        val current = player ?: return
        updateKeepScreenOn(current)
        val nativeDuration = current.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: 0L
        val duration = if (expectedDurationMs > 0) expectedDurationMs else nativeDuration
        val playbackRequested =
            current.playWhenReady &&
                current.playbackState != Player.STATE_ENDED &&
                current.mediaItemCount > 0
        channel.invokeMethod(
            "state",
            mapOf(
                "loadId" to loadId,
                "positionMs" to current.currentPosition.coerceAtLeast(0L),
                "durationMs" to duration,
                "playing" to current.isPlaying,
                "playbackRequested" to playbackRequested,
                "buffering" to (current.playbackState == Player.STATE_BUFFERING),
                "width" to current.videoSize.width,
                "height" to current.videoSize.height,
                "playbackState" to current.playbackState,
            ),
        )
    }

    private fun updateKeepScreenOn(current: Player? = player) {
        attachedTextureView?.keepScreenOn =
            current != null &&
                current.playWhenReady &&
                current.playbackState != Player.STATE_ENDED &&
                current.mediaItemCount > 0 &&
                current.playerError == null
    }

    private fun scheduleTicker() {
        if (tickerRunning || released) return
        tickerRunning = true
        handler.postDelayed(positionTicker, 250L)
    }

    private fun stop(clearMedia: Boolean) {
        val current = player ?: return
        current.stop()
        if (clearMedia) current.clearMediaItems()
        completedForLoad = false
        sendState()
    }

    fun release() {
        if (released) return
        released = true
        handler.removeCallbacks(positionTicker)
        tickerRunning = false
        attachedTextureView?.let { view ->
            view.keepScreenOn = false
            player?.clearVideoTextureView(view)
        }
        attachedTextureView = null
        player?.removeListener(this)
        player?.release()
        player = null
        channel.setMethodCallHandler(null)
    }

    private fun stringMap(raw: Map<*, *>?): Map<String, String> {
        if (raw == null) return emptyMap()
        return raw.entries.associate { (key, value) -> key.toString() to value.toString() }
    }
}

private class Media3TexturePlatformView(
    context: Context,
    private val controller: AndroidMedia3VideoPlayer,
) : PlatformView, TextureView.SurfaceTextureListener {
    private val textureView = TextureView(context)

    init {
        textureView.isOpaque = true
        textureView.surfaceTextureListener = this
        controller.attachTextureView(textureView)
    }

    override fun getView(): View = textureView

    override fun dispose() {
        controller.detachTextureView(textureView)
        textureView.surfaceTextureListener = null
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        controller.attachTextureView(textureView)
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        controller.detachTextureView(textureView)
        return true
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
}
