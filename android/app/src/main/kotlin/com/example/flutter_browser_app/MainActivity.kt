package com.example.flutter_browser_app

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import androidx.media3.common.util.UnstableApi

@UnstableApi
class MainActivity : AudioServiceActivity() {
    companion object {
        private const val CHANNEL = "flutter_browser_app/picture_in_picture"
        private const val ACTION_TOGGLE_PLAYBACK =
            "com.example.flutter_browser_app.action.TOGGLE_PLAYBACK"
        private const val PLAYBACK_ACTION_REQUEST_CODE = 4101
    }

    private lateinit var methodChannel: MethodChannel
    private var androidMedia3VideoPlayer: AndroidMedia3VideoPlayer? = null
    private var androidMedia3AudioPlayer: AndroidMedia3AudioPlayer? = null
    private var playerPageActive = false
    private var playbackPlaying = false
    private var autoEnterEnabled = false
    private var videoWidth = 16
    private var videoHeight = 9
    private var receiverRegistered = false
    private var pendingPictureInPictureExit = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pictureInPictureExitFallback = Runnable {
        if (pendingPictureInPictureExit) {
            resolvePictureInPictureExit(restoredToApp = hasWindowFocus())
        }
    }

    private val playbackActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_TOGGLE_PLAYBACK) {
                return
            }
            methodChannel.invokeMethod("togglePlayback", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerPlaybackActionReceiver()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        androidMedia3VideoPlayer = AndroidMedia3VideoPlayer(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { player ->
            flutterEngine.platformViewsController.registry.registerViewFactory(
                AndroidMedia3VideoPlayer.VIEW_TYPE,
                player.createViewFactory(),
            )
        }
        androidMedia3AudioPlayer = AndroidMedia3AudioPlayer(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    playerPageActive = call.argument<Boolean>("enabled") == true
                    playbackPlaying = call.argument<Boolean>("playing") == true
                    autoEnterEnabled =
                        call.argument<Boolean>("autoEnterEnabled") == true
                    videoWidth = call.argument<Int>("videoWidth") ?: 16
                    videoHeight = call.argument<Int>("videoHeight") ?: 9
                    updatePictureInPictureParams()
                    result.success(null)
                }
                "enter" -> {
                    if (
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        playerPageActive &&
                        supportsPictureInPicture()
                    ) {
                        result.success(
                            enterPictureInPictureMode(
                                createPictureInPictureParams(autoEnter = autoEnterEnabled),
                            ),
                        )
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (
            Build.VERSION.SDK_INT in Build.VERSION_CODES.O until Build.VERSION_CODES.S &&
            playerPageActive && autoEnterEnabled &&
            supportsPictureInPicture()
        ) {
            enterPictureInPictureMode(createPictureInPictureParams(autoEnter = false))
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            pendingPictureInPictureExit = false
            mainHandler.removeCallbacks(pictureInPictureExitFallback)
            dispatchPictureInPictureMode(
                active = true,
                restoredToApp = false,
            )
            return
        }

        // PiP=false precedes the definitive Activity lifecycle callback. Wait
        // for onPostResume (expanded back into the app) or onStop (PiP was
        // closed in the background) instead of guessing from a Dart timer.
        pendingPictureInPictureExit = true
        mainHandler.removeCallbacks(pictureInPictureExitFallback)
        mainHandler.postDelayed(pictureInPictureExitFallback, 1500)
    }

    override fun onPostResume() {
        super.onPostResume()
        resolvePictureInPictureExit(restoredToApp = true)
        // A manual PiP entry supplies its own parameter set. Re-apply the
        // current configuration after expanding the Activity so the next
        // Home gesture still sees the intended auto-enter state.
        updatePictureInPictureParams()
    }

    override fun onStop() {
        resolvePictureInPictureExit(restoredToApp = false)
        super.onStop()
    }

    override fun onDestroy() {
        resolvePictureInPictureExit(restoredToApp = false)
        mainHandler.removeCallbacks(pictureInPictureExitFallback)
        if (receiverRegistered) {
            unregisterReceiver(playbackActionReceiver)
            receiverRegistered = false
        }
        androidMedia3VideoPlayer?.release()
        androidMedia3VideoPlayer = null
        androidMedia3AudioPlayer?.release()
        androidMedia3AudioPlayer = null
        super.onDestroy()
    }

    private fun resolvePictureInPictureExit(restoredToApp: Boolean) {
        if (!pendingPictureInPictureExit) {
            return
        }
        pendingPictureInPictureExit = false
        mainHandler.removeCallbacks(pictureInPictureExitFallback)
        dispatchPictureInPictureMode(
            active = false,
            restoredToApp = restoredToApp,
        )
    }

    private fun dispatchPictureInPictureMode(
        active: Boolean,
        restoredToApp: Boolean,
    ) {
        if (!::methodChannel.isInitialized) {
            return
        }
        methodChannel.invokeMethod(
            "pictureInPictureModeChanged",
            mapOf(
                "active" to active,
                "restoredToApp" to restoredToApp,
            ),
        )
    }

    private fun updatePictureInPictureParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !supportsPictureInPicture()) {
            return
        }
        try {
            setPictureInPictureParams(createPictureInPictureParams(autoEnter = autoEnterEnabled))
        } catch (_: IllegalArgumentException) {
            // Some manufacturers enforce narrower aspect-ratio limits. In that
            // case Android chooses a valid default ratio itself.
            val builder = PictureInPictureParams.Builder()
                .setActions(listOf(createPlaybackRemoteAction()))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(autoEnterEnabled)
                builder.setSeamlessResizeEnabled(true)
            }
            setPictureInPictureParams(builder.build())
        }
    }

    private fun createPictureInPictureParams(autoEnter: Boolean): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setActions(listOf(createPlaybackRemoteAction()))
        sanitizedAspectRatio()?.let(builder::setAspectRatio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun sanitizedAspectRatio(): Rational? {
        if (videoWidth <= 0 || videoHeight <= 0) {
            return Rational(16, 9)
        }
        val ratio = videoWidth.toDouble() / videoHeight.toDouble()
        if (ratio < 1.0 / 2.39 || ratio > 2.39) {
            return null
        }
        return Rational(videoWidth, videoHeight)
    }

    private fun createPlaybackRemoteAction(): RemoteAction {
        val iconResource = if (playbackPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val label = if (playbackPlaying) "Pause" else "Start"
        val intent = Intent(ACTION_TOGGLE_PLAYBACK).setPackage(packageName)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            PLAYBACK_ACTION_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return RemoteAction(
            Icon.createWithResource(this, iconResource),
            label,
            label,
            pendingIntent,
        )
    }

    private fun supportsPictureInPicture(): Boolean {
        return packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun registerPlaybackActionReceiver() {
        val filter = IntentFilter(ACTION_TOGGLE_PLAYBACK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(playbackActionReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(playbackActionReceiver, filter)
        }
        receiverRegistered = true
    }
}
