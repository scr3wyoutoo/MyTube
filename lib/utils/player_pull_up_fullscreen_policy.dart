import 'dart:ui';

class PlayerPullUpFullscreenPolicy {
  const PlayerPullUpFullscreenPolicy._();

  static const double dragExtent = 180;
  static const double completionThreshold = 0.4;
  static const double minimumUpwardFlingVelocity = -700;
  static const double centerStartFraction = 0.25;
  static const double centerEndFraction = 0.75;

  static bool canStart({
    required bool fullscreen,
    required bool pictureInPicture,
  }) => fullscreen && !pictureInPicture;

  static bool startsInCenter({
    required Offset position,
    required Size viewport,
  }) {
    if (viewport.width <= 0 || viewport.height <= 0) {
      return false;
    }
    final minimumX = viewport.width * centerStartFraction;
    final maximumX = viewport.width * centerEndFraction;
    final minimumY = viewport.height * centerStartFraction;
    final maximumY = viewport.height * centerEndFraction;
    return position.dx >= minimumX &&
        position.dx <= maximumX &&
        position.dy >= minimumY &&
        position.dy <= maximumY;
  }

  static double progressForDistance(double upwardDistance) =>
      (upwardDistance / dragExtent).clamp(0, 1).toDouble();

  static bool shouldComplete({
    required double progress,
    required double primaryVelocity,
  }) =>
      progress >= completionThreshold ||
      primaryVelocity <= minimumUpwardFlingVelocity;
}
