const int searchHistoryLimit = 10;
const int searchHistoryMinimumMatchLength = 2;

List<String> sanitizeSearchHistory(Iterable<String> entries) {
  final sanitized = <String>[];
  final knownEntries = <String>{};
  for (final entry in entries) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty || !knownEntries.add(trimmed.toLowerCase())) {
      continue;
    }
    sanitized.add(trimmed);
    if (sanitized.length == searchHistoryLimit) {
      break;
    }
  }
  return List<String>.unmodifiable(sanitized);
}

List<String> addSearchHistoryEntry(Iterable<String> history, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return sanitizeSearchHistory(history);
  }
  final normalized = trimmed.toLowerCase();
  return sanitizeSearchHistory([
    trimmed,
    ...history.where((entry) => entry.trim().toLowerCase() != normalized),
  ]);
}

List<String> removeSearchHistoryEntry(Iterable<String> history, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return sanitizeSearchHistory(history);
  }
  return sanitizeSearchHistory(
    history.where((entry) => entry.trim().toLowerCase() != normalized),
  );
}

List<String> matchingSearchHistory(Iterable<String> history, String input) {
  final normalized = input.trim().toLowerCase();
  if (normalized.length < searchHistoryMinimumMatchLength) {
    return const [];
  }
  return List<String>.unmodifiable(
    sanitizeSearchHistory(
      history,
    ).where((entry) => entry.toLowerCase().contains(normalized)),
  );
}
