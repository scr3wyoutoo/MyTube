enum HybridPlaybackSleepPhase {
  foreground,
  backgroundPlaying,
  remoteStandby,
  softSleep,
  deepSleep,
}

class HybridPlaybackSleepTransition {
  const HybridPlaybackSleepTransition({
    required this.previous,
    required this.current,
    required this.deadline,
  });

  final HybridPlaybackSleepPhase previous;
  final HybridPlaybackSleepPhase current;
  final DateTime? deadline;

  bool get changed => previous != current;
}

/// Models background playback readiness without owning platform resources.
///
/// A session that entered the background while playing retains its PiP or
/// system-media surface in [HybridPlaybackSleepPhase.remoteStandby] after a
/// remote pause. A session that entered without playback, or whose remote
/// surface was closed, enters soft sleep immediately and deep sleep after the
/// configured grace period.
class HybridPlaybackSleepModel {
  HybridPlaybackSleepModel({this.deepSleepDelay = const Duration(minutes: 15)});

  final Duration deepSleepDelay;

  HybridPlaybackSleepPhase _phase = HybridPlaybackSleepPhase.foreground;
  DateTime? _deadline;

  HybridPlaybackSleepPhase get phase => _phase;
  DateTime? get deadline => _deadline;

  bool get isBackground => _phase != HybridPlaybackSleepPhase.foreground;

  bool get keepsRemoteSurface =>
      _phase == HybridPlaybackSleepPhase.backgroundPlaying ||
      _phase == HybridPlaybackSleepPhase.remoteStandby;

  HybridPlaybackSleepTransition enterBackground({
    required bool playing,
    required DateTime now,
  }) {
    if (_phase != HybridPlaybackSleepPhase.foreground) {
      return playbackChanged(playing: playing, now: now);
    }
    return _moveTo(
      playing
          ? HybridPlaybackSleepPhase.backgroundPlaying
          : HybridPlaybackSleepPhase.softSleep,
      now: now,
    );
  }

  HybridPlaybackSleepTransition enterForeground() =>
      _moveTo(HybridPlaybackSleepPhase.foreground);

  HybridPlaybackSleepTransition playbackChanged({
    required bool playing,
    required DateTime now,
  }) {
    switch (_phase) {
      case HybridPlaybackSleepPhase.backgroundPlaying:
        return playing
            ? _unchanged()
            : _moveTo(HybridPlaybackSleepPhase.remoteStandby);
      case HybridPlaybackSleepPhase.remoteStandby:
        return playing
            ? _moveTo(HybridPlaybackSleepPhase.backgroundPlaying)
            : _unchanged();
      case HybridPlaybackSleepPhase.foreground:
      case HybridPlaybackSleepPhase.softSleep:
      case HybridPlaybackSleepPhase.deepSleep:
        return _unchanged();
    }
  }

  HybridPlaybackSleepTransition remoteSurfaceClosed({required DateTime now}) {
    if (_phase == HybridPlaybackSleepPhase.backgroundPlaying ||
        _phase == HybridPlaybackSleepPhase.remoteStandby) {
      return _moveTo(HybridPlaybackSleepPhase.softSleep, now: now);
    }
    return _unchanged();
  }

  HybridPlaybackSleepTransition evaluateDeadline({required DateTime now}) {
    final deadline = _deadline;
    if (_phase == HybridPlaybackSleepPhase.softSleep &&
        deadline != null &&
        !now.isBefore(deadline)) {
      return _moveTo(HybridPlaybackSleepPhase.deepSleep);
    }
    return _unchanged();
  }

  HybridPlaybackSleepTransition _moveTo(
    HybridPlaybackSleepPhase next, {
    DateTime? now,
  }) {
    final previous = _phase;
    _phase = next;
    _deadline = next == HybridPlaybackSleepPhase.softSleep
        ? (now ?? DateTime.now()).add(deepSleepDelay)
        : null;
    return HybridPlaybackSleepTransition(
      previous: previous,
      current: _phase,
      deadline: _deadline,
    );
  }

  HybridPlaybackSleepTransition _unchanged() => HybridPlaybackSleepTransition(
    previous: _phase,
    current: _phase,
    deadline: _deadline,
  );
}
