import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/mytube_theme.dart';

/// Zeigt die vollständige MyTube-Grafik nach dem eingeschränkten
/// Android-12-System-Splash. Der eigentliche App-Inhalt wird bereits darunter
/// aufgebaut und steht nach der kurzen Ausblendung unmittelbar bereit.
class MyTubeStartupSplash extends StatefulWidget {
  const MyTubeStartupSplash({
    super.key,
    required this.child,
    this.minimumDuration = const Duration(milliseconds: 700),
    this.fadeDuration = const Duration(milliseconds: 250),
  });

  final Widget child;
  final Duration minimumDuration;
  final Duration fadeDuration;

  @override
  State<MyTubeStartupSplash> createState() => _MyTubeStartupSplashState();
}

class _MyTubeStartupSplashState extends State<MyTubeStartupSplash> {
  Timer? _hideTimer;
  bool _visible = true;
  bool _mountedOverlay = true;

  @override
  void initState() {
    super.initState();
    _hideTimer = Timer(widget.minimumDuration, () {
      if (mounted) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_mountedOverlay)
          Positioned.fill(
            child: AnimatedOpacity(
              key: const ValueKey('mytube-startup-splash'),
              opacity: _visible ? 1 : 0,
              duration: widget.fadeDuration,
              onEnd: () {
                if (!_visible && mounted) {
                  setState(() => _mountedOverlay = false);
                }
              },
              child: const MyTubeSplashArtwork(),
            ),
          ),
      ],
    );
  }
}

class MyTubeSplashArtwork extends StatelessWidget {
  const MyTubeSplashArtwork({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey('mytube-splash-artwork'),
      color: MyTubeColors.cream,
      child: SafeArea(
        child: Center(
          child: Image(
            image: AssetImage('assets/branding/mytube_splash_source.png'),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
