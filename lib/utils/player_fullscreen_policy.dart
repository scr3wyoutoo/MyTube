import 'package:flutter/services.dart';

class PlayerFullscreenPolicy {
  const PlayerFullscreenPolicy._();

  static const supportedFullscreenOrientations = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static const exitOrientations = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  static bool usesFullscreenLayout({
    required bool fullscreenRequested,
    required bool landscape,
  }) => fullscreenRequested || landscape;
}
