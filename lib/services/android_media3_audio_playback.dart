import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'runtime_android_platform_stub.dart'
    if (dart.library.io) 'runtime_android_platform_io.dart';

typedef AndroidMedia3AudioStateChanged =
    void Function(AndroidMedia3AudioPlaybackState state);

class AndroidMedia3AudioPlaybackState {
  const AndroidMedia3AudioPlaybackState({
    required this.position,
    required this.duration,
    required this.playing,
    required this.buffering,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;

  factory AndroidMedia3AudioPlaybackState.fromMap(
    Map<Object?, Object?> values,
  ) {
    int intValue(String key) {
      final value = values[key];
      return value is num ? value.round() : 0;
    }

    return AndroidMedia3AudioPlaybackState(
      position: Duration(milliseconds: intValue('positionMilliseconds')),
      duration: Duration(milliseconds: intValue('durationMilliseconds')),
      playing: values['playing'] == true,
      buffering: values['buffering'] == true,
    );
  }
}

class AndroidMedia3AudioPlayback {
  AndroidMedia3AudioPlayback._();

  static final AndroidMedia3AudioPlayback instance =
      AndroidMedia3AudioPlayback._();
  @visibleForTesting
  static bool? debugSupportedPlatformOverride;
  static const MethodChannel _channel = MethodChannel(
    'flutter_browser_app/android_media3_audio_playback',
  );

  AndroidMedia3AudioStateChanged? _onStateChanged;
  VoidCallback? _onCompleted;
  VoidCallback? _onAdvanced;
  void Function(String message)? _onFailed;

  bool get isSupportedPlatform =>
      debugSupportedPlatformOverride ?? isRuntimeAndroid;

  Future<void> attach({
    required AndroidMedia3AudioStateChanged onStateChanged,
    required VoidCallback onCompleted,
    required VoidCallback onAdvanced,
    required void Function(String message) onFailed,
  }) async {
    if (!isSupportedPlatform) return;
    _onStateChanged = onStateChanged;
    _onCompleted = onCompleted;
    _onAdvanced = onAdvanced;
    _onFailed = onFailed;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<bool> open({
    required Uri streamUrl,
    required Map<String, String> headers,
    required bool isHls,
    required double volume,
    required Duration position,
    required bool playing,
    Duration? expectedDuration,
    Duration crossfadeDuration = const Duration(seconds: 6),
  }) async {
    if (!isSupportedPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('open', <String, Object>{
            'streamUrl': streamUrl.toString(),
            'headers': headers,
            'isHls': isHls,
            'volume': volume.clamp(0.0, 1.0),
            'positionMilliseconds': position.inMilliseconds,
            'playing': playing,
            if (expectedDuration != null)
              'expectedDurationMilliseconds': expectedDuration.inMilliseconds,
            'crossfadeMilliseconds': crossfadeDuration.inMilliseconds,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> prepareNext({
    required Uri streamUrl,
    required Map<String, String> headers,
    required bool isHls,
    Duration? expectedDuration,
  }) async {
    if (!isSupportedPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('prepareNext', <String, Object>{
            'streamUrl': streamUrl.toString(),
            'headers': headers,
            'isHls': isHls,
            if (expectedDuration != null)
              'expectedDurationMilliseconds': expectedDuration.inMilliseconds,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> play() => _invokeVoid('play');

  Future<void> pause() => _invokeVoid('pause');

  Future<void> seek(Duration position) => _invokeVoid('seek', <String, Object>{
    'positionMilliseconds': position.inMilliseconds,
  });

  Future<void> setVolume(double volume) => _invokeVoid(
    'setVolume',
    <String, Object>{'volume': volume.clamp(0.0, 1.0)},
  );

  Future<void> clearNext() => _invokeVoid('clearNext');

  Future<void> stop() => _invokeVoid('stop');

  Future<void> detach() async {
    if (!isSupportedPlatform) return;
    _onStateChanged = null;
    _onCompleted = null;
    _onAdvanced = null;
    _onFailed = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _invokeVoid(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    if (!isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Android is the only embedding that provides this backend.
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'stateChanged':
        final arguments = call.arguments;
        if (arguments is Map) {
          _onStateChanged?.call(
            AndroidMedia3AudioPlaybackState.fromMap(arguments),
          );
        }
        return;
      case 'completed':
        _onCompleted?.call();
        return;
      case 'advanced':
        _onAdvanced?.call();
        return;
      case 'failed':
        _onFailed?.call(
          call.arguments?.toString() ?? 'Media3 audio playback failed.',
        );
        return;
    }
  }
}
