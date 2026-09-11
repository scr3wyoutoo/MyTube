import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/search_history.dart';

void main() {
  test('begrenzt, normalisiert und verschiebt Wiederholungen nach vorn', () {
    var history = <String>[];
    for (var index = 1; index <= 11; index++) {
      history = addSearchHistoryEntry(history, ' Suche $index ');
    }

    expect(history, hasLength(searchHistoryLimit));
    expect(history.first, 'Suche 11');
    expect(history.last, 'Suche 2');

    history = addSearchHistoryEntry(history, 'suche 5');
    expect(history.first, 'suche 5');
    expect(
      history.where((entry) => entry.toLowerCase() == 'suche 5'),
      hasLength(1),
    );
  });

  test('zeigt erst ab zwei Zeichen passende eindeutige Einträge', () {
    const history = ['Arte Doku', 'Flutter Tutorial', 'Spät bei ARTE'];

    expect(matchingSearchHistory(history, 'a'), isEmpty);
    expect(matchingSearchHistory(history, 'ar'), [
      'Arte Doku',
      'Spät bei ARTE',
    ]);
    expect(matchingSearchHistory(history, 'TTER'), ['Flutter Tutorial']);
  });

  test('löscht einen Eintrag dauerhaft ohne Groß-/Kleinschreibung', () {
    expect(
      removeSearchHistoryEntry(const [
        'Arte Doku',
        'Flutter Tutorial',
      ], ' arte doku '),
      ['Flutter Tutorial'],
    );
  });
}
