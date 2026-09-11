import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef IosPictureInPictureStarted = void Function();
typedef IosPictureInPictureStopped =
    void Function(
      Duration position,
      bool shouldResume,
      bool restoredUserInterface,
    );
typedef IosPictureInPictureFailed = void Function(String message);
typedef IosPictureInPictureCompleted = void Function();
typedef IosPictureInPictureAdvanced = void Function();
typedef IosPictureInPictureAudioRoutePaused = void Function();
typedef IosPictureInPicturePlaybackChanged = void Function(bool playing);
typedef IosPictureInPictureAutoEnterCancelled = void Function();
typedef IosMainPlayerStateChanged =
    void Function(IosMainPlayerState playbackState);

class IosMainPlayerState {
  const IosMainPlayerState({
    required this.position,
    required this.duration,
    required this.playing,
    required this.buffering,
    required this.width,
    required this.height,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final int? width;
  final int? height;

  factory IosMainPlayerState.fromMap(Map<Object?, Object?> values) {
    int intValue(String key) {
      final value = values[key];
      return value is num ? value.round() : 0;
    }

    return IosMainPlayerState(
      position: Duration(milliseconds: intValue('positionMilliseconds')),
      duration: Duration(milliseconds: intValue('durationMilliseconds')),
      playing: values['playing'] == true,
      buffering: values['buffering'] == true,
      width: intValue('width') > 0 ? intValue('width') : null,
      height: intValue('height') > 0 ? intValue('height') : null,
    );
  }
}

class IosPictureInPicture {
  IosPictureInPicture._();

  static final IosPictureInPicture instance = IosPictureInPicture._();
  static const MethodChannel _channel = MethodChannel(
    'flutter_browser_app/ios_picture_in_picture',
  );

  IosPictureInPictureStarted? _onStarted;
  IosPictureInPictureStopped? _onStopped;
  IosPictureInPictureFailed? _onFailed;
  IosPictureInPictureCompleted? _onCompleted;
  IosPictureInPictureAdvanced? _onAdvanced;
  IosPictureInPictureAudioRoutePaused? _onAudioRoutePaused;
  IosPictureInPicturePlaybackChanged? _onPlaybackChanged;
  IosPictureInPictureAutoEnterCancelled? _onAutoEnterCancelled;
  IosMainPlayerStateChanged? _onMainPlayerStateChanged;

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> attach({
    required IosPictureInPictureStarted onStarted,
    required IosPictureInPictureStopped onStopped,
    required IosPictureInPictureFailed onFailed,
    IosPictureInPictureCompleted? onCompleted,
    IosPictureInPictureAdvanced? onAdvanced,
    IosPictureInPictureAudioRoutePaused? onAudioRoutePaused,
    IosPictureInPicturePlaybackChanged? onPlaybackChanged,
    IosPictureInPictureAutoEnterCancelled? onAutoEnterCancelled,
    IosMainPlayerStateChanged? onMainPlayerStateChanged,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    _onStarted = onStarted;
    _onStopped = onStopped;
    _onFailed = onFailed;
    _onCompleted = onCompleted;
    _onAdvanced = onAdvanced;
    _onAudioRoutePaused = onAudioRoutePaused;
    _onPlaybackChanged = onPlaybackChanged;
    _onAutoEnterCancelled = onAutoEnterCancelled;
    _onMainPlayerStateChanged = onMainPlayerStateChanged;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<bool> openMainPlayer({
    required Uri streamUrl,
    required String title,
    required String artist,
    required String thumbnailUrl,
    required double playbackVolume,
    required Duration position,
    required bool playing,
    required bool autoEnterEnabled,
    required bool pictureInPictureEnabled,
    required bool continuesAudioInBackground,
    required bool isLive,
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('openMainPlayer', {
            'streamUrl': streamUrl.toString(),
            'title': title,
            'artist': artist,
            'thumbnailUrl': thumbnailUrl,
            'playbackVolume': playbackVolume,
            'positionMilliseconds': position.inMilliseconds,
            'playing': playing,
            'autoEnterEnabled': autoEnterEnabled,
            'pictureInPictureEnabled': pictureInPictureEnabled,
            'continuesAudioInBackground': continuesAudioInBackground,
            'isLive': isLive,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> seek(Duration position) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('seek', {
        'positionMilliseconds': position.inMilliseconds,
      });
    } on MissingPluginException {
      // Unsupported embedding: the caller keeps its current position.
    }
  }

  Future<bool> configure({
    required bool enabled,
    Uri? streamUrl,
    String title = '',
    String artist = '',
    String thumbnailUrl = '',
    double playbackVolume = 1,
    bool playlistFadeEnabled = false,
    bool hasNextItem = false,
    bool autoEnterEnabled = false,
    bool isLive = false,
    String debugResolution = '',
    String debugTransport = '',
    bool debugIsHls = false,
    bool debugHasHlsMaster = false,
    bool debugHasSeparateAudio = false,
    bool debugUsesProxy = false,
    String debugSourceScheme = '',
    String debugSourcePath = '',
    String debugMime = '',
    int? debugContentLength,
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('configure', <String, Object?>{
            'enabled': enabled,
            'streamUrl': streamUrl?.toString(),
            'title': title,
            'artist': artist,
            'thumbnailUrl': thumbnailUrl,
            'playbackVolume': playbackVolume,
            'playlistFadeEnabled': playlistFadeEnabled,
            'hasNextItem': hasNextItem,
            'autoEnterEnabled': autoEnterEnabled,
            'isLive': isLive,
            'debugResolution': debugResolution,
            'debugTransport': debugTransport,
            'debugIsHls': debugIsHls,
            'debugHasHlsMaster': debugHasHlsMaster,
            'debugHasSeparateAudio': debugHasSeparateAudio,
            'debugUsesProxy': debugUsesProxy,
            'debugSourceScheme': debugSourceScheme,
            'debugSourcePath': debugSourcePath,
            'debugMime': debugMime,
            'debugContentLength': debugContentLength,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> setAutoEnterEnabled(bool enabled) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setAutoEnterEnabled', <String, Object>{
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Unsupported embedding: automatic PiP remains unavailable.
    }
  }

  Future<void> setVolume(double volume) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setVolume', <String, Object>{
        'volume': volume,
      });
    } on MissingPluginException {
      // Unsupported embedding: the normal player remains authoritative.
    }
  }

  Future<void> pause() async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('pause');
    } on MissingPluginException {
      // Unsupported embedding: the normal player remains authoritative.
    }
  }

  Future<void> play() async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('play');
    } on MissingPluginException {
      // Unsupported embedding: the normal player remains authoritative.
    }
  }

