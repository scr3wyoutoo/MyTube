import 'package:flutter_browser_app/utils/hybrid_playback_sleep_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 8, 16, 12);

  test('Hintergrund ohne Wiedergabe wechselt nach 15 Minuten tief', () {
    final model = HybridPlaybackSleepModel();

    final background = model.enterBackground(playing: false, now: start);

    expect(background.current, HybridPlaybackSleepPhase.softSleep);
    expect(background.deadline, start.add(const Duration(minutes: 15)));
    expect(
      model
          .evaluateDeadline(
            now: start.add(const Duration(minutes: 14, seconds: 59)),
          )
          .current,
      HybridPlaybackSleepPhase.softSleep,
    );
    expect(
      model
          .evaluateDeadline(now: start.add(const Duration(minutes: 15)))
          .current,
      HybridPlaybackSleepPhase.deepSleep,
    );
  });

  test('remote pausiertes Medium bleibt ohne Zeitlimit fernsteuerbar', () {
    final model = HybridPlaybackSleepModel();

    model.enterBackground(playing: true, now: start);
    final paused = model.playbackChanged(
      playing: false,
      now: start.add(const Duration(seconds: 10)),
    );

    expect(paused.current, HybridPlaybackSleepPhase.remoteStandby);
    expect(paused.deadline, isNull);
    expect(
      model.evaluateDeadline(now: start.add(const Duration(hours: 2))).current,
      HybridPlaybackSleepPhase.remoteStandby,
    );
    expect(
      model
          .playbackChanged(
            playing: true,
            now: start.add(const Duration(hours: 2)),
          )
          .current,
      HybridPlaybackSleepPhase.backgroundPlaying,
    );
  });

  test('Schliessen der Fernsteuerung startet die Soft-Sleep-Frist', () {
    final model = HybridPlaybackSleepModel();
    final closedAt = start.add(const Duration(minutes: 30));

    model.enterBackground(playing: true, now: start);
    model.playbackChanged(
      playing: false,
      now: start.add(const Duration(minutes: 1)),
    );
    final closed = model.remoteSurfaceClosed(now: closedAt);

    expect(closed.current, HybridPlaybackSleepPhase.softSleep);
    expect(closed.deadline, closedAt.add(const Duration(minutes: 15)));
  });

  test('Vordergrund beendet jede offene Sleep-Frist', () {
    final model = HybridPlaybackSleepModel();

    model.enterBackground(playing: false, now: start);
    final foreground = model.enterForeground();

    expect(foreground.current, HybridPlaybackSleepPhase.foreground);
    expect(foreground.deadline, isNull);
    expect(
      model.evaluateDeadline(now: start.add(const Duration(hours: 1))).current,
      HybridPlaybackSleepPhase.foreground,
    );
  });

  test('Soft- und Deep-Sleep lassen keinen Hintergrundstart zu', () {
    final model = HybridPlaybackSleepModel();
    model.enterBackground(playing: false, now: start);

    expect(
      model.playbackChanged(playing: true, now: start).current,
      HybridPlaybackSleepPhase.softSleep,
    );
    model.evaluateDeadline(now: start.add(const Duration(minutes: 15)));
    expect(
      model.playbackChanged(playing: true, now: start).current,
      HybridPlaybackSleepPhase.deepSleep,
    );
  });
}
