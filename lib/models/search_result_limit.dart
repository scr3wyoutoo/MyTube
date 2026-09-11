const int searchResultLimit = 100;
const String searchResultLimitText = '- 100 Treffer -';

List<T> limitSearchResults<T>(Iterable<T> items) {
  return List<T>.unmodifiable(items.take(searchResultLimit));
}

List<T> appendUniqueSearchResults<T>({
  required List<T> current,
  required Iterable<T> additions,
  required String Function(T item) idOf,
}) {
  final limitedCurrent = current.take(searchResultLimit).toList(growable: true);
  if (limitedCurrent.length >= searchResultLimit) {
    return List<T>.unmodifiable(limitedCurrent);
  }
  final knownIds = limitedCurrent.map(idOf).toSet();
  for (final item in additions) {
    if (knownIds.add(idOf(item))) {
      limitedCurrent.add(item);
      if (limitedCurrent.length == searchResultLimit) {
        break;
      }
    }
  }
  return List<T>.unmodifiable(limitedCurrent);
}
