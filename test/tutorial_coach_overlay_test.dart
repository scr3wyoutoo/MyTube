import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/widgets/tutorial_coach_overlay.dart';

void main() {
  testWidgets('sperrt Ziele und übrige App-Inhalte standardmäßig', (
    tester,
  ) async {
    final targetKey = GlobalKey();
    var targetTaps = 0;
    var outsideTaps = 0;
    var nextTaps = 0;

    await tester.pumpWidget(
      _CoachTestApp(
        targetKey: targetKey,
        onTargetTap: () => targetTaps++,
        onOutsideTap: () => outsideTaps++,
        onNext: () => nextTaps++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('coach-test-target')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const Key('coach-test-outside')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(targetTaps, 0);
    expect(outsideTaps, 0);
    await tester.tap(find.byKey(const Key('tutorial-next-button')));
    await tester.pump();
    expect(nextTaps, 1);
  });

  testWidgets('lässt ausschließlich das freigegebene Ziel passieren', (
    tester,
  ) async {
    final targetKey = GlobalKey();
    var targetTaps = 0;
    var outsideTaps = 0;

    await tester.pumpWidget(
      _CoachTestApp(
        targetKey: targetKey,
        allowTargetInteraction: true,
        onTargetTap: () => targetTaps++,
        onOutsideTap: () => outsideTaps++,
        onNext: () {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coach-test-target')));
    await tester.tap(
      find.byKey(const Key('coach-test-outside')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(targetTaps, 1);
    expect(outsideTaps, 0);
  });
}

class _CoachTestApp extends StatelessWidget {
  const _CoachTestApp({
    required this.targetKey,
    required this.onTargetTap,
    required this.onOutsideTap,
    required this.onNext,
    this.allowTargetInteraction = false,
  });

  final GlobalKey targetKey;
  final VoidCallback onTargetTap;
  final VoidCallback onOutsideTap;
  final VoidCallback onNext;
  final bool allowTargetInteraction;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 24,
              top: 48,
              child: KeyedSubtree(
                key: targetKey,
                child: FilledButton(
                  key: const Key('coach-test-target'),
                  onPressed: onTargetTap,
                  child: const Text('Target'),
                ),
              ),
            ),
            Positioned(
              right: 24,
              top: 48,
              child: FilledButton(
                key: const Key('coach-test-outside'),
                onPressed: onOutsideTap,
                child: const Text('Outside'),
              ),
            ),
            Positioned.fill(
              child: TutorialCoachOverlay(
                targetKey: targetKey,
                sectionLabel: 'Test',
                tutorial: 1,
                tutorialCount: 1,
                title: 'Interaction lock',
                message: 'Only the coach remains interactive.',
                step: 1,
                stepCount: 1,
                onSkip: () {},
                onNext: onNext,
                allowTargetInteraction: allowTargetInteraction,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
