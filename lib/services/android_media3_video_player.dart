import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'runtime_android_platform_stub.dart'
    if (dart.library.io) 'runtime_android_platform_io.dart';

const String androidMedia3VideoViewType =
    'flutter_browser_app/android_media3_video_view';

class AndroidMedia3VideoState {
  const AndroidMedia3VideoState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.playbackRequested = false,
    this.buffering = false,
    this.width = 0,
    this.height = 0,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool playbackRequested;
  final bool buffering;
  final int width;
  final int height;
}

class AndroidMedia3VideoException implements Exception {
  const AndroidMedia3VideoException(this.message, {this.details = ''});

  final String message;
  final String details;

  @override
  String toString() => details.isEmpty ? message : '$message\n\n$details';
}

class AndroidMedia3VideoPlayer {
  AndroidMedia3VideoPlayer._();

  static final AndroidMedia3VideoPlayer instance = AndroidMedia3VideoPlayer._();

  static const MethodChannel _channel = MethodChannel(
    'flutter_browser_app/android_media3_video_player',
  );

  final ValueNotifier<AndroidMedia3VideoState> state = ValueNotifier(
    const AndroidMedia3VideoState(),
  );
  final Map<int, Completer<void>> _pendingLoads = {};
  int _nextLoadId = 0;
  int _activeLoadId = 0;
  bool _attached = false;
  VoidCallback? _onCompleted;
  ValueChanged<AndroidMedia3VideoException>? _onError;

  bool get isSupportedPlatform => isRuntimeAndroid;

  Future<void> attach({
    required VoidCallback onCompleted,
    required ValueChanged<AndroidMedia3VideoException> onError,
  }) async {
    if (!isSupportedPlatform) return;
    _onCompleted = onCompleted;
    _onError = onError;
    if (_attached) return;
    _attached = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> load({
    required Uri videoUrl,
    Uri? audioUrl,
    required bool isHls,
    required Map<String, String> headers,
    required Duration? position,
    required bool play,
    required double volume,
    Duration? expectedDuration,
  }) async {
    if (!isSupportedPlatform) {
      throw const AndroidMedia3VideoException(
        'Media3 ist auf dieser Plattform nicht verfügbar.',
      );
    }
    final loadId = ++_nextLoadId;
    _activeLoadId = loadId;
    for (final pending in _pendingLoads.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          const AndroidMedia3VideoException(
            'Der vorherige Media3-Ladevorgang wurde ersetzt.',
          ),
        );
      }
    }
    _pendingLoads.clear();
    final ready = Completer<void>();
    _pendingLoads[loadId] = ready;
    state.value = AndroidMedia3VideoState(
      position: position ?? Duration.zero,
      playbackRequested: play,
      buffering: true,
    );
    try {
      await _channel.invokeMethod<void>('load', <String, Object?>{
        'loadId': loadId,
        'videoUrl': videoUrl.toString(),
        'audioUrl': audioUrl?.toString(),
        'isHls': isHls,
        'headers': headers,
        'positionMs': position?.inMilliseconds,
        'play': play,
        'volume': volume.clamp(0.0, 1.0),
        'expectedDurationMs': expectedDuration?.inMilliseconds ?? 0,
      });
      await ready.future.timeout(const Duration(seconds: 20));
    } finally {
      _pendingLoads.remove(loadId);
    }
  }

  Future<void> play() => _invoke('play');

  Future<void> pause() => _invoke('pause');

  Future<void> seek(Duration position) =>
      _invoke('seek', <String, Object?>{'positionMs': position.inMilliseconds});

  Future<void> setVolume(double volume) =>
      _invoke('setVolume', <String, Object?>{'volume': volume.clamp(0.0, 1.0)});

  Future<void> stop() async {
    if (!isSupportedPlatform || !_attached) return;
    await _invoke('stop');
    state.value = const AndroidMedia3VideoState();
  }

  Future<void> detach({bool release = false}) async {
    if (!isSupportedPlatform) return;
    _onCompleted = null;
    _onError = null;
    for (final pending in _pendingLoads.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          const AndroidMedia3VideoException(
            'Der Media3-Player wurde geschlossen.',
          ),
        );
      }
    }
    _pendingLoads.clear();
    if (_attached) {
      try {
        await _channel.invokeMethod<void>(release ? 'dispose' : 'stop');
      } on MissingPluginException {
        // Tests and non-Android hosts intentionally have no native endpoint.
      }
    }
    _channel.setMethodCallHandler(null);
    _attached = false;
    state.value = const AndroidMedia3VideoState();
  }

  Future<void> _invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (!isSupportedPlatform || !_attached) return;
    await _channel.invokeMethod<void>(method, arguments);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final arguments = call.arguments is Map
        ? Map<Object?, Object?>.from(call.arguments as Map)
        : const <Object?, Object?>{};
    final loadId = _int(arguments['loadId']);
    if (loadId != 0 && loadId != _activeLoadId) return;
    switch (call.method) {
      case 'ready':
        final pending = _pendingLoads[loadId];
        if (pending != null && !pending.isCompleted) pending.complete();
        break;
      case 'state':
        state.value = AndroidMedia3VideoState(
          position: Duration(milliseconds: _int(arguments['positionMs'])),
          duration: Duration(milliseconds: _int(arguments['durationMs'])),
          playing: arguments['playing'] == true,
          playbackRequested: arguments['playbackRequested'] == true,
          buffering: arguments['buffering'] == true,
          width: _int(arguments['width']),
          height: _int(arguments['height']),
        );
        break;
      case 'completed':
        _onCompleted?.call();
        break;
      case 'error':
        final error = AndroidMedia3VideoException(
          arguments['message']?.toString() ?? 'Media3-Wiedergabefehler',
          details:
              'Media3 ${arguments['errorCodeName'] ?? ''} '
              '(${arguments['errorCode'] ?? ''})\n'
              '${arguments['cause'] ?? ''}',
        );
        final pending = _pendingLoads[loadId];
        if (pending != null && !pending.isCompleted) {
          pending.completeError(error);
        }
        _onError?.call(error);
        break;
    }
  }

  int _int(Object? value) => value is num ? value.toInt() : 0;
}

class AndroidMedia3VideoView extends StatelessWidget {
  const AndroidMedia3VideoView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AndroidView(
      viewType: androidMedia3VideoViewType,
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    );
  }
}
