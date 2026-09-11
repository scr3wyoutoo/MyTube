class PlayerPullDownFullscreenPolicy {
  const PlayerPullDownFullscreenPolicy._();

  static const double dragExtent = 240;
  static const double completionThreshold = 0.4;
  static const double minimumFlingVelocity = 700;
  static const double listTopTolerance = 0.5;

  static bool canStart({
    required bool portrait,
    required bool playerSectionActive,
    required bool fullscreen,
    required bool pictureInPicture,
    required bool keyboardVisible,
  }) =>
      portrait &&
      playerSectionActive &&
      !fullscreen &&
      !pictureInPicture &&
      !keyboardVisible;

  static bool listGestureStartsAtTop(double extentBefore) =>
      extentBefore <= listTopTolerance;

  static double progressForDistance(double distance) =>
      (distance / dragExtent).clamp(0, 1).toDouble();

  static bool shouldComplete({
    required double progress,
    required double primaryVelocity,
  }) =>
      progress >= completionThreshold ||
      primaryVelocity >= minimumFlingVelocity;
}
