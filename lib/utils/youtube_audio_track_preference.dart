String normalizeYoutubeAudioLanguage(String languageCode) {
  final normalized = languageCode.trim().toLowerCase();
  return normalized == 'en' || normalized.startsWith('en-') ? 'en' : 'de';
}

int youtubeAudioTrackLanguageScore({
  required String languageCode,
  required String trackId,
  required String displayName,
  required bool isDefault,
}) {
  final language = normalizeYoutubeAudioLanguage(languageCode);
  final normalizedId = trackId.trim().toLowerCase();
  final normalizedName = displayName.trim().toLowerCase();

  var score = -1;
  if (_hasLanguagePrefix(normalizedId, language)) {
    score = 100;
  } else if (_displayNameMatches(normalizedName, language)) {
    score = 80;
  }
  if (score < 0) {
    return score;
  }

  if (_isDescriptiveAudio(normalizedName)) {
    score -= 25;
  } else {
    score += 10;
  }
  if (isDefault) {
    score += 2;
  }
  return score;
}

bool _hasLanguagePrefix(String trackId, String language) {
  if (trackId == language) {
    return true;
  }
  return trackId.startsWith('$language-') ||
      trackId.startsWith('${language}_') ||
      trackId.startsWith('$language.');
}

bool _displayNameMatches(String displayName, String language) {
  final names = language == 'en'
      ? const ['english', 'englisch']
      : const ['deutsch', 'german'];
  return names.any(displayName.contains);
}

bool _isDescriptiveAudio(String displayName) {
  return const [
    'audiodeskrip',
    'audio description',
    'descriptive audio',
    'beschreibende audio',
  ].any(displayName.contains);
}
