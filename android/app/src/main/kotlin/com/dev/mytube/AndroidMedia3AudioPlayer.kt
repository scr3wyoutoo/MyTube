package com.dev.mytube

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max

@UnstableApi
class AndroidMedia3AudioPlayer(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "flutter_browser_app/android_media3_audio_playback"
        private const val STATE_INTERVAL_MS = 100L
        private const val STATE_PUBLISH_INTERVAL_MS = 250L
    }

    private inner class Slot(val name: String) : Player.Listener {
        val player: ExoPlayer = ExoPlayer.Builder(applicationContext).build().also { created ->
            created.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                false,
            )
            // Audio focus, interruptions and becoming-noisy are coordinated by
            // the existing app-wide AudioSession/MediaSession bridge.
            created.setHandleAudioBecomingNoisy(false)
            created.setWakeMode(C.WAKE_MODE_NETWORK)
            created.addListener(this)
        }
        var expectedDurationMs = 0L

        override fun onPlaybackStateChanged(playbackState: Int) {
            when {
                this === activeSlot && playbackState == Player.STATE_READY -> finishOpen(true)
                this === standbySlot && playbackState == Player.STATE_READY -> {
                    nextPrepared = true
                    finishPrepareNext(true)
                }
            }
            if (this === activeSlot && playbackState == Player.STATE_ENDED) {
                finishActiveTimeline()
            }
            publishState(force = true)
            scheduleTicker()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            publishState(force = true)
            scheduleTicker()
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            publishState(force = true)
            scheduleTicker()
        }

        override fun onPlayerError(error: PlaybackException) {
            val details = buildString {
                append(error.errorCodeName)
                append(": ")
                append(error.message ?: "Unbekannter Media3-Fehler")
                error.cause?.message?.let { cause ->
                    append("\n")
                    append(cause)
                }
            }
            if (this === standbySlot) {
                nextPrepared = false
                finishPrepareNextError(details)
            } else {
                finishOpenError(details)
                channel.invokeMethod("failed", details)
            }
            publishState(force = true)
        }
    }

    private val applicationContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())
    private val slotA = Slot("A")
    private val slotB = Slot("B")
    private var activeSlot = slotA
    private var standbySlot = slotB
    private var pendingOpenResult: MethodChannel.Result? = null
    private var pendingPrepareResult: MethodChannel.Result? = null
    private var nextPrepared = false
    private var crossfadeStarted = false
    private var crossfadeDurationMs = 6_000L
    private var masterVolume = 1f
    private var completedPublished = false
    private var released = false
    private var tickerScheduled = false
    private var lastStatePublishMs = 0L

    private val ticker = object : Runnable {
        override fun run() {
            tickerScheduled = false
            if (released) return
            updateCrossfade()
            publishState()
            scheduleTicker()
        }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (released) {
            result.error("android_media3_audio_released", "Media3-Audioplayer wurde freigegeben", null)
            return
        }
        try {
            when (call.method) {
                "open" -> open(call, result)
                "prepareNext" -> prepareNext(call, result)
                "play" -> {
                    activeSlot.player.play()
                    if (crossfadeStarted) standbySlot.player.play()
                    publishState(force = true)
                    scheduleTicker()
                    result.success(null)
                }
                "pause" -> {
                    activeSlot.player.pause()
                    standbySlot.player.pause()
                    publishState(force = true)
                    result.success(null)
                }
                "seek" -> {
                    cancelCrossfade(rewindNext = true)
                    val targetMs = call.argument<Number>("positionMilliseconds")?.toLong() ?: 0L
                    activeSlot.player.seekTo(targetMs.coerceAtLeast(0L))
                    completedPublished = false
                    publishState(force = true)
                    result.success(null)
                }
                "setVolume" -> {
                    masterVolume = (call.argument<Number>("volume")?.toFloat() ?: 1f)
                        .coerceIn(0f, 1f)
                    applyCrossfadeVolumes()
                    result.success(null)
                }
                "clearNext" -> {
                    clearNext()
                    result.success(null)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error(
                "android_media3_audio_${call.method}_failed",
                error.message ?: error.javaClass.simpleName,
                error.stackTraceToString(),
            )
        }
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        finishOpen(false)
        finishPrepareNext(false)
        handler.removeCallbacks(ticker)
        tickerScheduled = false
        resetSlot(activeSlot)
        resetSlot(standbySlot)
        nextPrepared = false
        crossfadeStarted = false
        completedPublished = false
        masterVolume = (call.argument<Number>("volume")?.toFloat() ?: 1f).coerceIn(0f, 1f)
        crossfadeDurationMs = max(
            1L,
            call.argument<Number>("crossfadeMilliseconds")?.toLong() ?: 6_000L,
        )
        activeSlot.expectedDurationMs =
            call.argument<Number>("expectedDurationMilliseconds")?.toLong()?.coerceAtLeast(0L)
                ?: 0L
        activeSlot.player.volume = masterVolume
        activeSlot.player.playWhenReady = call.argument<Boolean>("playing") == true
        val source = buildMediaSource(call)
        val positionMs =
            call.argument<Number>("positionMilliseconds")?.toLong()?.coerceAtLeast(0L) ?: 0L
        activeSlot.player.setMediaSource(source, positionMs)
        pendingOpenResult = result
        activeSlot.player.prepare()
        publishState(force = true)
        scheduleTicker()
    }

    private fun prepareNext(call: MethodCall, result: MethodChannel.Result) {
        finishPrepareNext(false)
        cancelCrossfade(rewindNext = false)
        resetSlot(standbySlot)
        standbySlot.expectedDurationMs =
            call.argument<Number>("expectedDurationMilliseconds")?.toLong()?.coerceAtLeast(0L)
                ?: 0L
        standbySlot.player.volume = 0f
        standbySlot.player.playWhenReady = false
        standbySlot.player.setMediaSource(buildMediaSource(call))
        nextPrepared = false
        pendingPrepareResult = result
        standbySlot.player.prepare()
        scheduleTicker()
    }

    private fun buildMediaSource(call: MethodCall): MediaSource {
        val url = call.argument<String>("streamUrl")?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("streamUrl fehlt")
        val headers = stringMap(call.argument<Map<*, *>>("headers"))
        val isHls = call.argument<Boolean>("isHls") == true
        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(headers)
        val itemBuilder = MediaItem.Builder().setUri(url)
        if (isHls) itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
        val item = itemBuilder.build()
        return if (isHls) {
            HlsMediaSource.Factory(dataSourceFactory).createMediaSource(item)
        } else {
            ProgressiveMediaSource.Factory(dataSourceFactory).createMediaSource(item)
        }
    }

    private fun updateCrossfade() {
        val current = activeSlot.player
        val canonicalDuration = activeDurationMs()
        if (canonicalDuration <= 0L) return
        val position = current.currentPosition.coerceAtLeast(0L)
        val remaining = canonicalDuration - position

        if (nextPrepared && current.playWhenReady && remaining <= crossfadeDurationMs) {
            if (!crossfadeStarted) {
                val missedFadeMs = (crossfadeDurationMs - remaining).coerceIn(0L, crossfadeDurationMs)
                standbySlot.player.seekTo(missedFadeMs)
                standbySlot.player.playWhenReady = true
                standbySlot.player.play()
                crossfadeStarted = true
            }
            applyCrossfadeVolumes()
        }

        if (position >= canonicalDuration) {
            finishActiveTimeline()
        }
    }

    private fun applyCrossfadeVolumes() {
        if (!crossfadeStarted) {
            activeSlot.player.volume = masterVolume
            standbySlot.player.volume = 0f
            return
        }
        val duration = activeDurationMs()
        val remaining = (duration - activeSlot.player.currentPosition).coerceAtLeast(0L)
        val incomingFactor =
            (1.0 - remaining.toDouble() / crossfadeDurationMs.toDouble()).coerceIn(0.0, 1.0)
        activeSlot.player.volume = (masterVolume * (1.0 - incomingFactor)).toFloat()
        standbySlot.player.volume = (masterVolume * incomingFactor).toFloat()
    }

    private fun finishActiveTimeline() {
        if (nextPrepared) {
            promoteStandby()
            return
        }
        if (completedPublished) return
        completedPublished = true
        activeSlot.player.pause()
        channel.invokeMethod("completed", null)
        publishState(force = true)
    }

    private fun promoteStandby() {
        val outgoing = activeSlot
        val incoming = standbySlot
        val shouldContinuePlaying = outgoing.player.playWhenReady || incoming.player.playWhenReady
        outgoing.player.pause()
        outgoing.player.stop()
        outgoing.player.clearMediaItems()
        outgoing.expectedDurationMs = 0L
        outgoing.player.volume = 0f

        activeSlot = incoming
        standbySlot = outgoing
        activeSlot.player.volume = masterVolume
        activeSlot.player.playWhenReady = shouldContinuePlaying
        if (shouldContinuePlaying) activeSlot.player.play()
        nextPrepared = false
        crossfadeStarted = false
        completedPublished = false
        channel.invokeMethod("advanced", null)
        publishState(force = true)
        scheduleTicker()
    }

    private fun cancelCrossfade(rewindNext: Boolean) {
        if (crossfadeStarted) {
            standbySlot.player.pause()
            if (rewindNext) standbySlot.player.seekTo(0L)
        }
        crossfadeStarted = false
        activeSlot.player.volume = masterVolume
        standbySlot.player.volume = 0f
    }

    private fun clearNext() {
        finishPrepareNext(false)
        cancelCrossfade(rewindNext = false)
        resetSlot(standbySlot)
        nextPrepared = false
        publishState(force = true)
    }

    private fun stop() {
        finishOpen(false)
        finishPrepareNext(false)
        handler.removeCallbacks(ticker)
        tickerScheduled = false
        resetSlot(activeSlot)
        resetSlot(standbySlot)
        nextPrepared = false
        crossfadeStarted = false
        completedPublished = false
        publishState(force = true)
    }

    private fun resetSlot(slot: Slot) {
        slot.player.pause()
        slot.player.stop()
        slot.player.clearMediaItems()
        slot.player.volume = 0f
        slot.expectedDurationMs = 0L
    }

    private fun activeDurationMs(): Long {
        if (activeSlot.expectedDurationMs > 0L) return activeSlot.expectedDurationMs
        val nativeDuration = activeSlot.player.duration
        return if (nativeDuration == C.TIME_UNSET || nativeDuration < 0L) 0L else nativeDuration
    }

    private fun publishState(force: Boolean = false) {
        if (released) return
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastStatePublishMs < STATE_PUBLISH_INTERVAL_MS) return
        lastStatePublishMs = now
        val current = activeSlot.player
        val currentPlaybackRequested =
            current.playWhenReady && current.playbackState != Player.STATE_ENDED
        val incomingPlaybackRequested =
            crossfadeStarted &&
                standbySlot.player.playWhenReady &&
                standbySlot.player.playbackState != Player.STATE_ENDED
        val effectivePlaying = currentPlaybackRequested || incomingPlaybackRequested
        val buffering =
            current.playbackState == Player.STATE_BUFFERING ||
                (crossfadeStarted && standbySlot.player.playbackState == Player.STATE_BUFFERING)
        channel.invokeMethod(
            "stateChanged",
            mapOf(
                "positionMilliseconds" to current.currentPosition.coerceAtLeast(0L),
                "durationMilliseconds" to activeDurationMs(),
                "playing" to effectivePlaying,
                "buffering" to buffering,
            ),
        )
    }

    private fun scheduleTicker() {
        if (released || tickerScheduled) return
        val current = activeSlot.player
        val shouldTick =
            current.playWhenReady ||
                current.playbackState == Player.STATE_BUFFERING ||
                crossfadeStarted
        if (!shouldTick) return
        tickerScheduled = true
        handler.postDelayed(ticker, STATE_INTERVAL_MS)
    }

    private fun finishOpen(success: Boolean) {
        val result = pendingOpenResult ?: return
        pendingOpenResult = null
        result.success(success)
    }

    private fun finishOpenError(message: String) {
        val result = pendingOpenResult ?: return
        pendingOpenResult = null
        result.error("android_media3_audio_open_failed", message, null)
    }

    private fun finishPrepareNext(success: Boolean) {
        val result = pendingPrepareResult ?: return
        pendingPrepareResult = null
        result.success(success)
    }

    private fun finishPrepareNextError(message: String) {
        val result = pendingPrepareResult ?: return
        pendingPrepareResult = null
        result.error("android_media3_audio_prepare_next_failed", message, null)
    }

    fun release() {
        if (released) return
        stop()
        released = true
        handler.removeCallbacks(ticker)
        slotA.player.removeListener(slotA)
        slotB.player.removeListener(slotB)
        slotA.player.release()
        slotB.player.release()
        channel.setMethodCallHandler(null)
    }

    private fun stringMap(raw: Map<*, *>?): Map<String, String> {
        if (raw == null) return emptyMap()
        return raw.entries.associate { (key, value) -> key.toString() to value.toString() }
    }
}
