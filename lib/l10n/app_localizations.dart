import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/hot_music.dart';
import '../models/video_search_source.dart';
import '../models/youtube_search_category.dart';
import '../models/youtube_search_sort.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  static const supportedLocales = <Locale>[Locale('de'), Locale('en')];
  static const delegate = _AppLocalizationsDelegate();
  static const german = AppLocalizations(Locale('de'));

  final Locale locale;

  bool get isEnglish => locale.languageCode == 'en';

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ?? german;

  String get search => isEnglish ? 'Search' : 'Suche';
  String get hotMusic => 'Hot Music';
  String get myProfile => isEnglish ? 'My profile' : 'Mein Profil';
  String get cancel => isEnglish ? 'Cancel' : 'Abbrechen';
  String get create => isEnglish ? 'Create' : 'Erstellen';
  String get save => isEnglish ? 'Save' : 'Speichern';
  String get close => isEnglish ? 'Close' : 'Schließen';
  String get delete => isEnglish ? 'Delete' : 'Löschen';
  String get back => isEnglish ? 'Back' : 'Zurück';
  String get next => isEnglish ? 'Next' : 'Weiter';
  String get nextTutorial => isEnglish ? 'Next' : 'Nächstes';
  String get finish => isEnglish ? 'Finish' : 'Fertig';
  String get retry => isEnglish ? 'Try again' : 'Erneut versuchen';
  String get copy => isEnglish ? 'Copy' : 'Kopieren';
  String get searchAction => isEnglish ? 'Search' : 'Suchen';
  String get searchSourceTooltip =>
      isEnglish ? 'Select search source' : 'Suchquelle auswählen';
  String get clearSearchField =>
      isEnglish ? 'Clear search field' : 'Suchfeld leeren';
  String deleteSearchHistoryEntry(String entry) =>
      isEnglish ? 'Permanently delete “$entry”' : '„$entry“ dauerhaft löschen';

  String searchHint(VideoSearchSource source, YouTubeSearchCategory category) {
    final music = source == VideoSearchSource.youtubeMusic;
    return switch (category) {
      YouTubeSearchCategory.videos =>
        music
            ? (isEnglish
                  ? 'Song, artist or album'
                  : 'Song, Künstler oder Album')
            : (isEnglish ? 'Enter a search term' : 'Suchbegriff eingeben'),
      YouTubeSearchCategory.channels =>
        music
            ? (isEnglish ? 'Enter artist name' : 'Künstlername eingeben')
            : (isEnglish ? 'Enter channel name' : 'Channel-Name eingeben'),
      YouTubeSearchCategory.playlists =>
        music
            ? (isEnglish ? 'Search song playlists' : 'Song-Playlist suchen')
            : (isEnglish ? 'Search playlists' : 'Playlist suchen'),
    };
  }

  String searchLabel(VideoSearchSource source, YouTubeSearchCategory category) {
    final music = source == VideoSearchSource.youtubeMusic;
    return switch (category) {
      YouTubeSearchCategory.videos =>
        music
            ? (isEnglish ? 'YouTube Music search' : 'YouTube-Music-Suche')
            : (isEnglish ? 'YouTube search' : 'YouTube-Suche'),
      YouTubeSearchCategory.channels =>
        music
            ? (isEnglish ? 'Artist search' : 'Künstler-Suche')
            : (isEnglish ? 'Channel search' : 'Channel-Suche'),
      YouTubeSearchCategory.playlists =>
        music
            ? (isEnglish ? 'Song playlist search' : 'Song-Playlist-Suche')
            : (isEnglish ? 'Playlist search' : 'Playlist-Suche'),
    };
  }

  String categoryLabel(YouTubeSearchCategory category, {bool music = false}) =>
      switch (category) {
        YouTubeSearchCategory.videos => music ? 'Songs' : 'Videos',
        YouTubeSearchCategory.channels =>
          music ? (isEnglish ? 'Artists' : 'Künstler') : 'Channels',
        YouTubeSearchCategory.playlists => 'Playlists',
      };

  String categorySingular(
    YouTubeSearchCategory category, {
    bool music = false,
  }) => switch (category) {
    YouTubeSearchCategory.videos => music ? 'Song' : 'Video',
    YouTubeSearchCategory.channels =>
      music ? (isEnglish ? 'Artist' : 'Künstler') : 'Channel',
    YouTubeSearchCategory.playlists => 'Playlist',
  };

  String sortLabel(YouTubeSearchSort sort) => switch (sort) {
    YouTubeSearchSort.relevance => isEnglish ? 'Relevance' : 'Relevanz',
    YouTubeSearchSort.uploadDate => isEnglish ? 'Newest' : 'Neueste',
    YouTubeSearchSort.viewCount => isEnglish ? 'Most viewed' : 'Meistgesehen',
    YouTubeSearchSort.rating => isEnglish ? 'Top rated' : 'Bestbewertet',
  };
  String sortTooltip(YouTubeSearchSort sort) => isEnglish
      ? 'Sorting: ${sortLabel(sort)}'
      : 'Sortierung: ${sortLabel(sort)}';

  String hotMusicSection(HotMusicSection section) => switch (section) {
    HotMusicSection.explore => isEnglish ? 'Explore' : 'Entdecken',
    HotMusicSection.charts => 'Charts',
    HotMusicSection.genres => 'Genres',
  };
  String exploreFilter(HotMusicExploreFilter filter) => switch (filter) {
    HotMusicExploreFilter.trending => 'Trending Songs',
    HotMusicExploreFilter.newVideos => isEnglish ? 'New videos' : 'Neue Videos',
    HotMusicExploreFilter.newReleases =>
      isEnglish ? 'New releases' : 'Neuerscheinungen',
  };
  String genreFilter(HotMusicGenreFilter filter) => switch (filter) {
    HotMusicGenreFilter.moods => isEnglish ? 'Moods' : 'Stimmungen',
    HotMusicGenreFilter.genres => 'Genres',
  };
  String chartsFilter(HotMusicChartsFilter filter) => switch (filter) {
    HotMusicChartsFilter.videos => 'Videos',
    HotMusicChartsFilter.artists => isEnglish ? 'Artists' : 'Künstler',
  };

  String get previousTitle => isEnglish ? 'Previous title' : 'Vorheriger Titel';
  String get nextTitle => isEnglish ? 'Next title' : 'Nächster Titel';
  String get pause => isEnglish ? 'Pause' : 'Pause';
  String get play => isEnglish ? 'Play' : 'Start';
  String get pictureInPicture =>
      isEnglish ? 'Picture in picture' : 'Bild-in-Bild';
  String get exitFullscreen =>
      isEnglish ? 'Exit fullscreen' : 'Vollbild verlassen';
  String get fullscreen => isEnglish ? 'Fullscreen' : 'Vollbild';
  String get moreOptions => isEnglish ? 'More options' : 'Weitere Optionen';
  String get information => isEnglish ? 'Information' : 'Informationen';
  String get title => isEnglish ? 'Title' : 'Titel';
  String get channel => 'Channel';
  String get publicationDate =>
      isEnglish ? 'Publication date' : 'Veröffentlichungsdatum';
  String get description => isEnglish ? 'Description' : 'Beschreibung';
  String get source => isEnglish ? 'Source' : 'Quelle';
  String get unavailable => isEnglish ? 'Not available' : 'Nicht verfügbar';
  String formatDate(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return isEnglish
        ? '${twoDigits(value.month)}/${twoDigits(value.day)}/${value.year}'
        : '${twoDigits(value.day)}.${twoDigits(value.month)}.${value.year}';
  }

  String get descriptionLoading =>
      isEnglish ? 'Loading description …' : 'Beschreibung wird geladen …';
  String get noDescription =>
      isEnglish ? 'No description available.' : 'Keine Beschreibung verfügbar.';
  String get removeFavorite =>
      isEnglish ? 'Remove from favorites' : 'Aus Favoriten entfernen';
  String get addFavorite =>
      isEnglish ? 'Add to favorites' : 'Zu Favoriten hinzufügen';
  String get addToPlaylist =>
      isEnglish ? 'Add to playlist' : 'Zu Playlist hinzufügen';
  String get removeChannelFavorite =>
      isEnglish ? 'Remove channel favorite' : 'Channel-Favorit entfernen';
  String get addChannelFavorite =>
      isEnglish ? 'Save channel as favorite' : 'Channel als Favorit speichern';
  String get addCompletePlaylist =>
      isEnglish ? 'Add complete playlist' : 'Komplette Playlist hinzufügen';
  String get openPlaylist => isEnglish ? 'Open playlist' : 'Playlist öffnen';
  String videoCount(int count) => isEnglish ? '$count videos' : '$count Videos';
  String contentCount(int count) =>
      isEnglish ? '$count items' : '$count Inhalte';
  String newContentCount(int count, int newCount) => isEnglish
      ? '$count items · $newCount new'
      : '$count Inhalte · $newCount neu';

  String get newProfile => isEnglish ? 'New profile' : 'Neues Profil';
  String get profileName => isEnglish ? 'Profile name' : 'Profilname';
  String get profileNameHint => isEnglish ? 'e.g. Alex' : 'z. B. Alex';
  String get newPlaylist => isEnglish ? 'New playlist' : 'Neue Playlist';
  String get playlistName => isEnglish ? 'Playlist name' : 'Name der Playlist';
  String get renamePlaylist =>
      isEnglish ? 'Rename playlist' : 'Playlist umbenennen';
  String get newName => isEnglish ? 'New name' : 'Neuer Name';
  String get noPlaylistsCreated => isEnglish
      ? 'You have not created a playlist yet.'
      : 'Du hast noch keine Playlist erstellt.';
  String get playlistLoading =>
      isEnglish ? 'Loading playlist' : 'Playlist wird geladen';
  String get fetchingAllItems =>
      isEnglish ? 'Fetching all items …' : 'Alle Inhalte werden abgerufen …';
  String get playlistLoadFailed => isEnglish
      ? 'The playlist could not be loaded completely.'
      : 'Die Playlist konnte nicht vollständig geladen werden.';
  String get playlistEmpty => isEnglish
      ? 'The playlist contains no items.'
      : 'Die Playlist enthält keine Inhalte.';
  String addedToPlaylist(
    String name, {
    required bool single,
    required int count,
  }) {
    if (isEnglish) {
      return single ? 'Added to “$name”.' : 'Added $count items to “$name”.';
    }
    return single
        ? 'Zu „$name“ hinzugefügt.'
        : '$count Inhalte zu „$name“ hinzugefügt.';
  }

  String alreadyInPlaylist(String name, {required bool single}) {
    if (isEnglish) {
      return single
          ? 'The video is already in “$name”.'
          : 'All items are already in “$name”.';
    }
    return single
        ? 'Das Video ist bereits in „$name“.'
        : 'Alle Inhalte sind bereits in „$name“.';
  }

  String get profileMenu => isEnglish ? 'Profile menu' : 'Profilmenü';
  String get repeatTutorial =>
      isEnglish ? 'Repeat tutorial' : 'Tutorial wiederholen';
  String get logFile => isEnglish ? 'Log file' : 'Logdatei';
  String get clearLogFile => isEnglish ? 'Clear log file' : 'Logdatei leeren';
  String get logFileCopied =>
      isEnglish ? 'Log file copied.' : 'Logdatei kopiert.';
  String get logFileEmpty => isEnglish
      ? 'The log file does not contain any entries.'
      : 'Die Logdatei enthält noch keine Einträge.';
  String get logFileLoadFailed => isEnglish
      ? 'The log file could not be loaded.'
      : 'Die Logdatei konnte nicht geladen werden.';
  String get activeProfile => isEnglish ? 'Active profile' : 'Aktives Profil';
  String get language => isEnglish ? 'Language' : 'Sprache';
  String get deleteProfile => isEnglish ? 'Delete profile' : 'Profil löschen';
  String get deleteProfileQuestion =>
      isEnglish ? 'Delete profile?' : 'Profil löschen?';
  String deleteProfileMessage(String name) => isEnglish
      ? '“$name” and all associated favorites, channels, reactions and playlists will be permanently deleted from this device.'
      : '„$name“ sowie alle zugehörigen Favoriten, Channels, Reaktionen und Playlists werden dauerhaft von diesem Gerät gelöscht.';
  String get createProfile => isEnglish ? 'Create profile' : 'Profil erstellen';
  String get personalArea =>
      isEnglish ? 'Your personal area' : 'Dein persönlicher Bereich';
  String get createProfileDescription => isEnglish
      ? 'Create a local profile for favorites, channels, likes and playlists.'
      : 'Erstelle ein lokales Profil für Favoriten, Channels, Likes und Playlists.';
  String get favorites => isEnglish ? 'Favorites' : 'Favoriten';
  String get playlists => 'Playlists';
  String get channels => 'Channels';
  String get removeFromFavorites =>
      isEnglish ? 'Remove from favorites' : 'Aus Favoriten entfernen';
  String get noFavorites => isEnglish
      ? 'No favorites saved yet.'
      : 'Noch keine Favoriten gespeichert.';
  String get noChannels =>
      isEnglish ? 'No channels saved yet.' : 'Noch keine Channels gespeichert.';
  String get noPlaylists => isEnglish
      ? 'No playlists created yet.'
      : 'Noch keine Playlists erstellt.';
  String get playPlaylist => isEnglish ? 'Play playlist' : 'Playlist abspielen';
  String get rename => isEnglish ? 'Rename' : 'Umbenennen';
  String get removeFromPlaylist =>
      isEnglish ? 'Remove from playlist' : 'Aus Playlist entfernen';
  String get addVideosFromPlayer => isEnglish
      ? 'Add videos from the player page.'
      : 'Füge Videos über die Player-Seite hinzu.';
  String tutorialStep(
    String section,
    int tutorial,
    int tutorialCount,
    int step,
    int stepCount,
  ) => isEnglish
      ? '$section tutorial ($tutorial/$tutorialCount) · Step $step of $stepCount'
      : '$section-Tutorial ($tutorial/$tutorialCount) · Schritt $step von $stepCount';
  String get profileTutorialSection => isEnglish ? 'Profile' : 'Profil';
  String get searchTutorialSection => isEnglish ? 'Search' : 'Suche';
  String get hotMusicTutorialSection => 'Hot Music';
  String get playerTutorialSection => isEnglish ? 'Player' : 'Player';
  String get skipTutorial =>
      isEnglish ? 'Skip tutorial' : 'Tutorial überspringen';
  String get profileTutorialCreateTitle =>
      isEnglish ? 'Create your first profile' : 'Erstes Profil erstellen';
  String get profileTutorialCreateMessage => isEnglish
      ? 'Profiles keep favorites, playlists, channels, language and settings separate. Tap the highlighted button and create one with a unique name on this device to continue.'
      : 'Profile trennen Favoriten, Playlists, Channels, Sprache und Einstellungen. Tippe zum Fortfahren auf den markierten Button und erstelle eines mit einem auf diesem Gerät einmaligen Namen.';
  String get profileTutorialFavoritesTitle =>
      isEnglish ? 'Your favorites' : 'Deine Favoriten';
  String get profileTutorialFavoritesMessage => isEnglish
      ? 'Media marked with a heart is collected here for this profile.'
      : 'Medien, die du mit einem Herz markierst, werden hier für dieses Profil gesammelt.';
  String get profileTutorialPlaylistsTitle =>
      isEnglish ? 'Your playlists' : 'Deine Playlists';
  String get profileTutorialPlaylistsMessage => isEnglish
      ? 'Create playlists, add songs and videos, and change their order using the drag handles.'
      : 'Erstelle Playlists, füge Songs und Videos hinzu und ändere ihre Reihenfolge über die Ziehgriffe.';
  String get profileTutorialChannelsTitle => isEnglish
      ? 'Saved channels and artists'
      : 'Gespeicherte Channels und Künstler';
  String get profileTutorialChannelsMessage => isEnglish
      ? 'Channels and artists marked with a heart are kept separately from media favorites.'
      : 'Mit einem Herz markierte Channels und Künstler werden getrennt von Medien-Favoriten gespeichert.';
  String get profileTutorialAddTitle =>
      isEnglish ? 'Add another profile' : 'Weiteres Profil hinzufügen';
  String get profileTutorialAddMessage => isEnglish
      ? 'Use this button to create more profiles. Every profile needs a unique local name and keeps its own content and settings.'
      : 'Über diesen Button erstellst du weitere Profile. Jedes Profil braucht einen lokal einmaligen Namen und besitzt eigene Inhalte und Einstellungen.';
  String get profileTutorialMenuTitle => isEnglish
      ? 'Language and profile management'
      : 'Sprache und Profilverwaltung';
  String get profileTutorialMenuMessage => isEnglish
      ? 'The round profile picture opens the menu for language selection, the local log file and deleting the active profile.'
      : 'Das runde Profilbild öffnet das Menü für die Sprachwahl, die lokale Logdatei und zum Löschen des aktiven Profils.';
  String get profileTutorialLanguageDescription => isEnglish
      ? 'Changes all app labels and the language used for searches in this profile.'
      : 'Ändert alle App-Texte und die für Suchen verwendete Sprache dieses Profils.';
  String get profileTutorialDeleteDescription => isEnglish
      ? 'Permanently removes this profile and all of its locally saved content.'
      : 'Entfernt dieses Profil und alle darin lokal gespeicherten Inhalte dauerhaft.';
  String get profileTutorialRepeatDescription => isEnglish
      ? 'Restarts all four tutorial sections from the profile area.'
      : 'Startet alle vier Tutorialabschnitte erneut im Profilbereich.';
  String get searchTutorialSourceTitle =>
      isEnglish ? 'YouTube or YouTube Music' : 'YouTube oder YouTube Music';
  String get searchTutorialSourceMessage => isEnglish
      ? 'Use this dropdown to switch the complete search between videos and YouTube Music. The category labels and internal search path change with it.'
      : 'Über dieses Dropdown wechselst du die gesamte Suche zwischen Videos und YouTube Music. Die Rubriknamen und der interne Suchpfad wechseln dabei mit.';
  String get searchTutorialButtonTitle =>
      isEnglish ? 'Start the search' : 'Suche starten';
  String get searchTutorialButtonMessage => isEnglish
      ? 'Enter a term and tap the magnifying glass. The active source and category determine what MyTube searches for.'
      : 'Gib einen Begriff ein und tippe auf die Lupe. Die aktive Quelle und Rubrik bestimmen, wonach MyTube sucht.';
  String get searchTutorialVideosTitle =>
      isEnglish ? 'Videos and songs' : 'Videos und Songs';
  String get searchTutorialVideosMessage => isEnglish
      ? 'In YouTube mode this category finds videos. In Music mode the same position becomes Songs.'
      : 'Im YouTube-Modus sucht diese Rubrik Videos. Im Music-Modus wird dieselbe Position zu „Songs“.';
  String get searchTutorialChannelsTitle =>
      isEnglish ? 'Channels and artists' : 'Channels und Künstler';
  String get searchTutorialChannelsMessage => isEnglish
      ? 'Search for YouTube channels here. In Music mode this category searches for artists instead.'
      : 'Hier suchst du nach YouTube-Channels. Im Music-Modus sucht diese Rubrik stattdessen nach Künstlern.';
  String get searchTutorialPlaylistsTitle => 'Playlists';
  String get searchTutorialPlaylistsMessage => isEnglish
      ? 'This category searches for complete video or music playlists. Open a result to view and play its contents.'
      : 'Diese Rubrik sucht nach vollständigen Video- oder Musik-Playlists. Öffne einen Treffer, um die Inhalte anzusehen und abzuspielen.';
  String get hotMusicTutorialExploreTitle =>
      isEnglish ? 'Explore music' : 'Musik entdecken';
  String get hotMusicTutorialExploreMessage => isEnglish
      ? 'Explore contains filters for trending songs, new videos and new releases.'
      : '„Entdecken“ enthält Filter für Trending Songs, neue Videos und Neuerscheinungen.';
  String get hotMusicTutorialChartsTitle =>
      isEnglish ? 'Music charts' : 'Musik-Charts';
  String get hotMusicTutorialChartsMessage => isEnglish
      ? 'Charts lets you choose between video and artist charts. The separate country selector changes the chart region.'
      : '„Charts“ bietet Video- und Künstler-Charts. Über die separate Länderwahl änderst du die Chart-Region.';
  String get hotMusicTutorialGenresTitle =>
      isEnglish ? 'Moods and genres' : 'Stimmungen und Genres';
  String get hotMusicTutorialGenresMessage => isEnglish
      ? 'Genres switches between moods and genres. A selection opens the matching playlist collection.'
      : '„Genres“ wechselt zwischen Stimmungen und Genres. Eine Auswahl öffnet die passende Playlist-Sammlung.';
  String get hotMusicTutorialFavoriteTitle =>
      isEnglish ? 'Save as favorite' : 'Als Favorit speichern';
  String get hotMusicTutorialFavoriteMessage => isEnglish
      ? 'Use the heart to save this song in the favorites of the active profile.'
      : 'Mit dem Herz speicherst du diesen Song in den Favoriten des aktiven Profils.';
  String get hotMusicTutorialPlaylistTitle =>
      isEnglish ? 'Add to a playlist' : 'Zu einer Playlist hinzufügen';
  String get hotMusicTutorialPlaylistMessage => isEnglish
      ? 'This button adds the song to an existing personal playlist or creates a new one.'
      : 'Über diesen Button fügst du den Song einer vorhandenen eigenen Playlist hinzu oder erstellst eine neue.';
  String get hotMusicTutorialInfoTitle =>
      isEnglish ? 'Song information' : 'Song-Informationen';
  String get hotMusicTutorialInfoMessage => isEnglish
      ? 'The information button shows title, artist, publication date, full description and source. Continue to open this song paused in the player.'
      : 'Der Info-Button zeigt Titel, Künstler, Veröffentlichungsdatum, vollständige Beschreibung und Quelle. Danach wird dieser Song pausiert im Player geöffnet.';
  String get hotMusicTutorialSongUnavailable => isEnglish
      ? 'No playable tutorial song is available right now. Please try again.'
      : 'Momentan ist kein abspielbarer Tutorial-Song verfügbar. Bitte versuche es erneut.';
  String get playerTutorialCenterTitle =>
      isEnglish ? 'Play and pause' : 'Start und Pause';
  String get playerTutorialCenterMessage => isEnglish
      ? 'A single tap in the center of the image toggles playback. A paused medium stays paused until you resume it.'
      : 'Ein einfacher Tap in die Bildmitte wechselt zwischen Wiedergabe und Pause. Ein pausiertes Medium bleibt angehalten, bis du es fortsetzt.';
  String get playerTutorialDoubleTapTitle =>
      isEnglish ? 'Jump ten seconds' : 'Zehn Sekunden springen';
  String get playerTutorialDoubleTapMessage => isEnglish
      ? 'Double-tap the left side to jump back 10 seconds or the right side to jump forward 10 seconds.'
      : 'Mit einem Doppeltap links springst du 10 Sekunden zurück, mit einem Doppeltap rechts 10 Sekunden vor.';
  String get playerTutorialHoldTitle =>
      isEnglish ? 'Rewind and fast-forward' : 'Vor- und zurückspulen';
  String get playerTutorialHoldMessage => isEnglish
      ? 'Press and hold the left or right edge to rewind or fast-forward continuously. Release your finger to stop seeking.'
      : 'Halte den linken oder rechten Bildrand gedrückt, um fortlaufend zurück- oder vorzuspulen. Beim Loslassen endet das Spulen.';
  String get playerTutorialTransportTitle =>
      isEnglish ? 'Playback controls' : 'Wiedergabesteuerung';
  String get playerTutorialTransportMessage => isEnglish
      ? 'Previous follows your playback history. Play/Pause controls the current medium. Next first moves forward through history, then continues in the current queue.'
      : 'Zurück folgt deiner Wiedergabehistorie. Start/Pause steuert das aktuelle Medium. Vor geht zuerst durch die Historie und danach in der aktuellen Queue weiter.';
  String get playerTutorialOptionsTitle =>
      isEnglish ? 'More options' : 'Weitere Optionen';
  String get playerTutorialOptionsMessage => isEnglish
      ? 'The three-dot menu contains quality, subtitles, volume, mute and video brightness when available.'
      : 'Im Drei-Punkte-Menü findest du – soweit verfügbar – Qualität, Untertitel, Lautstärke, Mute und Videohelligkeit.';
  String get playerTutorialAutoplayTitle => 'Auto-Play';
  String get playerTutorialAutoplayMessage => isEnglish
      ? 'Auto-Play advances through the active history or queue and starts again at the beginning after the final item.'
      : 'Auto-Play spielt die aktive Historie beziehungsweise Queue weiter und beginnt nach dem letzten Eintrag wieder von vorn.';
  String get playerTutorialShuffleTitle =>
      isEnglish ? 'Shuffle the queue' : 'Queue mischen';
  String get playerTutorialShuffleMessage => isEnglish
      ? 'Shuffle is available while Auto-Play is active. It mixes the queue once and reshuffles it for every new loop.'
      : 'Shuffle ist bei aktivem Auto-Play verfügbar. Die Queue wird einmal gemischt und für jeden neuen Durchlauf erneut durchmischt.';
  String get playerTutorialReactionsTitle =>
      isEnglish ? 'Like or dislike' : 'Like oder Dislike';
  String get playerTutorialReactionsMessage => isEnglish
      ? 'Use these buttons to store your personal like or dislike for this medium in the active profile.'
      : 'Mit diesen Buttons speicherst du deine persönliche Like- oder Dislike-Wertung für dieses Medium im aktiven Profil.';
  String get playerTutorialFavoriteTitle =>
      isEnglish ? 'Save as favorite' : 'Als Favorit speichern';
  String get playerTutorialFavoriteMessage => isEnglish
      ? 'The heart adds or removes the current medium from the favorites of the active profile.'
      : 'Das Herz fügt das aktuelle Medium den Favoriten des aktiven Profils hinzu oder entfernt es wieder.';
  String get playerTutorialPlaylistTitle =>
      isEnglish ? 'Add to a playlist' : 'Zu einer Playlist hinzufügen';
  String get playerTutorialPlaylistMessage => isEnglish
      ? 'Add the current medium to an existing personal playlist or create a new playlist.'
      : 'Füge das aktuelle Medium einer vorhandenen eigenen Playlist hinzu oder erstelle eine neue Playlist.';
  String get playerTutorialInfoTitle =>
      isEnglish ? 'Media information' : 'Medien-Informationen';
  String get playerTutorialInfoMessage => isEnglish
      ? 'The information button shows title, channel or artist, publication date, description and source. This completes the tutorial.'
      : 'Der Info-Button zeigt Titel, Channel beziehungsweise Künstler, Veröffentlichungsdatum, Beschreibung und Quelle. Damit ist das Tutorial abgeschlossen.';
  String deletePlaylistQuestion(String name) => isEnglish
      ? '“$name” will be removed from this profile.'
      : '„$name“ wird aus diesem Profil entfernt.';
  String get deletePlaylistTitle =>
      isEnglish ? 'Delete playlist?' : 'Playlist löschen?';

  String get enterSearchTerm => isEnglish
      ? 'Please enter a search term.'
      : 'Bitte gib einen Suchbegriff ein.';
  String get searchInProgress => isEnglish ? 'Searching …' : 'Suche läuft …';
  String get searchUnavailableTitle =>
      isEnglish ? 'Search unavailable' : 'Suche nicht möglich';
  String get unexpectedSearchError => isEnglish
      ? 'An unexpected error occurred during the search.'
      : 'Bei der Suche ist ein unerwarteter Fehler aufgetreten.';
  String get searchTimeout => isEnglish
      ? 'The search took longer than 10 seconds. Please try again.'
      : 'Die Suche hat länger als 10 Sekunden gedauert. Bitte versuche es erneut.';
  String noMoreResults(String query) => isEnglish
      ? 'No more results for “$query”.'
      : 'Keine weiteren Ergebnisse für „$query“.';
  String get resultLimitReached => isEnglish ? '100 results' : '100 Treffer';
  String get noMoreHits =>
      isEnglish ? 'No more results' : 'Keine weiteren Treffer';
  String get noAdditionalResults => isEnglish
      ? 'No additional results yet.'
      : 'Noch keine weiteren Ergebnisse.';
  String get browseArtists =>
      isEnglish ? 'Browse artists' : 'Künstler durchsuchen';
  String get browseSongs => isEnglish ? 'Browse songs' : 'Songs durchsuchen';
  String browseSource(String source) =>
      isEnglish ? 'Browse $source' : '$source durchsuchen';
  String get browseChannels =>
      isEnglish ? 'Browse channels' : 'Channels durchsuchen';
  String get browsePlaylists =>
      isEnglish ? 'Browse playlists' : 'Playlists durchsuchen';
  String get browseSongPlaylists =>
      isEnglish ? 'Browse song playlists' : 'Song-Playlists durchsuchen';
  String get songSearchPrompt => isEnglish
      ? 'Search for songs in the YouTube Music catalog.'
      : 'Suche nach Songs aus dem YouTube-Music-Katalog.';
  String get videoSearchPrompt => isEnglish
      ? 'Enter a search term above to find videos.'
      : 'Gib oben einen Suchbegriff ein, um Videos zu finden.';
  String get artistSearchPrompt => isEnglish
      ? 'Search the YouTube Music catalog for an artist.'
      : 'Suche im YouTube-Music-Katalog nach einem Künstler.';
  String get channelSearchPrompt => isEnglish
      ? 'Search for a channel name and open its newest videos.'
      : 'Suche nach einem Channel-Namen und öffne seine neuesten Videos.';
  String get artistSearchAbove => isEnglish
      ? 'Search for an artist above.'
      : 'Suche oben nach einem Künstler.';
  String get channelSearchAbove => isEnglish
      ? 'Search for a channel name above.'
      : 'Suche oben nach einem Channel-Namen.';
  String get songPlaylistSearchAbove => isEnglish
      ? 'Search for a song playlist above.'
      : 'Suche oben nach einer Song-Playlist.';
  String get playlistSearchAbove => isEnglish
      ? 'Search for a playlist above.'
      : 'Suche oben nach einer Playlist.';
  String get noArtistsFound =>
      isEnglish ? 'No artists found.' : 'Keine Künstler gefunden.';
  String get noChannelsFound =>
      isEnglish ? 'No channels found.' : 'Keine Channels gefunden.';
  String get noPlaylistsFound =>
      isEnglish ? 'No playlists found.' : 'Keine Playlists gefunden.';
  String get musicPlaylistSearchPrompt => isEnglish
      ? 'Search the YouTube Music catalog for song playlists.'
      : 'Suche im YouTube-Music-Katalog nach Song-Playlists.';
  String get playlistSearchPrompt => isEnglish
      ? 'Search for a playlist and open its first items.'
      : 'Suche nach einer Playlist und öffne ihre ersten Inhalte.';
  String noCategoryFound(String category) =>
      isEnglish ? 'No $category found.' : 'Keine $category gefunden.';
  String get tryAnotherSearchTerm => isEnglish
      ? 'Try a different search term.'
      : 'Versuche es mit einem anderen Suchbegriff.';
  String searchCategoryPrompt(String category) => isEnglish
      ? 'Enter a search term to find $category.'
      : 'Gib einen Suchbegriff ein, um $category zu finden.';

  String get hotMusicUnsupported => isEnglish
      ? 'Hot Music is not available on this platform yet.'
      : 'Hot Music ist auf dieser Plattform noch nicht verfügbar.';
  String get noCategories =>
      isEnglish ? 'No categories available.' : 'Keine Kategorien verfügbar.';
  String noItems(String label) =>
      isEnglish ? 'No $label available.' : 'Keine $label verfügbar.';
  String get noSongs =>
      isEnglish ? 'No songs available.' : 'Keine Songs verfügbar.';
  String get noNewReleases => isEnglish
      ? 'No new releases available.'
      : 'Keine Neuerscheinungen verfügbar.';
  String get noVideoCharts => isEnglish
      ? 'No video charts available for this country.'
      : 'Keine Video-Charts für dieses Land verfügbar.';
  String get noArtistCharts => isEnglish
      ? 'No artist charts available.'
      : 'Keine Künstler-Charts verfügbar.';
  String noCategoryPlaylists(String title) => isEnglish
      ? 'No playlists available for $title.'
      : 'Keine Playlists für $title verfügbar.';
  String get backToGenres => isEnglish ? 'Back to genres' : 'Zurück zu Genres';
  String chartCountry(String country) =>
      isEnglish ? 'Chart country: $country' : 'Chart-Land: $country';
  String countryLabel(String code) => switch (code) {
    'DE' => isEnglish ? 'Germany (DE)' : 'Deutschland (DE)',
    'AT' => isEnglish ? 'Austria (AT)' : 'Österreich (AT)',
    'CH' => isEnglish ? 'Switzerland (CH)' : 'Schweiz (CH)',
    'US' => isEnglish ? 'United States (US)' : 'USA (US)',
    'GB' => isEnglish ? 'United Kingdom (GB)' : 'Großbritannien (GB)',
    'ZZ' => isEnglish ? 'Global (ZZ)' : 'Global (ZZ)',
    _ => code,
  };

  String get autoplay => 'Auto-Play';
  String get enableShuffle =>
      isEnglish ? 'Enable shuffle' : 'Zufallswiedergabe aktivieren';
  String get disableShuffle =>
      isEnglish ? 'Disable shuffle' : 'Zufallswiedergabe deaktivieren';
  String get like => isEnglish ? 'Like' : 'Gefällt mir';
  String get dislike => isEnglish ? 'Dislike' : 'Gefällt mir nicht';
  String get videoQuality => isEnglish ? 'Video quality' : 'Videoqualität';
  String get subtitles => isEnglish ? 'Subtitles' : 'Untertitel';
  String get unmute => isEnglish ? 'Unmute' : 'Ton an';
  String get mute => isEnglish ? 'Mute' : 'Stumm';
  String get videoLoadFailed => isEnglish
      ? 'The video could not be loaded.'
      : 'Das Video konnte nicht geladen werden.';
  String get videoPlaybackFailed => isEnglish
      ? 'The video could not be played.'
      : 'Das Video konnte nicht abgespielt werden.';
  String get videoLoadTimeout => isEnglish
      ? 'Loading the video took too long.'
      : 'Das Laden des Videos hat zu lange gedauert.';
  String get nextQueueLoadTimeout => isEnglish
      ? 'Loading the next queued item took too long.'
      : 'Das Laden des nächsten Queue-Mediums hat zu lange gedauert.';
  String get nextQueuePlaybackFailed => isEnglish
      ? 'The next queued item could not be played.'
      : 'Das nächste Queue-Medium konnte nicht abgespielt werden.';
  String nextQueueStartFailed(Object error) => isEnglish
      ? 'The next queued item could not be started: $error'
      : 'Das nächste Queue-Medium konnte nicht gestartet werden: $error';
  String playbackFallback(String initial, String source, String selected) =>
      isEnglish
      ? '$initial could not be loaded. Playback is using $source at $selected.'
      : '$initial konnte nicht geladen werden. Wiedergabe läuft über $source in $selected.';
  String get playbackStoppedOnExit => isEnglish
      ? 'Playback was stopped when the app closed.'
      : 'Die Wiedergabe wurde beim Beenden der App gestoppt.';
  String get searchFailed =>
      isEnglish ? 'The search failed.' : 'Die Suche ist fehlgeschlagen.';
  String categorySearchFailed(String category) => isEnglish
      ? '$category search failed.'
      : 'Die $category-Suche ist fehlgeschlagen.';
  String qualityLoadFailed(String quality) => isEnglish
      ? '$quality could not be loaded.'
      : '$quality konnte nicht geladen werden.';
  String get details => isEnglish ? 'Details' : 'Details';
  String get technicalDetails =>
      isEnglish ? 'Technical details' : 'Technische Details';
  String get technicalDetailsCopied =>
      isEnglish ? 'Technical details copied.' : 'Technische Details kopiert.';
  String pipStartFailed(String message) => isEnglish
      ? 'Picture in picture could not be started: $message'
      : 'Bild-in-Bild konnte nicht gestartet werden: $message';
  String get pipHlsAndFallbackFailed => isEnglish
      ? 'Neither the HLS stream nor the progressive fallback became ready for picture in picture.'
      : 'Weder der HLS-Stream noch der progressive Fallback wurde für Bild-in-Bild bereit.';
  String get pipNativeStreamNotReady => isEnglish
      ? 'The native stream did not become ready for picture in picture.'
      : 'Der native Stream wurde nicht rechtzeitig für Bild-in-Bild bereit.';
  String get nextQueuePipStreamUnavailable => isEnglish
      ? 'No iOS picture-in-picture stream is available for the next queued item.'
      : 'Für das nächste Queue-Medium ist kein iOS-PiP-Stream verfügbar.';
  String get nextQueuePipHandoffFailed => isEnglish
      ? 'The next queued item could not be handed over to iOS picture in picture.'
      : 'Das nächste Queue-Medium konnte nicht an iOS-PiP übergeben werden.';

  String releaseType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'veröffentlichung' || normalized == 'release') {
      return isEnglish ? 'Release' : 'Veröffentlichung';
    }
    return value;
  }

  String translateKnownMessage(String message) {
    if (!isEnglish) {
      return message;
    }
    const exact = <String, String>{
      'Bitte gib einen Namen ein.': 'Please enter a name.',
      'Bitte gib einen Profilnamen ein.': 'Please enter a profile name.',
      'Dieser Profilname ist auf dem Gerät bereits vergeben.':
          'This profile name is already in use on this device.',
      'Bitte gib einen Namen für die Playlist ein.':
          'Please enter a name for the playlist.',
      'Eine Playlist mit diesem Namen existiert bereits.':
          'A playlist with this name already exists.',
      'In diesem Profil gibt es bereits eine Playlist mit diesem Namen.':
          'A playlist with this name already exists in this profile.',
      'Die Suche hat länger als 10 Sekunden gedauert. Bitte versuche es erneut.':
          'The search took longer than 10 seconds. Please try again.',
      'Bei der Suche ist ein unerwarteter Fehler aufgetreten.':
          'An unexpected error occurred during the search.',
      'Die Playlist konnte nicht vollständig geladen werden.':
          'The playlist could not be loaded completely.',
      'Das Laden der Playlist hat zu lange gedauert. Bitte versuche es erneut.':
          'Loading the playlist took too long. Please try again.',
      'Die Playlist enthält keine Inhalte.': 'The playlist contains no items.',
      'Die key-freie YouTube-Suche ist momentan nicht verfügbar. Bitte versuche es später erneut.':
          'The key-free YouTube search is currently unavailable. Please try again later.',
      'Die YouTube-Music-Suche ist momentan nicht verfügbar. Bitte versuche es später erneut.':
          'YouTube Music search is currently unavailable. Please try again later.',
      'Die Channel-Suche ist momentan nicht verfügbar. Bitte versuche es später erneut.':
          'Channel search is currently unavailable. Please try again later.',
      'Die Playlist-Suche ist momentan nicht verfügbar. Bitte versuche es später erneut.':
          'Playlist search is currently unavailable. Please try again later.',
      'Channel- und Playlist-Suche ist auf dieser Plattform nicht verfügbar.':
          'Channel and playlist search are not available on this platform.',
      'Die erweiterte YouTube-Music-Suche ist auf dieser Plattform nicht verfügbar.':
          'Extended YouTube Music search is not available on this platform.',
      'Die YouTube-Suche ist momentan nicht verfügbar.':
          'YouTube search is currently unavailable.',
      'Die YouTube-Music-Suche ist auf dieser Plattform nicht verfügbar.':
          'YouTube Music search is not available on this platform.',
      'Hot Music ist auf dieser Plattform noch nicht verfügbar.':
          'Hot Music is not available on this platform yet.',
      'Hot Music konnte nicht geladen werden.':
          'Hot Music could not be loaded.',
      'Die Charts konnten nicht geladen werden.':
          'The charts could not be loaded.',
      'Die Playlists konnten nicht geladen werden.':
          'The playlists could not be loaded.',
      'YouTube Music Entdecken ist momentan nicht verfügbar.':
          'YouTube Music Explore is currently unavailable.',
      'Die YouTube-Music-Charts sind momentan nicht verfügbar.':
          'YouTube Music charts are currently unavailable.',
      'Genres und Stimmungen konnten nicht geladen werden.':
          'Genres and moods could not be loaded.',
      'Die Playlists dieser Kategorie konnten nicht geladen werden.':
          'The playlists in this category could not be loaded.',
      'Die Songs konnten nicht aus YouTube Music geladen werden.':
          'The songs could not be loaded from YouTube Music.',
      'Die YouTube-Music-Katalogsuche ist momentan nicht verfügbar. Bitte versuche es später erneut.':
          'YouTube Music catalog search is currently unavailable. Please try again later.',
      'Die YouTube-Music-Suche ist auf dieser Plattform noch nicht verfügbar.':
          'YouTube Music search is not available on this platform yet.',
      'Hot Music ist mit dieser Music-Datenquelle nicht verfügbar.':
          'Hot Music is not available with this music data source.',
      'Ungültige Ergebnisseite.': 'Invalid results page.',
      'Ungültige Music-Ergebnisseite.': 'Invalid music results page.',
      'Ungültige Channel-ID.': 'Invalid channel ID.',
      'Die Videos des Channels konnten nicht geladen werden.':
          'The channel videos could not be loaded.',
      'Die Inhalte der Playlist konnten nicht geladen werden.':
          'The playlist contents could not be loaded.',
      'YouTube konnte nicht erreicht werden. Prüfe deine Internetverbindung.':
          'YouTube could not be reached. Check your internet connection.',
      'YouTube hat eine ungültige Antwort geliefert.':
          'YouTube returned an invalid response.',
      'Die Playlist lieferte ungültige Seitendaten und konnte nicht vollständig geladen werden.':
          'The playlist returned invalid page data and could not be loaded completely.',
      'Für dieses Video wurde kein abspielbarer Stream gefunden.':
          'No playable stream was found for this video.',
      'Dieses Video ist nur für Kanalmitglieder verfügbar.':
          'This video is available to channel members only.',
      'Das Video konnte nicht geladen werden. Bitte versuche es erneut.':
          'The video could not be loaded. Please try again.',
      'Der Video-Dienst wurde bereits geschlossen.':
          'The video service has already been closed.',
      'Der Live-Stream konnte nicht geladen werden.':
          'The live stream could not be loaded.',
      'Das nächste Queue-Medium konnte nicht abgespielt werden.':
          'The next queued item could not be played.',
      'Das Laden des nächsten Queue-Mediums hat zu lange gedauert.':
          'Loading the next queued item took too long.',
    };
    final translated = exact[message];
    if (translated != null) {
      return translated;
    }
    if (message.startsWith('YouTube-Suche fehlgeschlagen')) {
      return message.replaceFirst(
        'YouTube-Suche fehlgeschlagen',
        'YouTube search failed',
      );
    }
    if (message.startsWith('Es ist noch kein YouTube-API-Key konfiguriert.')) {
      return message.replaceFirst(
        'Es ist noch kein YouTube-API-Key konfiguriert.',
        'No YouTube API key has been configured yet.',
      );
    }
    return message;
  }
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (item) => item.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
