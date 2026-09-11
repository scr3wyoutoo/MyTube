import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/l10n/app_localizations.dart';
import 'package:flutter_browser_app/models/video_search_source.dart';
import 'package:flutter_browser_app/models/youtube_search_category.dart';

void main() {
  test('liefert deutsche Texte als Standard', () {
    const l10n = AppLocalizations(Locale('de'));

    expect(l10n.search, 'Suche');
    expect(l10n.myProfile, 'Mein Profil');
    expect(l10n.next, 'Weiter');
    expect(l10n.nextTutorial, 'Nächstes');
    expect(l10n.finish, 'Fertig');
    expect(l10n.repeatTutorial, 'Tutorial wiederholen');
    expect(l10n.logFile, 'Logdatei');
    expect(l10n.clearLogFile, 'Logdatei leeren');
    expect(l10n.searchTutorialSourceTitle, 'YouTube oder YouTube Music');
    expect(l10n.hotMusicTutorialExploreTitle, 'Musik entdecken');
    expect(l10n.playerTutorialDoubleTapTitle, 'Zehn Sekunden springen');
    expect(l10n.playerTutorialOptionsTitle, 'Weitere Optionen');
    expect(
      l10n.tutorialStep('Suche', 2, 4, 3, 5),
      'Suche-Tutorial (2/4) · Schritt 3 von 5',
    );
    expect(
      l10n.searchHint(VideoSearchSource.youtube, YouTubeSearchCategory.videos),
      'Suchbegriff eingeben',
    );
  });

  test('liefert englische UI- und bekannte Backend-Fehlermeldungen', () {
    const l10n = AppLocalizations(Locale('en'));

    expect(l10n.search, 'Search');
    expect(l10n.myProfile, 'My profile');
    expect(l10n.nextTutorial, 'Next');
    expect(l10n.finish, 'Finish');
    expect(l10n.repeatTutorial, 'Repeat tutorial');
    expect(l10n.logFile, 'Log file');
    expect(l10n.clearLogFile, 'Clear log file');
    expect(l10n.searchTutorialChannelsTitle, 'Channels and artists');
    expect(l10n.hotMusicTutorialGenresTitle, 'Moods and genres');
    expect(l10n.playerTutorialDoubleTapTitle, 'Jump ten seconds');
    expect(l10n.playerTutorialOptionsTitle, 'More options');
    expect(
      l10n.tutorialStep('Search', 2, 4, 3, 5),
      'Search tutorial (2/4) · Step 3 of 5',
    );
    expect(
      l10n.searchHint(
        VideoSearchSource.youtubeMusic,
        YouTubeSearchCategory.channels,
      ),
      'Enter artist name',
    );
    expect(
      l10n.translateKnownMessage(
        'Die YouTube-Music-Charts sind momentan nicht verfügbar.',
      ),
      'YouTube Music charts are currently unavailable.',
    );
    expect(
      l10n.translateKnownMessage('Bitte gib einen Profilnamen ein.'),
      'Please enter a profile name.',
    );
  });
}
