Duration? parseMediaDuration(Object? value) {
  if (value is Duration) {
    return value > Duration.zero ? value : null;
  }
  if (value is num) {
    return _durationFromSeconds(value.toDouble());
  }
  if (value is! String) {
    return null;
  }

  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  if (!text.contains(':')) {
    return _durationFromSeconds(double.tryParse(text));
  }

  final parts = text.split(':');
  if (parts.length < 2 || parts.length > 3) {
    return null;
  }
  final seconds = double.tryParse(parts.last);
  final minutes = int.tryParse(parts[parts.length - 2]);
  final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
  if (seconds == null ||
      minutes == null ||
      hours == null ||
      seconds < 0 ||
      seconds >= 60 ||
      minutes < 0 ||
      (parts.length == 3 && minutes >= 60) ||
      hours < 0) {
    return null;
  }
  return _durationFromSeconds((hours * 3600) + (minutes * 60) + seconds);
}

Duration? youtubeStreamDuration(Uri uri) {
  for (final key in const ['dur', 'duration']) {
    final parsed = parseMediaDuration(uri.queryParameters[key]);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

Duration? mediaDurationFromDescription(String description) {
  final durationPattern = RegExp(r'^\d{1,3}:\d{2}(?::\d{2})?$');
  for (final segment in description.split('•').reversed) {
    final candidate = segment.trim();
    if (!durationPattern.hasMatch(candidate)) {
      continue;
    }
    final duration = parseMediaDuration(candidate);
    if (duration != null) {
      return duration;
    }
  }
  return null;
}

Duration? canonicalPlaybackDuration({
  Duration? streamDuration,
  Duration? catalogDuration,
}) {
  if (streamDuration != null &&
      streamDuration > Duration.zero &&
      catalogDuration != null &&
      catalogDuration > Duration.zero) {
    final difference =
        (streamDuration.inMilliseconds - catalogDuration.inMilliseconds).abs();
    // The signed stream URL usually contains the more precise value. If its
    // timeline materially disagrees with YouTube Music's displayed duration,
    // however, the catalog value represents the actual audible item and avoids
    // AVFoundation exposing a trailing container timeline as part of the song.
    return difference <= const Duration(seconds: 2).inMilliseconds
        ? streamDuration
        : catalogDuration;
  }
  if (streamDuration != null && streamDuration > Duration.zero) {
    return streamDuration;
  }
  if (catalogDuration != null && catalogDuration > Duration.zero) {
    return catalogDuration;
  }
  return null;
}

Duration? _durationFromSeconds(double? seconds) {
  if (seconds == null || !seconds.isFinite || seconds <= 0) {
    return null;
  }
  return Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );
}
