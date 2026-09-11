import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef IosNativeAudioStateChanged =
    void Function(IosNativeAudioPlaybackState state);

class IosNativeAudioPlaybackState {
  const IosNativeAudioPlaybackState({
    required this.position,
    required this.duration,
    required this.playing,
    required this.buffering,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;

  factory IosNativeAudioPlaybackState.fromMap(Map<Object?, Object?> values) {
    int intValue(String key) {
      final value = values[key];
      return value is num ? value.round() : 0;
    }

    return IosNativeAudioPlaybackState(
      position: Duration(milliseconds: intValue('positionMilliseconds')),
      duration: Duration(milliseconds: intValue('durationMilliseconds')),
      playing: values['playing'] == true,
      buffering: values['buffering'] == true,
    );
  }
}

class IosNativeAudioPlayback {
  IosNativeAudioPlayback._();

  static final IosNativeAudioPlayback instance = IosNativeAudioPlayback._();
  static const MethodChannel _channel = MethodChannel(
    'flutter_browser_app/ios_native_audio_playback',
  );

  IosNativeAudioStateChanged? _onStateChanged;
  VoidCallback? _onCompleted;
  VoidCallback? _onAdvanced;
  VoidCallback? _onPreviousRequested;
  VoidCallback? _onNextRequested;
  VoidCallback? _onAudioRoutePaused;
  void Function(String message)? _onFailed;

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> attach({
    required IosNativeAudioStateChanged onStateChanged,
    required VoidCallback onCompleted,
    required VoidCallback onAdvanced,
    required VoidCallback onPreviousRequested,
    required VoidCallback onNextRequested,
    required VoidCallback onAudioRoutePaused,
    required void Function(String message) onFailed,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    _onStateChanged = onStateChanged;
    _onCompleted = onCompleted;
    _onAdvanced = onAdvanced;
    _onPreviousRequested = onPreviousRequested;
    _onNextRequested = onNextRequested;
    _onAudioRoutePaused = onAudioRoutePaused;
    _onFailed = onFailed;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<bool> open({
    required Uri streamUrl,
    required String title,
    required String artist,
    required String thumbnailUrl,
    required double volume,
    required Duration position,
    required bool playing,
    required bool hasPrevious,
    required bool hasNext,
    Duration? expectedDuration,
    bool remoteControlsEnabled = true,
    Duration crossfadeDuration = const Duration(seconds: 6),
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('open', <String, Object>{
            'streamUrl': streamUrl.toString(),
            'title': title,
            'artist': artist,
            'thumbnailUrl': thumbnailUrl,
            'volume': volume,
            'positionMilliseconds': position.inMilliseconds,
            'playing': playing,
            'hasPrevious': hasPrevious,
            'hasNext': hasNext,
            if (expectedDuration != null)
              'expectedDurationMilliseconds': expectedDuration.inMilliseconds,
            'remoteControlsEnabled': remoteControlsEnabled,
            'crossfadeMilliseconds': crossfadeDuration.inMilliseconds,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> prepareNext({
    required Uri streamUrl,
    required String title,
    required String artist,
    required String thumbnailUrl,
    required bool hasNext,
    Duration? expectedDuration,
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('prepareNext', <String, Object>{
            'streamUrl': streamUrl.toString(),
            'title': title,
            'artist': artist,
            'thumbnailUrl': thumbnailUrl,
            'hasNext': hasNext,
            if (expectedDuration != null)
              'expectedDurationMilliseconds': expectedDuration.inMilliseconds,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> updateNavigation({
    required bool hasPrevious,
    required bool hasNext,
  }) => _invokeVoid('updateNavigation', <String, Object>{
    'hasPrevious': hasPrevious,
    'hasNext': hasNext,
  });

  Future<void> play() => _invokeVoid('play');

  Future<void> pause() => _invokeVoid('pause');

  Future<void> seek(Duration position) => _invokeVoid('seek', <String, Object>{
    'positionMilliseconds': position.inMilliseconds,
  });

  Future<void> setVolume(double volume) =>
      _invokeVoid('setVolume', <String, Object>{'volume': volume});

  Future<void> clearNext() => _invokeVoid('clearNext');

  Future<void> stop() => _invokeVoid('stop');

  Future<void> detach() async {
    if (!isSupportedPlatform) {
      return;
    }
    _onStateChanged = null;
    _onCompleted = null;
    _onAdvanced = null;
    _onPreviousRequested = null;
    _onNextRequested = null;
    _onAudioRoutePaused = null;
    _onFailed = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _invokeVoid(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // The iOS-only native backend is unavailable on this embedding.
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'stateChanged':
        final arguments = call.arguments;
        if (arguments is Map) {
          _onStateChanged?.call(IosNativeAudioPlaybackState.fromMap(arguments));
        }
        return;
      case 'completed':
        _onCompleted?.call();
        return;
      case 'advanced':
        _onAdvanced?.call();
        return;
      case 'previousRequested':
        _onPreviousRequested?.call();
        return;
      case 'nextRequested':
        _onNextRequested?.call();
        return;
      case 'pausedByAudioRouteChange':
        _onAudioRoutePaused?.call();
        return;
      case 'failed':
        _onFailed?.call(call.arguments?.toString() ?? 'AVPlayer audio failed.');
        return;
    }
  }
}
