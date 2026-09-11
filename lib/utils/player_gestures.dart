Duration doubleTapSeekOffset({required double localX, required double width}) {
  return localX < width / 2
      ? const Duration(seconds: -10)
      : const Duration(seconds: 10);
}

bool isCenterPlaybackTap({required double localX, required double width}) {
  if (width <= 0) {
    return false;
  }
  return localX >= width * 0.32 && localX <= width * 0.68;
}
