import 'dart:async';

import 'package:flutter/material.dart';

enum PlayerGestureFeedback {
  play,
  rewindHold,
  forwardHold,
  rewindTen,
  forwardTen,
}

bool shouldShowPlayerLoadingIndicator({
  required bool buffering,
  required bool changingQuality,
  required bool nativeIosVideoLoading,
}) => buffering || changingQuality || nativeIosVideoLoading;

bool shouldShowPersistentPauseFeedback({
  required bool playing,
  required bool buffering,
  required bool nativeIosVideoLoading,
}) => !nativeIosVideoLoading && !playing && !buffering;

class PlayerGestureFeedbackController
    extends ValueNotifier<PlayerGestureFeedback?> {
  PlayerGestureFeedbackController() : super(null);

  static const transientDuration = Duration(milliseconds: 500);

  Timer? _timer;

  void showTransient(PlayerGestureFeedback feedback) {
    _timer?.cancel();
    value = feedback;
    _timer = Timer(transientDuration, () {
      if (value == feedback) {
        value = null;
      }
    });
  }

  void showHold(PlayerGestureFeedback feedback) {
    assert(
      feedback == PlayerGestureFeedback.rewindHold ||
          feedback == PlayerGestureFeedback.forwardHold,
    );
    _timer?.cancel();
    _timer = null;
    value = feedback;
  }

  void clearHold() {
    if (value == PlayerGestureFeedback.rewindHold ||
        value == PlayerGestureFeedback.forwardHold) {
      value = null;
    }
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    value = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class PlayerGestureFeedbackOverlay extends StatelessWidget {
  const PlayerGestureFeedbackOverlay({
    super.key,
    required this.showPersistentPause,
    this.feedback,
  });

  final bool showPersistentPause;
  final PlayerGestureFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    final activeFeedback = feedback;
    if (activeFeedback == null && !showPersistentPause) {
      return const SizedBox.shrink();
    }

    final icon = switch (activeFeedback) {
      PlayerGestureFeedback.play => Icons.play_arrow,
      PlayerGestureFeedback.rewindHold => Icons.fast_rewind,
      PlayerGestureFeedback.forwardHold => Icons.fast_forward,
      PlayerGestureFeedback.rewindTen => Icons.replay_10,
      PlayerGestureFeedback.forwardTen => Icons.forward_10,
      null => Icons.pause,
    };
    final alignment = switch (activeFeedback) {
      PlayerGestureFeedback.rewindHold ||
      PlayerGestureFeedback.rewindTen => const Alignment(-0.62, 0),
      PlayerGestureFeedback.forwardHold ||
      PlayerGestureFeedback.forwardTen => const Alignment(0.62, 0),
      PlayerGestureFeedback.play || null => Alignment.center,
    };
    final feedbackKey = switch (activeFeedback) {
      PlayerGestureFeedback.play => 'player-gesture-play-feedback',
      PlayerGestureFeedback.rewindHold => 'player-gesture-rewind-hold-feedback',
      PlayerGestureFeedback.forwardHold =>
        'player-gesture-forward-hold-feedback',
      PlayerGestureFeedback.rewindTen => 'player-gesture-rewind-ten-feedback',
      PlayerGestureFeedback.forwardTen => 'player-gesture-forward-ten-feedback',
      null => 'player-gesture-pause-feedback',
    };

    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: DecoratedBox(
          key: ValueKey(feedbackKey),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(
              icon,
              size: 58,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}
