import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../l10n/app_localizations.dart';

class TutorialCoachOverlay extends StatefulWidget {
  const TutorialCoachOverlay({
    super.key,
    required this.targetKey,
    this.additionalTargetKeys = const [],
    required this.sectionLabel,
    required this.tutorial,
    required this.tutorialCount,
    required this.title,
    required this.message,
    required this.step,
    required this.stepCount,
    required this.onSkip,
    required this.onNext,
    this.onBack,
    this.nextLabel,
    this.nextEnabled = true,
    this.showNextButton = true,
    this.allowTargetInteraction = false,
  });

  final GlobalKey targetKey;
  final List<GlobalKey> additionalTargetKeys;
  final String sectionLabel;
  final int tutorial;
  final int tutorialCount;
  final String title;
  final String message;
  final int step;
  final int stepCount;
  final VoidCallback onSkip;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final String? nextLabel;
  final bool nextEnabled;
  final bool showNextButton;
  final bool allowTargetInteraction;

  @override
  State<TutorialCoachOverlay> createState() => _TutorialCoachOverlayState();
}

class _TutorialCoachOverlayState extends State<TutorialCoachOverlay> {
  List<Rect> _targetRects = const [];
  Timer? _measurementRetryTimer;
  int _remainingMeasurementAttempts = 6;

  @override
  void initState() {
    super.initState();
    _scheduleMeasurement();
  }

  @override
  void didUpdateWidget(TutorialCoachOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey ||
        !listEquals(
          oldWidget.additionalTargetKeys,
          widget.additionalTargetKeys,
        )) {
      _targetRects = const [];
      _remainingMeasurementAttempts = 6;
    }
    _scheduleMeasurement();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMeasurement();
  }

  void _scheduleMeasurement() {
    _measurementRetryTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final measuredRects = [
        widget.targetKey,
        ...widget.additionalTargetKeys,
      ].map(_measureTarget).whereType<Rect>().toList(growable: false);
      if (!listEquals(measuredRects, _targetRects)) {
        setState(() => _targetRects = measuredRects);
      }
      if (measuredRects.length < 1 + widget.additionalTargetKeys.length &&
          _remainingMeasurementAttempts > 0) {
        _remainingMeasurementAttempts--;
        _measurementRetryTimer = Timer(
          const Duration(milliseconds: 50),
          _scheduleMeasurement,
        );
      }
    });
  }

  Rect? _measureTarget(GlobalKey targetKey) {
    final renderObject = targetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  @override
  void dispose() {
    _measurementRetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final highlightedRects = _targetRects
        .map((rect) => rect.inflate(7))
        .toList(growable: false);
    final targetBounds = highlightedRects.isEmpty
        ? null
        : highlightedRects
              .skip(1)
              .fold(
                highlightedRects.first,
                (bounds, rect) => bounds.expandToInclude(rect),
              );
    final targetIsHigh =
        targetBounds == null ||
        targetBounds.center.dy < screenSize.height * 0.52;

    return Stack(
      key: const Key('tutorial-coach-overlay'),
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _TutorialScrimPainter(targetRects: highlightedRects),
            ),
          ),
        ),
        Positioned.fill(
          child: _TutorialPointerBlocker(
            key: const Key('tutorial-interaction-blocker'),
            passThroughGlobalRects: widget.allowTargetInteraction
                ? _targetRects.take(1).toList(growable: false)
                : const [],
          ),
        ),
        for (var index = 0; index < highlightedRects.length; index++)
          Positioned.fromRect(
            rect: highlightedRects[index],
            child: IgnorePointer(
              child: SizedBox(key: ValueKey('tutorial-highlight-$index')),
            ),
          ),
        Positioned.fill(
          child: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Align(
              alignment: targetIsHigh
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Material(
                  key: const Key('tutorial-coach-card'),
                  elevation: 12,
                  color: Theme.of(context).colorScheme.surface,
                  surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.tutorialStep(
                            widget.sectionLabel,
                            widget.tutorial,
                            widget.tutorialCount,
                            widget.step,
                            widget.stepCount,
                          ),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          widget.title,
                          key: const Key('tutorial-coach-title'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(widget.message),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  key: const Key('tutorial-skip-button'),
                                  onPressed: widget.onSkip,
                                  child: Text(context.l10n.skipTutorial),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 88,
                              child: widget.showNextButton
                                  ? FilledButton(
                                      key: const Key('tutorial-next-button'),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                      ),
                                      onPressed: widget.nextEnabled
                                          ? widget.onNext
                                          : null,
                                      child: Text(
                                        widget.nextLabel ?? context.l10n.next,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 72,
                              child: widget.onBack == null
                                  ? const SizedBox.shrink()
                                  : TextButton(
                                      key: const Key('tutorial-back-button'),
                                      onPressed: widget.onBack,
                                      child: Text(context.l10n.back),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TutorialPointerBlocker extends SingleChildRenderObjectWidget {
  const _TutorialPointerBlocker({
    super.key,
    required this.passThroughGlobalRects,
  }) : super(child: const SizedBox.expand());

  final List<Rect> passThroughGlobalRects;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTutorialPointerBlocker(passThroughGlobalRects);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTutorialPointerBlocker renderObject,
  ) {
    renderObject.passThroughGlobalRects = passThroughGlobalRects;
  }
}

class _RenderTutorialPointerBlocker extends RenderProxyBox {
  _RenderTutorialPointerBlocker(this._passThroughGlobalRects);

  List<Rect> _passThroughGlobalRects;

  set passThroughGlobalRects(List<Rect> value) {
    if (listEquals(_passThroughGlobalRects, value)) {
      return;
    }
    _passThroughGlobalRects = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }
    final globalPosition = localToGlobal(position);
    if (_passThroughGlobalRects.any((rect) => rect.contains(globalPosition))) {
      return false;
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

class _TutorialScrimPainter extends CustomPainter {
  const _TutorialScrimPainter({required this.targetRects});

  final List<Rect> targetRects;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    for (final target in targetRects) {
      path.addRRect(RRect.fromRectAndRadius(target, const Radius.circular(14)));
    }
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.68),
    );
    for (final target in targetRects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(target, const Radius.circular(14)),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_TutorialScrimPainter oldDelegate) =>
      !listEquals(oldDelegate.targetRects, targetRects);
}
