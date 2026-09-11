abstract final class PlaybackSeekPolicy {
  static bool canSeek({required bool isLive}) => !isLive;

  static Duration? mediaStart({
    required bool isLive,
    required Duration position,
  }) {
    return canSeek(isLive: isLive) ? position : null;
  }

  static bool shouldSeekAfterOpen({
    required bool isLive,
    required Duration position,
    required bool startedImmediately,
  }) {
    return canSeek(isLive: isLive) &&
        (position > Duration.zero || !startedImmediately);
  }

  static bool isNonSeekableStreamError(String details) {
    final normalized = details.toLowerCase();
    return normalized.contains('cannot seek in this stream') ||
        normalized.contains('can not seek in this stream');
  }
}