  Future<bool> configureNext({
    required Uri streamUrl,
    required String title,
    required String artist,
    required String thumbnailUrl,
    required bool hasNextItem,
    bool isLive = false,
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel
              .invokeMethod<bool>('configureNext', <String, Object>{
                'streamUrl': streamUrl.toString(),
                'title': title,
                'artist': artist,
                'thumbnailUrl': thumbnailUrl,
                'hasNextItem': hasNextItem,
                'isLive': isLive,
              }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> clearNext() async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('clearNext');
    } on MissingPluginException {
      // Unsupported embedding: no native next player exists.
    }
  }

  Future<bool> start({
    required Duration position,
    required bool playing,
    bool seekToPosition = true,
    int? debugRequestId,
    bool notifyFailure = true,
    Duration readinessTimeout = const Duration(seconds: 15),
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('start', <String, Object?>{
            'positionMilliseconds': position.inMilliseconds,
            'playing': playing,
            'seekToPosition': seekToPosition,
            'debugRequestId': debugRequestId,
            'notifyFailure': notifyFailure,
            'readinessTimeoutMilliseconds': readinessTimeout.inMilliseconds,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> armAutoEnter({
    required Duration position,
    required bool playing,
    bool seekToPosition = true,
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('armAutoEnter', <String, Object>{
            'positionMilliseconds': position.inMilliseconds,
            'playing': playing,
            'seekToPosition': seekToPosition,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> cancelAutoEnter() async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancelAutoEnter');
    } on MissingPluginException {
      // Unsupported embedding: no automatic native handoff is armed.
    }
  }

  Future<Map<String, Object?>> readDebugState({
    required int requestId,
    required String checkpoint,
    required String trigger,
  }) async {
    if (!isSupportedPlatform) {
      return const <String, Object?>{};
    }
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'readDebugState',
        <String, Object?>{
          'requestId': requestId,
          'checkpoint': checkpoint,
          'trigger': trigger,
        },
      );
      if (raw == null) {
        return const <String, Object?>{};
      }
      return <String, Object?>{
        for (final entry in raw.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      };
    } on MissingPluginException {
      return const <String, Object?>{};
    } on PlatformException catch (error) {
      return <String, Object?>{
        'debugReadError': '${error.code}: ${error.message ?? ''}',
      };
    }
  }

  Future<Map<String, Object?>> testHlsReadiness({
    required Uri streamUrl,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!isSupportedPlatform) {
      return const <String, Object?>{};
    }
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'testHlsReadiness',
        <String, Object>{
          'streamUrl': streamUrl.toString(),
          'timeoutMilliseconds': timeout.inMilliseconds,
        },
      );
      if (raw == null) {
        return const <String, Object?>{};
      }
      return <String, Object?>{
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    } on MissingPluginException {
      return const <String, Object?>{};
    } on PlatformException catch (error) {
      return <String, Object?>{
        'testError': '${error.code}: ${error.message ?? ''}',
      };
    }
  }

  Future<void> stop() async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Unsupported embedding: leave the normal player running.
    }
  }

  Future<void> detach() async {
    if (!isSupportedPlatform) {
      return;
    }
    _onStarted = null;
    _onStopped = null;
    _onFailed = null;
    _onCompleted = null;
    _onAdvanced = null;
    _onAudioRoutePaused = null;
    _onPlaybackChanged = null;
    _onAutoEnterCancelled = null;
    _onMainPlayerStateChanged = null;
    await configure(enabled: false);
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'started':
        _onStarted?.call();
        return;
      case 'stopped':
        final arguments = call.arguments;
        if (arguments is Map) {
          final rawPosition = arguments['positionMilliseconds'];
          final position = Duration(
            milliseconds: rawPosition is int ? rawPosition : 0,
          );
          _onStopped?.call(
            position,
            arguments['shouldResume'] == true,
            arguments['restoredUserInterface'] == true,
          );
        }
        return;
      case 'failed':
        _onFailed?.call(
          call.arguments?.toString() ?? 'iOS-PiP ist fehlgeschlagen.',
        );
        return;
      case 'completed':
        _onCompleted?.call();
        return;
      case 'advanced':
        _onAdvanced?.call();
        return;
      case 'pausedByAudioRouteChange':
        _onAudioRoutePaused?.call();
        return;
      case 'playbackStateChanged':
        final arguments = call.arguments;
        if (arguments is Map) {
          _onPlaybackChanged?.call(arguments['playing'] == true);
          _onMainPlayerStateChanged?.call(
            IosMainPlayerState.fromMap(arguments),
          );
        }
        return;
      case 'autoEnterCancelled':
        _onAutoEnterCancelled?.call();
        return;
    }
  }
}
