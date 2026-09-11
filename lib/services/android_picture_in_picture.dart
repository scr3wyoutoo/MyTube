import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef PictureInPictureModeChanged =
    void Function(bool active, bool restoredToApp);

class AndroidPictureInPicture {
  AndroidPictureInPicture._();

  static final AndroidPictureInPicture instance = AndroidPictureInPicture._();
  static const MethodChannel _channel = MethodChannel(
    'flutter_browser_app/picture_in_picture',
  );

  Future<void> Function()? _onTogglePlayback;
  PictureInPictureModeChanged? _onModeChanged;

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> attach({
    required Future<void> Function() onTogglePlayback,
    required PictureInPictureModeChanged onModeChanged,
    required bool playing,
    required int videoWidth,
    required int videoHeight,
    bool enabled = true,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    _onTogglePlayback = onTogglePlayback;
    _onModeChanged = onModeChanged;
    _channel.setMethodCallHandler(_handleMethodCall);
    await update(
      enabled: enabled,
      playing: playing,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
    );
  }

  Future<void> update({
    required bool enabled,
    required bool playing,
    required int videoWidth,
    required int videoHeight,
    bool? autoEnterEnabled,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('configure', <String, Object>{
        'enabled': enabled,
        'playing': playing,
        'autoEnterEnabled': autoEnterEnabled ?? enabled && playing,
        'videoWidth': videoWidth,
        'videoHeight': videoHeight,
      });
    } on MissingPluginException {
      // Keeps widget tests and unsupported Android embeddings functional.
    }
  }

  Future<void> detach() async {
    if (!isSupportedPlatform) {
      return;
    }
    _onTogglePlayback = null;
    _onModeChanged = null;
    await update(enabled: false, playing: false, videoWidth: 0, videoHeight: 0);
    _channel.setMethodCallHandler(null);
  }

  Future<bool> enter() async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'togglePlayback':
        await _onTogglePlayback?.call();
        return;
      case 'pictureInPictureModeChanged':
        final arguments = call.arguments;
        if (arguments is Map) {
          _onModeChanged?.call(
            arguments['active'] == true,
            arguments['restoredToApp'] == true,
          );
        } else {
          // Backward-compatible fallback for an older native host.
          _onModeChanged?.call(arguments == true, false);
        }
        return;
    }
  }
}
