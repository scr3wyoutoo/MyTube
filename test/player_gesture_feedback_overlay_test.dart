import 'package:flutter/material.dart';
import 'package:flutter_browser_app/widgets/player_gesture_feedback_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS-Videoladen zeigt Loading statt persistenter Pause', () {
    expect(
      shouldShowPlayerLoadingIndicator(
        buffering: false,
        changingQuality: false,
        nativeIosVideoLoading: true,
      ),
      isTrue,
    );
    expect(
      shouldShowPersistentPauseFeedback(
        playing: false,
        buffering: false,
        nativeIosVideoLoading: true,
      ),
      isFalse,
    );
  });

  test('fertig geladene echte Pause behält das Pause-Zeichen', () {
    expect(
      shouldShowPlayerLoadingIndicator(
        buffering: false,
        changingQuality: false,
        nativeIosVideoLoading: false,
      ),
      isFalse,
    );
    expect(
      shouldShowPersistentPauseFeedback(
        playing: false,
        buffering: false,
        nativeIosVideoLoading: false,
      ),
      isTrue,
    );
  });

  test('bestehende Buffering- und Qualitätsindikatoren bleiben aktiv', () {
    expect(
      shouldShowPlayerLoadingIndicator(
        buffering: true,
        changingQuality: false,
        nativeIosVideoLoading: false,
      ),
      isTrue,
    );
    expect(
      shouldShowPlayerLoadingIndicator(
        buffering: false,
        changingQuality: true,
        nativeIosVideoLoading: false,
      ),
      isTrue,
    );
  });

  testWidgets('blendet transientes Feedback nach exakt 500 ms aus', (
    tester,
  ) async {
    final controller = PlayerGestureFeedbackController();
    addTearDown(controller.dispose);

    controller.showTransient(PlayerGestureFeedback.play);
    expect(controller.value, PlayerGestureFeedback.play);

    await tester.pump(const Duration(milliseconds: 499));
    expect(controller.value, PlayerGestureFeedback.play);

    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.value, isNull);
  });

  testWidgets('Hold-Feedback bleibt bis zum Loslassen sichtbar', (
    tester,
  ) async {
    final controller = PlayerGestureFeedbackController();
    addTearDown(controller.dispose);

    controller.showHold(PlayerGestureFeedback.rewindHold);
    await tester.pump(const Duration(seconds: 2));
    expect(controller.value, PlayerGestureFeedback.rewindHold);

    controller.clearHold();
    expect(controller.value, isNull);
  });

  testWidgets(
    'zeigt Pause dauerhaft und Richtungsfeedback auf der richtigen Seite',
    (tester) async {
      Future<void> pumpOverlay({
        required bool paused,
        PlayerGestureFeedback? feedback,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox(
              width: 400,
              height: 220,
              child: PlayerGestureFeedbackOverlay(
                showPersistentPause: paused,
                feedback: feedback,
              ),
            ),
          ),
        ),
      );

      await pumpOverlay(paused: true);
      expect(
        find.byKey(const ValueKey('player-gesture-pause-feedback')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await pumpOverlay(paused: true, feedback: PlayerGestureFeedback.play);
      expect(
        find.byKey(const ValueKey('player-gesture-play-feedback')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pause), findsNothing);

      await pumpOverlay(
        paused: false,
        feedback: PlayerGestureFeedback.rewindTen,
      );
      final rewindCenter = tester.getCenter(
        find.byKey(const ValueKey('player-gesture-rewind-ten-feedback')),
      );
      expect(rewindCenter.dx, lessThan(200));
      expect(find.byIcon(Icons.replay_10), findsOneWidget);

      await pumpOverlay(
        paused: false,
        feedback: PlayerGestureFeedback.forwardHold,
      );
      final forwardCenter = tester.getCenter(
        find.byKey(const ValueKey('player-gesture-forward-hold-feedback')),
      );
      expect(forwardCenter.dx, greaterThan(200));
      expect(find.byIcon(Icons.fast_forward), findsOneWidget);
    },
  );
}
