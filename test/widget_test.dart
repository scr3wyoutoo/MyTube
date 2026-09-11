import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/main.dart';
import 'package:flutter_browser_app/models/app_tutorial_stage.dart';
import 'package:flutter_browser_app/models/hot_music.dart';
import 'package:flutter_browser_app/models/user_profile.dart';
import 'package:flutter_browser_app/models/video_playback.dart';
import 'package:flutter_browser_app/models/youtube_catalog_item.dart';
import 'package:flutter_browser_app/models/youtube_search_category.dart';
import 'package:flutter_browser_app/models/youtube_search_sort.dart';
import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/screens/youtube_search_page.dart';
import 'package:flutter_browser_app/services/app_log.dart';
import 'package:flutter_browser_app/services/app_log_storage_stub.dart';
import 'package:flutter_browser_app/services/profile_controller.dart';
import 'package:flutter_browser_app/services/video_playback_service.dart';
import 'package:flutter_browser_app/services/youtube_catalog_repository.dart';
import 'package:flutter_browser_app/services/youtube_music_catalog_repository.dart';
import 'package:flutter_browser_app/services/youtube_music_discovery_repository.dart';
import 'package:flutter_browser_app/services/youtube_search_repository.dart';
import 'package:flutter_browser_app/services/youtube_video_details_repository.dart';
import 'package:flutter_browser_app/widgets/video_result_card.dart';
import 'package:flutter_browser_app/widgets/media_search_category_bar.dart';
import 'package:flutter_browser_app/widgets/tutorial_coach_overlay.dart';

void main() {
  testWidgets('wechselt die App-Sprache mit dem aktiven Profil', (
    tester,
  ) async {
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        profileController: profiles,
      ),
    );

    expect(find.text('Suchbegriff eingeben'), findsOneWidget);
    expect(
      find.text('Gib oben einen Suchbegriff ein, um Videos zu finden.'),
      findsOneWidget,
    );

    await profiles.setLanguage(ProfileLanguage.english);
    await tester.pumpAndSettle();

    expect(find.text('Enter a search term'), findsOneWidget);
    expect(
      find.text('Enter a search term above to find videos.'),
      findsOneWidget,
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
  });

  testWidgets('zeigt die einfache Suchoberfläche', (tester) async {
    await tester.pumpWidget(
      BrowserApp(searchRepository: _FakeSearchRepository()),
    );

    expect(find.text('Video Browser'), findsNothing);
    expect(find.text('YouTube search'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
    expect(find.byKey(const Key('search-source-selector')), findsOneWidget);
    expect(find.byKey(const Key('search-source-icon')), findsOneWidget);
    expect(
      find.byKey(const Key('search-source-dropdown-indicator')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('search-clear-button')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-button')),
        matching: find.byIcon(Icons.search),
      ),
      findsOneWidget,
    );
    expect(find.text('Browse YouTube'), findsOneWidget);
    final sectionNavigation = tester.widget<NavigationBar>(
      find.byKey(const Key('main-section-navigation')),
    );
    expect(sectionNavigation.height, 52);
    expect(
      sectionNavigation.labelBehavior,
      NavigationDestinationLabelBehavior.alwaysHide,
    );
    expect(
      tester.getSize(find.byKey(const Key('main-section-navigation'))).height,
      52,
    );
    expect(find.byKey(const Key('main-section-hot-music')), findsOneWidget);
    final hotMusicDestination = tester.widget<NavigationDestination>(
      find.byKey(const Key('main-section-hot-music')),
    );
    expect(hotMusicDestination.icon, isA<Icon>());
    expect((hotMusicDestination.icon as Icon).icon, Icons.music_note_outlined);
    expect(hotMusicDestination.selectedIcon, isA<Icon>());
    expect((hotMusicDestination.selectedIcon! as Icon).icon, Icons.music_note);
    expect(find.byKey(const Key('main-section-profile')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.pump();
    expect(find.byKey(const Key('search-clear-button')), findsOneWidget);

    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byKey(const Key('search-clear-button')));
    await tester.pump();
    final searchField = tester.widget<TextField>(
      find.byKey(const Key('search-field')),
    );
    expect(searchField.controller?.text, isEmpty);
    expect(
      searchField.controller?.selection,
      const TextSelection.collapsed(offset: 0),
    );
    expect(searchField.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const Key('search-clear-button')), findsNothing);
  });

  testWidgets('öffnet Hot-Music-Playlistinhalte im Music-Songs-Bereich', (
    tester,
  ) async {
    final musicRepository = _FakeMusicSearchRepository();
    YouTubeVideo? startedVideo;
    List<YouTubeVideo>? startedQueue;
    String? startedQuery;
    YouTubeSearchRepository? playerRepository;
    await tester.pumpWidget(
      MaterialApp(
        home: YouTubeSearchPage(
          searchRepository: _FakeSearchRepository(),
          musicSearchRepository: musicRepository,
          videoPageBuilder:
              (
                video,
                results,
                query,
                searchRepository, {
                required initiallyPaused,
              }) {
                startedVideo = video;
                startedQueue = results;
                startedQuery = query;
                playerRepository = searchRepository;
                return Scaffold(body: Text('Auto-Start ${video.title}'));
              },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('main-section-hot-music')));
    await tester.pumpAndSettle();
    expect(find.text('Hot Music'), findsAtLeastNWidgets(1));
    expect(find.text('Hot Trending'), findsOneWidget);

    await tester.tap(find.byKey(const Key('main-hot-music-section-explore')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('main-hot-music-explore-filter-newReleases')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hot Artist'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-type-badge-OLAK-hot-album')),
      findsOneWidget,
    );
    await tester.tap(find.text('Hot Album'));
    await tester.pumpAndSettle();

    expect(musicRepository.openedPlaylistIds, ['OLAK-hot-album']);
    expect(find.text('Auto-Start Playlist-Song'), findsOneWidget);
    expect(startedVideo?.id, 'playlist-song');
    expect(startedVideo?.isMusic, isTrue);
    expect(startedVideo?.isMusicVideo, isFalse);
    expect(startedVideo?.hasVideo, isFalse);
    expect(startedQueue?.map((video) => video.id), ['playlist-song']);
    expect(startedQuery, 'Hot Album');
    expect(playerRepository, same(musicRepository));
  });

  testWidgets('klassifiziert Inhalte der Music-Video-Charts als Video', (
    tester,
  ) async {
    final musicRepository = _FakeMusicSearchRepository();
    YouTubeVideo? startedVideo;
    List<YouTubeVideo>? startedQueue;
    await tester.pumpWidget(
      MaterialApp(
        home: YouTubeSearchPage(
          searchRepository: _FakeSearchRepository(),
          musicSearchRepository: musicRepository,
          videoPageBuilder:
              (
                video,
                results,
                query,
                searchRepository, {
                required initiallyPaused,
              }) {
                startedVideo = video;
                startedQueue = results;
                return Scaffold(body: Text('Auto-Start ${video.title}'));
              },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('main-section-hot-music')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('main-hot-music-section-charts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hot Video Charts'));
    await tester.pumpAndSettle();

    expect(musicRepository.openedPlaylistIds, ['VL-hot-video-charts']);
    expect(find.text('Auto-Start Playlist-Song'), findsOneWidget);
    expect(startedVideo?.isMusic, isTrue);
    expect(startedVideo?.isMusicVideo, isTrue);
    expect(startedVideo?.hasVideo, isTrue);
    expect(startedQueue?.single.isMusicVideo, isTrue);
  });

  testWidgets('startet aus einem Hot-Music-Künstler den ersten Song', (
    tester,
  ) async {
    final musicRepository = _FakeMusicSearchRepository();
    YouTubeVideo? startedVideo;
    await tester.pumpWidget(
      MaterialApp(
        home: YouTubeSearchPage(
          searchRepository: _FakeSearchRepository(),
          musicSearchRepository: musicRepository,
          videoPageBuilder:
              (
                video,
                results,
                query,
                searchRepository, {
                required initiallyPaused,
              }) {
                startedVideo = video;
                return Scaffold(body: Text('Auto-Start ${video.title}'));
              },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('main-section-hot-music')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('main-hot-music-section-charts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('main-hot-music-section-charts')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('main-hot-music-charts-filter-artists')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hot Chart Artist'));
    await tester.pumpAndSettle();

    expect(musicRepository.openedArtistIds, ['hot-chart-artist']);
    expect(find.text('Auto-Start Künstler-Song'), findsOneWidget);
    expect(startedVideo?.id, 'artist-song');
    expect(startedVideo?.isMusic, isTrue);
  });

  testWidgets('filtert, startet und löscht die Profil-Suchhistorie', (
    tester,
  ) async {
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await profiles.recordSearchQuery('Spät bei ARTE');
    await profiles.recordSearchQuery('Flutter Tutorial');
    await profiles.recordSearchQuery('Arte Doku');
    final repository = _FakeSearchRepository();
    await tester.pumpWidget(
      BrowserApp(searchRepository: repository, profileController: profiles),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'a');
    await tester.pump();
    expect(find.byKey(const Key('search-history-dropdown')), findsNothing);

    await tester.enterText(find.byKey(const Key('search-field')), 'ar');
    await tester.pump();
    expect(find.byKey(const Key('search-history-dropdown')), findsOneWidget);
    expect(find.text('Arte Doku'), findsOneWidget);
    expect(find.text('Spät bei ARTE'), findsOneWidget);
    expect(find.text('Flutter Tutorial'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('search-history-delete-arte doku')),
    );
    await tester.pumpAndSettle();
    expect(profiles.activeProfile!.searchHistory, isNot(contains('Arte Doku')));
    expect(find.text('Arte Doku'), findsNothing);
    expect(find.text('Spät bei ARTE'), findsOneWidget);

    await tester.tap(find.text('Spät bei ARTE'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('search-field')))
          .controller
          ?.text,
      'Spät bei ARTE',
    );
    expect(repository.queries, everyElement('Spät bei ARTE'));
    expect(profiles.activeProfile!.searchHistory.first, 'Spät bei ARTE');
    expect(find.byKey(const Key('search-history-dropdown')), findsNothing);
  });

  testWidgets('nutzt Relevanz und blendet die Sortiersteuerung aus', (
    tester,
  ) async {
    final repository = _FakeSearchRepository();
    final catalog = _FakeCatalogRepository();
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: repository,
        catalogRepository: catalog,
        profileController: profiles,
      ),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    expect(repository.sorts, [
      YouTubeSearchSort.relevance,
      YouTubeSearchSort.relevance,
    ]);

    await tester.tap(find.byKey(const Key('search-category-videos')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('search-sort-videos-uploadDate')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('search-category-videos')),
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
      findsNothing,
    );
    expect(repository.sorts, [
      YouTubeSearchSort.relevance,
      YouTubeSearchSort.relevance,
    ]);
    expect(
      profiles.activeProfile?.videoSearchSort,
      YouTubeSearchSort.relevance,
    );

    await tester.tap(find.byKey(const Key('search-category-playlists')));
    await tester.pump();
    expect(find.byKey(const Key('search-sort-playlists-rating')), findsNothing);
    await tester.enterText(find.byKey(const Key('search-field')), 'Training');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    expect(catalog.playlistSorts, [YouTubeSearchSort.relevance]);

    await tester.tap(find.byKey(const Key('search-category-playlists')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('search-sort-playlists-viewCount')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('search-category-playlists')),
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
      findsNothing,
    );
    expect(catalog.playlistSorts, [YouTubeSearchSort.relevance]);
    expect(
      profiles.activeProfile?.playlistSearchSort,
      YouTubeSearchSort.relevance,
    );
  });

  testWidgets('bietet für Channel-Ergebnisse keine änderbare Sortierung an', (
    tester,
  ) async {
    final catalog = _FakeCatalogRepository();
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        catalogRepository: catalog,
        profileController: profiles,
      ),
    );

    await tester.tap(find.byKey(const Key('search-category-channels')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('search-category-channels')));
    await tester.pump();
    expect(find.byKey(const Key('search-sort-channels-rating')), findsNothing);

    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flutter Channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-category-videos')));
    await tester.pump();
    expect(find.byKey(const Key('search-sort-videos-rating')), findsNothing);
    expect(
      profiles.activeProfile?.videoSearchSort,
      YouTubeSearchSort.relevance,
    );
  });

  testWidgets('kennzeichnet Live-Videos direkt auf dem Thumbnail', (
    tester,
  ) async {
    const video = YouTubeVideo(
      id: 'live-result',
      title: 'Live-Übertragung',
      description: '',
      thumbnailUrl: '',
      isLive: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoResultCard(video: video, onTap: () {}),
        ),
      ),
    );

    expect(find.byKey(const Key('video-live-tag-live-result')), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('fordert bei leerer Suche einen Suchbegriff an', (tester) async {
    await tester.pumpWidget(
      BrowserApp(searchRepository: _FakeSearchRepository()),
    );

    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump();

    expect(find.text('Please enter a search term.'), findsOneWidget);
  });

  testWidgets('beendet eine hängende Suche nach zehn Sekunden', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: YouTubeSearchPage(searchRepository: _HangingSearchRepository()),
      ),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'Timeout');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text(
        'Die Suche hat länger als 10 Sekunden gedauert. '
        'Bitte versuche es erneut.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('beendet den Ladezustand auch bei einem Parser-Error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: YouTubeSearchPage(searchRepository: _ErrorSearchRepository()),
      ),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'Arte');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Bei der Suche ist ein unerwarteter Fehler aufgetreten.'),
      findsOneWidget,
    );
  });

  testWidgets('erstellt und öffnet ein lokales Profil', (tester) async {
    final profiles = ProfileController.inMemory();
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        profileController: profiles,
      ),
    );

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Your personal area'), findsOneWidget);

    await tester.tap(find.byKey(const Key('first-profile-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-language-field')), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-language-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-name-field')), 'Alex');
    await tester.tap(find.byKey(const Key('create-profile-button')));
    await tester.pumpAndSettle();

    expect(profiles.activeProfile?.name, 'Alex');
    expect(profiles.activeProfile?.language, ProfileLanguage.german);
    expect(find.byKey(const Key('profile-selector')), findsOneWidget);
    expect(find.text('Favoriten'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(
      tester.getCenter(find.widgetWithText(Tab, 'Playlists')).dx,
      lessThan(tester.getCenter(find.widgetWithText(Tab, 'Favoriten')).dx),
    );
    expect(
      tester.getCenter(find.widgetWithText(Tab, 'Favoriten')).dx,
      lessThan(tester.getCenter(find.widgetWithText(Tab, 'Channels')).dx),
    );
    expect(find.byKey(const Key('profile-language-selector')), findsNothing);
    expect(find.byKey(const Key('delete-profile-button')), findsNothing);
    expect(find.byKey(const Key('profile-avatar-menu')), findsOneWidget);
    expect(find.byKey(const Key('add-profile-button')), findsOneWidget);
    final addProfileRight = tester
        .getTopRight(find.byKey(const Key('add-profile-button')))
        .dx;
    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(logicalWidth - addProfileRight, 16);

    await tester.tap(find.byKey(const Key('profile-avatar-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Sprache'), findsOneWidget);
    expect(find.text('Tutorial wiederholen'), findsOneWidget);
    expect(find.text('Logdatei'), findsOneWidget);
    expect(find.text('Profil löschen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-profile-menu-item')));
    await tester.pumpAndSettle();
    expect(find.text('Profil löschen?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-profile-button')));
    await tester.pumpAndSettle();

    expect(profiles.profiles, isEmpty);
    expect(find.text('Your personal area'), findsOneWidget);
  });

  testWidgets('zeigt die lokale Logdatei und startet beim neuesten Eintrag', (
    tester,
  ) async {
    final previousLogger = AppLog.instance;
    addTearDown(() => AppLog.replaceForTesting(previousLogger));
    final storage = MemoryAppLogStorage();
    await storage.append(
      List<String>.generate(
        80,
        (index) => '2026-09-09 INFO test.viewer.entry index=$index ${'x' * 80}',
      ).join('\n'),
      maxBytes: 2 * 1024 * 1024,
    );
    final logger = AppLogService.forTesting(
      storage: storage,
      sessionId: 'widget-test',
    );
    AppLog.replaceForTesting(logger);

    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await profiles.setLanguage(ProfileLanguage.german);
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        profileController: profiles,
      ),
    );
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-avatar-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-file-menu-item')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('log-file-contents')), findsOneWidget);
    expect(find.byKey(const Key('clear-log-file-button')), findsOneWidget);
    expect(find.byKey(const Key('copy-log-file-button')), findsOneWidget);
    expect(find.byKey(const Key('close-log-file-button')), findsOneWidget);
    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('log-file-scroll-view')),
    );
    expect(
      scrollView.controller!.offset,
      scrollView.controller!.position.maxScrollExtent,
    );

    await tester.tap(find.byKey(const Key('clear-log-file-button')));
    await tester.pumpAndSettle();
    expect(
      find.text('Die Logdatei enthält noch keine Einträge.'),
      findsOneWidget,
    );
    expect(await logger.read(), isEmpty);
  });

  testWidgets('startet das gesamte Tutorial manuell aus dem Profilmenü neu', (
    tester,
  ) async {
    final profiles = await ProfileController.load(
      storage: MemoryProfileStorage(),
    );
    await profiles.createProfile('Alex');
    await profiles.completeAllTutorialStages();
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        musicSearchRepository: _FakeMusicSearchRepository(),
        profileController: profiles,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tutorial-coach-overlay')), findsNothing);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-avatar-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restart-tutorial-menu-item')));
    await tester.pumpAndSettle();

    expect(
      AppTutorialStage.values.every(
        (stage) => profiles.shouldShowTutorialStage(stage),
      ),
      isTrue,
    );
    expect(find.text('Deine Playlists'), findsOneWidget);
    expect(
      find.text('Profil-Tutorial (1/4) · Schritt 2 von 6'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tutorial-coach-overlay')), findsOneWidget);
  });

  testWidgets('überspringt vom Profil-Coach aus alle Tutorial-Abschnitte', (
    tester,
  ) async {
    final profiles = await ProfileController.load(
      storage: MemoryProfileStorage(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: YouTubeSearchPage(
          searchRepository: _FakeSearchRepository(),
          musicSearchRepository: _FakeMusicSearchRepository(),
          profileController: profiles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tutorial-skip-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tutorial-coach-overlay')), findsNothing);
    expect(
      AppTutorialStage.values.every(profiles.isTutorialStageCompleted),
      isTrue,
    );
  });

  testWidgets(
    'verlangt ohne Profil die echte Profilerstellung zum Fortsetzen',
    (tester) async {
      final profiles = await ProfileController.load(
        storage: MemoryProfileStorage(),
      );
      await tester.pumpWidget(
        BrowserApp(
          searchRepository: _FakeSearchRepository(),
          musicSearchRepository: _FakeMusicSearchRepository(),
          profileController: profiles,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('en'),
      );
      expect(find.text('Create your first profile'), findsOneWidget);
      expect(find.byKey(const Key('first-profile-button')), findsOneWidget);
      expect(find.byKey(const Key('tutorial-next-button')), findsNothing);
      expect(find.byKey(const Key('tutorial-skip-button')), findsOneWidget);
      expect(
        tester
            .widget<TutorialCoachOverlay>(find.byType(TutorialCoachOverlay))
            .allowTargetInteraction,
        isTrue,
      );
      expect(
        tester
            .widget<PopScope>(
              find.byKey(const Key('main-tutorial-navigation-lock')),
            )
            .canPop,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('first-profile-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-name-field')),
        'Alex',
      );
      await tester.tap(find.byKey(const Key('create-profile-button')));
      await tester.pumpAndSettle();

      expect(profiles.activeProfile?.name, 'Alex');
      expect(profiles.activeProfile?.language, ProfileLanguage.english);
      expect(find.text('Your playlists'), findsOneWidget);
      expect(find.byKey(const Key('tutorial-next-button')), findsOneWidget);
      expect(
        tester
            .widget<TutorialCoachOverlay>(find.byType(TutorialCoachOverlay))
            .allowTargetInteraction,
        isFalse,
      );
    },
  );

  testWidgets(
    'führt durch Profil, Suche und Hot Music bis zum pausierten Song',
    (tester) async {
      final storage = MemoryProfileStorage();
      final profiles = await ProfileController.load(storage: storage);
      await profiles.createProfile('Alex');
      final repository = _FakeSearchRepository();
      final musicRepository = _FakeMusicSearchRepository();
      YouTubeVideo? tutorialSong;
      List<YouTubeVideo>? tutorialQueue;
      bool? tutorialSongInitiallyPaused;
      await tester.pumpWidget(
        MaterialApp(
          home: YouTubeSearchPage(
            searchRepository: repository,
            musicSearchRepository: musicRepository,
            profileController: profiles,
            videoPageBuilder:
                (
                  video,
                  results,
                  query,
                  searchRepository, {
                  required initiallyPaused,
                }) {
                  tutorialSong = video;
                  tutorialQueue = results;
                  tutorialSongInitiallyPaused = initiallyPaused;
                  return Scaffold(body: Text('Tutorial-Player ${video.title}'));
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mein Profil'), findsWidgets);
      expect(find.text('Deine Playlists'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Deine Favoriten'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Gespeicherte Channels und Künstler'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Weiteres Profil hinzufügen'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Sprache und Profilverwaltung'), findsOneWidget);

      expect(find.widgetWithText(FilledButton, 'Nächstes'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Nächstes'));
      await tester.pumpAndSettle();
      expect(
        profiles.isTutorialStageCompleted(AppTutorialStage.profile),
        isTrue,
      );
      expect(find.text('YouTube oder YouTube Music'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Suche starten'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Videos und Songs'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Channels und Künstler'), findsOneWidget);
      expect(
        tester
            .widget<MediaSearchCategoryBar>(find.byType(MediaSearchCategoryBar))
            .selected,
        YouTubeSearchCategory.channels,
      );

      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Suche-Tutorial (2/4) · Schritt 5 von 5'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<MediaSearchCategoryBar>(find.byType(MediaSearchCategoryBar))
            .selected,
        YouTubeSearchCategory.playlists,
      );
      expect(find.widgetWithText(FilledButton, 'Nächstes'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Nächstes'));
      await tester.pumpAndSettle();
      expect(
        profiles.isTutorialStageCompleted(AppTutorialStage.search),
        isTrue,
      );
      expect(repository.queries, isEmpty);

      expect(find.text('Musik entdecken'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();

      expect(find.text('Musik-Charts'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();

      expect(find.text('Stimmungen und Genres'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pump();
      expect(find.byKey(const Key('tutorial-next-button')), findsNothing);
      await tester.pumpAndSettle();

      expect(find.text('Als Favorit speichern'), findsOneWidget);
      expect(find.byKey(const Key('tutorial-highlight-0')), findsOneWidget);
      expect(
        find.byKey(const Key('search-favorite-hot-trending')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Zu einer Playlist hinzufügen'), findsOneWidget);
      expect(
        find.byKey(const Key('search-add-playlist-hot-trending')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Song-Informationen'), findsOneWidget);
      expect(find.byKey(const Key('search-info-hot-trending')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Nächstes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Tutorial-Player Hot Trending'), findsOneWidget);
      expect(tutorialSong?.id, 'hot-trending');
      expect(tutorialQueue?.single.id, 'hot-trending');
      expect(tutorialSongInitiallyPaused, isTrue);
      expect(
        profiles.isTutorialStageCompleted(AppTutorialStage.hotMusic),
        isTrue,
      );
    },
  );

  testWidgets('verwendet die Sprache des aktiven Profils für die Suche', (
    tester,
  ) async {
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    final repository = _FakeSearchRepository();
    await tester.pumpWidget(
      BrowserApp(searchRepository: repository, profileController: profiles),
    );

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-avatar-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-language-menu-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-language-en')));
    await tester.pumpAndSettle();
    expect(profiles.activeProfile?.language, ProfileLanguage.english);

    await tester.tap(find.byKey(const Key('main-section-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();

    expect(repository.languageCodes, everyElement('en'));
  });

  testWidgets('sortiert Playlist-Titel über den Drag-Griff neu', (
    tester,
  ) async {
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    final playlist = await profiles.createPlaylist('Sortierung');
    await profiles.addVideoToPlaylist(playlist.id, _playlistFirstVideo);
    await profiles.addVideoToPlaylist(playlist.id, _playlistSecondVideo);
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        profileController: profiles,
      ),
    );

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sortierung'));
    await tester.pumpAndSettle();

    final firstHandle = find.byKey(
      ValueKey('playlist-drag-${playlist.id}-${_playlistFirstVideo.id}'),
    );
    expect(firstHandle, findsOneWidget);
    final drag = await tester.startGesture(tester.getCenter(firstHandle));
    await tester.pump();
    await drag.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 500));
    await drag.up();
    await tester.pumpAndSettle();

    expect(
      profiles.activeProfile!.playlists.single.videos.map((video) => video.id),
      [_playlistSecondVideo.id, _playlistFirstVideo.id],
    );
  });

  testWidgets('benennt eine Playlist über ihr Drei-Punkte-Menü um', (
    tester,
  ) async {
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    final playlist = await profiles.createPlaylist('Alter Name');
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        profileController: profiles,
      ),
    );

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-menu-${playlist.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rename-playlist-menu-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-playlist-name-field')),
      'Neuer Name',
    );
    await tester.tap(find.byKey(const Key('rename-playlist-button')));
    await tester.pumpAndSettle();

    expect(profiles.activeProfile!.playlists.single.name, 'Neuer Name');
    expect(find.text('Neuer Name'), findsOneWidget);
  });

  testWidgets('hängt die nächste Ergebnisseite automatisch an', (tester) async {
    final repository = _FakeSearchRepository();
    await tester.pumpWidget(BrowserApp(searchRepository: repository));

    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();

    expect(repository.queries, ['Flutter', 'Flutter']);
    expect(repository.pageTokens, [null, 'next-page']);
    expect(find.text('Flutter Einführung'), findsOneWidget);
    expect(find.text('Eine Beschreibung zum ersten Video.'), findsOneWidget);
    expect(find.text('Flutter Fortsetzung'), findsOneWidget);
    expect(repository.languageCodes, everyElement('en'));
    expect(find.byTooltip('Next page'), findsNothing);
    expect(find.byTooltip('Previous page'), findsNothing);
    expect(find.text('- No more results -'), findsOneWidget);
  });

  testWidgets('zeigt beim verzögerten automatischen Nachladen den Ladezyklus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DelayedNextPageSearchRepository();
    await tester.pumpWidget(BrowserApp(searchRepository: repository));

    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    expect(repository.pageTokens, [null]);

    await tester.drag(
      find.byKey(const Key('video-results')),
      const Offset(0, -10000),
    );
    await tester.pump();
    await tester.pump();

    expect(repository.pageTokens, [null, 'delayed-next']);
    expect(find.byKey(const Key('search-videos-loading-more')), findsOneWidget);
    expect(find.byKey(const ValueKey('delayed-video-20')), findsOneWidget);

    repository.completeNextPage();
    await tester.pumpAndSettle();

    expect(find.text('Video 21'), findsOneWidget);
    expect(
      find.byKey(const Key('search-videos-no-more-results')),
      findsOneWidget,
    );
    expect(find.text('- No more results -'), findsOneWidget);
  });

  testWidgets('begrenzt eine fortlaufende Suche auf 100 Treffer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _HundredResultSearchRepository();
    await tester.pumpWidget(BrowserApp(searchRepository: repository));

    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();

    for (var page = 2; page <= 5; page++) {
      await tester.drag(
        find.byKey(const Key('video-results')),
        const Offset(0, -10000),
      );
      await tester.pumpAndSettle();
    }
    await tester.drag(
      find.byKey(const Key('video-results')),
      const Offset(0, -10000),
    );
    await tester.pumpAndSettle();

    expect(repository.pageTokens, [
      null,
      'limit-page-2',
      'limit-page-3',
      'limit-page-4',
      'limit-page-5',
    ]);
    expect(find.text('Limit Video 100'), findsOneWidget);
    expect(find.text('- 100 results -'), findsOneWidget);
    expect(find.text('- No more results -'), findsNothing);
    expect(find.byKey(const Key('search-videos-result-limit')), findsOneWidget);
  });

  testWidgets('öffnet beim Antippen eines Treffers die Player-Seite', (
    tester,
  ) async {
    final repository = _FakeSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: YouTubeSearchPage(
          searchRepository: repository,
          videoPageBuilder:
              (
                video,
                results,
                query,
                searchRepository, {
                required initiallyPaused,
              }) {
                return Scaffold(body: Text('Player für ${video.title}'));
              },
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flutter Einführung'));
    await tester.pumpAndSettle();

    expect(find.text('Player für Flutter Einführung'), findsOneWidget);
  });

  testWidgets('zeigt Channel, Datum und Beschreibung im Info-Fenster', (
    tester,
  ) async {
    final detailsSource = _ControlledVideoDetailsSource();
    final detailsRepository = YouTubeVideoDetailsRepository(
      source: detailsSource,
    );
    addTearDown(detailsRepository.close);
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        videoDetailsRepository: detailsRepository,
      ),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-info-video-1')));
    await tester.pumpAndSettle();

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Flutter Einführung'), findsNWidgets(2));
    expect(find.text('Channel'), findsOneWidget);
    expect(find.text('Flutter Channel'), findsOneWidget);
    expect(find.text('Publication date'), findsOneWidget);
    expect(find.text('01/02/2024'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(
      find.text('https://www.youtube.com/watch?v=video-1'),
      findsOneWidget,
    );
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byKey(const Key('video-info-scroll-video-1')), findsOneWidget);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.text('Eine Beschreibung zum ersten Video.'), findsNWidgets(2));
    expect(detailsSource.requests, ['en:video-1']);

    detailsSource.complete(
      'en:video-1',
      'Das ist die vollständige Beschreibung des ersten Videos.',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Das ist die vollständige Beschreibung des ersten Videos.'),
      findsOneWidget,
    );
    expect(find.text('Eine Beschreibung zum ersten Video.'), findsOneWidget);
    expect(
      find.text('https://www.youtube.com/watch?v=video-1'),
      findsOneWidget,
    );
  });

  testWidgets('scrollt eine lange Beschreibung vollständig', (tester) async {
    tester.view.physicalSize = const Size(390, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final video = YouTubeVideo(
      id: 'long-info',
      title: 'Langes Video',
      description: List.filled(
        80,
        'Dies ist eine lange Beschreibung.',
      ).join(' '),
      thumbnailUrl: '',
      channelTitle: 'Test Channel',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoInfoButton(
            key: const Key('long-info-button'),
            video: video,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('long-info-button')));
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const Key('video-info-scroll-long-info'));
    final scrollableFinder = find.descendant(
      of: listFinder,
      matching: find.byType(Scrollable),
    );
    final scrollable = tester.state<ScrollableState>(scrollableFinder);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    await tester.drag(listFinder, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.drag(listFinder, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('lädt fehlende Kachel-Beschreibungen verzögert nach', (
    tester,
  ) async {
    final description = Completer<String>();
    var loadCalls = 0;
    const video = YouTubeVideo(
      id: 'lazy-description',
      title: 'Video ohne Suchbeschreibung',
      description: '',
      thumbnailUrl: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoResultCard(
            video: video,
            onTap: () {},
            loadFullDescription: () {
              loadCalls++;
              return description.future;
            },
          ),
        ),
      ),
    );

    expect(loadCalls, 1);
    expect(find.text('Beschreibung wird geladen …'), findsOneWidget);

    description.complete('Nachgeladene vollständige Beschreibung');
    await tester.pumpAndSettle();

    expect(find.text('Nachgeladene vollständige Beschreibung'), findsOneWidget);
  });

  testWidgets('verwaltet Favorit und Playlist direkt am Suchtreffer', (
    tester,
  ) async {
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    final playlist = await profiles.createPlaylist('Merkliste');
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        profileController: profiles,
      ),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-favorite-video-1')));
    await tester.pumpAndSettle();
    expect(profiles.isFavorite('video-1'), isTrue);
    expect(find.byTooltip('Aus Favoriten entfernen'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-add-playlist-video-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merkliste'));
    await tester.pumpAndSettle();

    expect(
      profiles.activeProfile?.playlists
          .singleWhere((item) => item.id == playlist.id)
          .videos
          .single
          .id,
      'video-1',
    );
  });

  testWidgets('fordert kein Manifest vor dem Video-Tap an', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playbackService = _FakePlaybackService();
    await tester.pumpWidget(
      MaterialApp(
        home: YouTubeSearchPage(
          searchRepository: _TwentyVideoSearchRepository(),
          playbackService: playbackService,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'Zwanzig');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pump();
    await tester.pump();

    expect(playbackService.resolvedVideoIds, isEmpty);
    expect(playbackService.maximumActiveRequests, 0);

    await tester.tap(find.text('Video 0'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(playbackService.resolvedVideoIds, ['prefetch-0']);
    expect(playbackService.maximumActiveRequests, 1);
    expect(playbackService.hasManifestCallbackFor('prefetch-0'), isTrue);
  });

  testWidgets('sucht im Music-Modus über das Music-Repository', (tester) async {
    final youtubeRepository = _FakeSearchRepository();
    final musicRepository = _FakeMusicSearchRepository();
    YouTubeSearchRepository? repositoryPassedToPlayer;
    await tester.pumpWidget(
      MaterialApp(
        home: YouTubeSearchPage(
          searchRepository: youtubeRepository,
          musicSearchRepository: musicRepository,
          videoPageBuilder:
              (
                video,
                results,
                query,
                searchRepository, {
                required initiallyPaused,
              }) {
                repositoryPassedToPlayer = searchRepository;
                return Scaffold(body: Text('Music-Player für ${video.title}'));
              },
        ),
      ),
    );

    await _selectMusicSource(tester);
    expect(find.text('YouTube-Music-Suche'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search-field')), 'Oasis');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();

    expect(youtubeRepository.queries, isEmpty);
    expect(musicRepository.queries, ['Oasis']);
    expect(find.text('Wonderwall'), findsOneWidget);

    await tester.tap(find.text('Wonderwall'));
    await tester.pumpAndSettle();
    expect(repositoryPassedToPlayer, same(musicRepository));
    expect(find.text('Music-Player für Wonderwall'), findsOneWidget);
  });

  testWidgets('nutzt im Music-Modus Songs, Künstler und Music-Playlists', (
    tester,
  ) async {
    final musicRepository = _FakeMusicSearchRepository();
    final youtubeCatalog = _FakeCatalogRepository();
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await tester.pumpWidget(
      MaterialApp(
        home: YouTubeSearchPage(
          searchRepository: _FakeSearchRepository(),
          musicSearchRepository: musicRepository,
          catalogRepository: youtubeCatalog,
          profileController: profiles,
        ),
      ),
    );

    await _selectMusicSource(tester);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Künstler'), findsOneWidget);
    expect(find.text('Channels'), findsNothing);

    await tester.tap(find.byKey(const Key('search-category-channels')));
    await tester.enterText(find.byKey(const Key('search-field')), 'Oasis');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    expect(musicRepository.artistQueries, ['Oasis']);
    expect(youtubeCatalog.channelQueries, isEmpty);
    expect(find.text('Oasis Künstler'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('catalog-favorite-channel-music-artist')),
    );
    await tester.pumpAndSettle();
    expect(profiles.activeProfile!.favoriteChannels.single.id, 'music-artist');
    expect(profiles.activeProfile!.favoriteChannels.single.isMusic, isTrue);
    expect(profiles.activeProfile!.favorites, isEmpty);

    await tester.tap(find.text('Oasis Künstler'));
    await tester.pumpAndSettle();
    expect(musicRepository.openedArtistIds, ['music-artist']);
    expect(find.text('Künstler-Song'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-category-playlists')));
    await tester.enterText(find.byKey(const Key('search-field')), 'Workout');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    expect(musicRepository.playlistQueries, ['Workout']);
    expect(youtubeCatalog.playlistQueries, isEmpty);
    expect(find.text('Music Workout'), findsOneWidget);

    await tester.tap(find.text('Music Workout'));
    await tester.pumpAndSettle();
    expect(musicRepository.openedPlaylistIds, ['VLmusic-playlist']);
    expect(find.text('Playlist-Song'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Channels'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('profile-channel-music-artist')),
    );
    await tester.pumpAndSettle();
    expect(musicRepository.openedArtistIds, ['music-artist', 'music-artist']);
    expect(find.text('Künstler-Song'), findsOneWidget);
  });

  testWidgets('sucht Channels und Playlists und öffnet deren erste 20 Videos', (
    tester,
  ) async {
    final catalog = _FakeCatalogRepository();
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        catalogRepository: catalog,
      ),
    );

    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Channels'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-category-channels')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();

    expect(catalog.channelQueries, ['Flutter']);
    expect(find.text('Flutter Channel'), findsOneWidget);

    await tester.tap(find.text('Flutter Channel'));
    await tester.pumpAndSettle();

    expect(catalog.openedChannelIds, ['channel-1']);
    expect(find.byKey(const Key('video-results')), findsOneWidget);
    expect(find.text('Neuestes Channel-Video'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-category-playlists')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('search-field')), 'Training');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();

    expect(catalog.playlistQueries, ['Training']);
    expect(find.text('Training Playlist'), findsOneWidget);

    await tester.tap(find.text('Training Playlist'));
    await tester.pumpAndSettle();

    expect(catalog.openedPlaylistIds, ['playlist-1', 'playlist-1']);
    expect(find.byKey(const Key('video-results')), findsOneWidget);
    expect(find.text('Erster Playlist-Inhalt'), findsOneWidget);
    expect(find.text('Zweiter Playlist-Inhalt'), findsOneWidget);
  });

  testWidgets('speichert Channels getrennt und öffnet sie aus dem Profil', (
    tester,
  ) async {
    final catalog = _FakeCatalogRepository();
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await tester.pumpWidget(
      BrowserApp(
        searchRepository: _FakeSearchRepository(),
        catalogRepository: catalog,
        profileController: profiles,
      ),
    );

    await tester.tap(find.byKey(const Key('search-category-channels')));
    await tester.enterText(find.byKey(const Key('search-field')), 'Flutter');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('catalog-favorite-channel-channel-1')),
    );
    await tester.pumpAndSettle();

    expect(profiles.activeProfile!.favoriteChannels.single.id, 'channel-1');
    expect(profiles.activeProfile!.favorites, isEmpty);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Channels'), findsWidgets);
    await tester.tap(find.widgetWithText(Tab, 'Channels'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('profile-channels-list')),
        matching: find.byKey(const ValueKey('profile-channel-channel-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(catalog.openedChannelIds, ['channel-1']);
    expect(find.text('Neuestes Channel-Video'), findsOneWidget);
  });

  testWidgets(
    'importiert eine komplette Katalog-Playlist in bestehende oder neue Listen',
    (tester) async {
      final profiles = ProfileController.inMemory();
      await profiles.createProfile('Alex');
      final existing = await profiles.createPlaylist('Sammlung');
      final catalog = _FakeCatalogRepository();
      await tester.pumpWidget(
        BrowserApp(
          searchRepository: _FakeSearchRepository(),
          catalogRepository: catalog,
          profileController: profiles,
        ),
      );

      await tester.tap(find.byKey(const Key('search-category-playlists')));
      await tester.enterText(find.byKey(const Key('search-field')), 'Training');
      await tester.tap(find.byKey(const Key('search-button')));
      await tester.pumpAndSettle();

      final addButton = find.byKey(
        const ValueKey('catalog-add-playlist-playlist-1'),
      );
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      expect(find.text('Zu Playlist hinzufügen'), findsOneWidget);
      await tester.tap(find.text('Sammlung'));
      await tester.pumpAndSettle();

      expect(
        profiles.activeProfile!.playlists
            .firstWhere((playlist) => playlist.id == existing.id)
            .videos
            .map((video) => video.id),
        ['playlist-video', 'playlist-video-2'],
      );
      expect(catalog.playlistPageTokens, [null, 'playlist-next']);

      await tester.tap(addButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neue Playlist'));
      await tester.pumpAndSettle();
      expect(find.text('Training Playlist'), findsAtLeastNWidgets(1));
      await tester.tap(find.byKey(const Key('create-playlist-button')));
      await tester.pumpAndSettle();

      final imported = profiles.activeProfile!.playlists.firstWhere(
        (playlist) => playlist.name == 'Training Playlist',
      );
      expect(imported.videos.map((video) => video.id), [
        'playlist-video',
        'playlist-video-2',
      ]);
    },
  );

  testWidgets('importiert auch eine YouTube-Music-Playlist lokal', (
    tester,
  ) async {
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    final musicRepository = _FakeMusicSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: YouTubeSearchPage(
          searchRepository: _FakeSearchRepository(),
          musicSearchRepository: musicRepository,
          catalogRepository: _FakeCatalogRepository(),
          profileController: profiles,
        ),
      ),
    );

    await _selectMusicSource(tester);
    await tester.tap(find.byKey(const Key('search-category-playlists')));
    await tester.enterText(find.byKey(const Key('search-field')), 'Workout');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('catalog-add-playlist-VLmusic-playlist')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neue Playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-playlist-button')));
    await tester.pumpAndSettle();

    final imported = profiles.activeProfile!.playlists.single;
    expect(imported.name, 'Music Workout');
    expect(imported.videos.single.id, 'playlist-song');
    expect(imported.videos.single.isMusic, isTrue);
    expect(musicRepository.openedPlaylistIds, ['VLmusic-playlist']);
  });
}

Future<void> _selectMusicSource(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('search-source-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('search-source-music')));
  await tester.pumpAndSettle();
}

class _FakeCatalogRepository implements YouTubeCatalogRepository {
  final List<String> channelQueries = [];
  final List<String> playlistQueries = [];
  final List<String> openedChannelIds = [];
  final List<String> openedPlaylistIds = [];
  final List<String?> playlistPageTokens = [];
  final List<YouTubeSearchSort> playlistSorts = [];

  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> loadChannelVideos({
    required String channelId,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    openedChannelIds.add(channelId);
    return const YouTubeSearchResult(
      videos: [
        YouTubeVideo(
          id: 'channel-video',
          title: 'Neuestes Channel-Video',
          description: 'Beschreibung',
          thumbnailUrl: '',
        ),
      ],
    );
  }

  @override
  Future<YouTubeSearchResult> loadPlaylistVideos({
    required String playlistId,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    openedPlaylistIds.add(playlistId);
    playlistPageTokens.add(pageToken);
    if (pageToken == 'playlist-next') {
      return const YouTubeSearchResult(
        videos: [
          YouTubeVideo(
            id: 'playlist-video-2',
            title: 'Zweiter Playlist-Inhalt',
            description: 'Beschreibung',
            thumbnailUrl: '',
          ),
        ],
      );
    }
    return const YouTubeSearchResult(
      videos: [
        YouTubeVideo(
          id: 'playlist-video',
          title: 'Erster Playlist-Inhalt',
          description: 'Beschreibung',
          thumbnailUrl: '',
        ),
      ],
      nextPageToken: 'playlist-next',
    );
  }

  @override
  Future<YouTubeCatalogPage<YouTubeChannelResult>> searchChannels({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    channelQueries.add(query);
    return const YouTubeCatalogPage(
      items: [
        YouTubeChannelResult(
          id: 'channel-1',
          name: 'Flutter Channel',
          description: 'Channel-Beschreibung',
          thumbnailUrl: '',
          videoCount: 42,
        ),
      ],
    );
  }

  @override
  Future<YouTubeCatalogPage<YouTubePlaylistResult>> searchPlaylists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    playlistQueries.add(query);
    playlistSorts.add(sort);
    return const YouTubeCatalogPage(
      items: [
        YouTubePlaylistResult(
          id: 'playlist-1',
          title: 'Training Playlist',
          thumbnailUrl: '',
          videoCount: 20,
        ),
      ],
    );
  }
}

class _FakeSearchRepository implements YouTubeSearchRepository {
  final List<String> queries = [];
  final List<String?> pageTokens = [];
  final List<String> languageCodes = [];
  final List<YouTubeSearchSort> sorts = [];

  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    queries.add(query);
    pageTokens.add(pageToken);
    languageCodes.add(languageCode);
    sorts.add(sort);

    if (pageToken == 'next-page') {
      return const YouTubeSearchResult(
        videos: [
          YouTubeVideo(
            id: 'video-2',
            title: 'Flutter Fortsetzung',
            description: 'Das zweite Video.',
            thumbnailUrl: '',
          ),
        ],
        previousPageToken: 'previous-page',
      );
    }

    return YouTubeSearchResult(
      videos: [
        YouTubeVideo(
          id: 'video-1',
          title: 'Flutter Einführung',
          description: 'Eine Beschreibung zum ersten Video.',
          thumbnailUrl: '',
          channelTitle: 'Flutter Channel',
          publishedAt: DateTime(2024, 1, 2),
        ),
      ],
      nextPageToken: 'next-page',
    );
  }
}

class _DelayedNextPageSearchRepository implements YouTubeSearchRepository {
  final List<String?> pageTokens = [];
  final Completer<YouTubeSearchResult> _nextPage = Completer();

  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) {
    pageTokens.add(pageToken);
    if (pageToken == 'delayed-next') {
      return _nextPage.future;
    }
    return Future.value(
      YouTubeSearchResult(
        videos: List.generate(
          20,
          (index) => YouTubeVideo(
            id: 'delayed-video-${index + 1}',
            title: 'Video ${index + 1}',
            description: '',
            thumbnailUrl: '',
          ),
        ),
        nextPageToken: 'delayed-next',
      ),
    );
  }

  void completeNextPage() {
    _nextPage.complete(
      const YouTubeSearchResult(
        videos: [
          YouTubeVideo(
            id: 'delayed-video-21',
            title: 'Video 21',
            description: '',
            thumbnailUrl: '',
          ),
        ],
      ),
    );
  }
}

class _HundredResultSearchRepository implements YouTubeSearchRepository {
  final List<String?> pageTokens = [];

  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    pageTokens.add(pageToken);
    final pageNumber = pageToken == null
        ? 1
        : int.parse(pageToken.substring('limit-page-'.length));
    final firstNumber = (pageNumber - 1) * 20 + 1;
    return YouTubeSearchResult(
      videos: List.generate(
        20,
        (index) => YouTubeVideo(
          id: 'limit-video-${firstNumber + index}',
          title: 'Limit Video ${firstNumber + index}',
          description: '',
          thumbnailUrl: '',
        ),
      ),
      nextPageToken: 'limit-page-${pageNumber + 1}',
    );
  }
}

class _HangingSearchRepository implements YouTubeSearchRepository {
  const _HangingSearchRepository();

  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) => Completer<YouTubeSearchResult>().future;
}

class _ErrorSearchRepository implements YouTubeSearchRepository {
  const _ErrorSearchRepository();

  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) => Future.error(
    NoSuchMethodError.withInvocation(this, Invocation.getter(#text)),
  );
}

const _playlistFirstVideo = YouTubeVideo(
  id: 'playlist-first',
  title: 'Erster Titel',
  description: '',
  thumbnailUrl: '',
);

const _playlistSecondVideo = YouTubeVideo(
  id: 'playlist-second',
  title: 'Zweiter Titel',
  description: '',
  thumbnailUrl: '',
);

class _FakeMusicSearchRepository
    implements
        YouTubeSearchRepository,
        YouTubeMusicCatalogRepository,
        YouTubeMusicDiscoveryRepository {
  final List<String> queries = [];
  final List<String> languageCodes = [];
  final List<String> artistQueries = [];
  final List<String> playlistQueries = [];
  final List<String> openedArtistIds = [];
  final List<String> openedPlaylistIds = [];

  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    queries.add(query);
    languageCodes.add(languageCode);
    return const YouTubeSearchResult(
      videos: [
        YouTubeVideo(
          id: 'music-video',
          title: 'Wonderwall',
          description: 'Oasis • Morning Glory',
          thumbnailUrl: '',
          isMusic: true,
        ),
      ],
    );
  }

  @override
  Future<YouTubeCatalogPage<YouTubeChannelResult>> searchArtists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    artistQueries.add(query);
    return const YouTubeCatalogPage(
      items: [
        YouTubeChannelResult(
          id: 'music-artist',
          name: 'Oasis Künstler',
          description: '',
          thumbnailUrl: '',
          videoCount: 0,
          isMusic: true,
        ),
      ],
    );
  }

  @override
  Future<YouTubeCatalogPage<YouTubePlaylistResult>> searchMusicPlaylists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    playlistQueries.add(query);
    return const YouTubeCatalogPage(
      items: [
        YouTubePlaylistResult(
          id: 'VLmusic-playlist',
          title: 'Music Workout',
          thumbnailUrl: '',
          videoCount: 20,
        ),
      ],
    );
  }

  @override
  Future<YouTubeSearchResult> loadArtistSongs({
    required String artistId,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    openedArtistIds.add(artistId);
    return const YouTubeSearchResult(
      videos: [
        YouTubeVideo(
          id: 'artist-song',
          title: 'Künstler-Song',
          description: '',
          thumbnailUrl: '',
          isMusic: true,
        ),
      ],
    );
  }

  @override
  Future<YouTubeSearchResult> loadMusicPlaylistSongs({
    required String playlistId,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    openedPlaylistIds.add(playlistId);
    return const YouTubeSearchResult(
      videos: [
        YouTubeVideo(
          id: 'playlist-song',
          title: 'Playlist-Song',
          description: '',
          thumbnailUrl: '',
          isMusic: true,
        ),
      ],
    );
  }

  @override
  Future<HotMusicExploreResult> loadExplore({
    String languageCode = 'de',
  }) async => const HotMusicExploreResult(
    trending: [
      YouTubeVideo(
        id: 'hot-trending',
        title: 'Hot Trending',
        description: '',
        thumbnailUrl: '',
        isMusic: true,
      ),
    ],
    newReleases: [
      YouTubePlaylistResult(
        id: 'OLAK-hot-album',
        title: 'Hot Album',
        thumbnailUrl: '',
        videoCount: 0,
        creatorName: 'Hot Artist',
        typeLabel: 'Album',
      ),
    ],
  );

  @override
  Future<HotMusicChartsResult> loadCharts({
    required String countryCode,
    String languageCode = 'de',
  }) async => HotMusicChartsResult(
    countryCode: countryCode,
    countryCodes: const ['DE', 'US', 'ZZ'],
    videos: const [
      YouTubePlaylistResult(
        id: 'VL-hot-video-charts',
        title: 'Hot Video Charts',
        thumbnailUrl: '',
        videoCount: 20,
        itemsAreMusicVideos: true,
      ),
    ],
    artists: const [
      YouTubeChannelResult(
        id: 'hot-chart-artist',
        name: 'Hot Chart Artist',
        description: '',
        thumbnailUrl: '',
        videoCount: 0,
        isMusic: true,
      ),
    ],
  );

  @override
  Future<List<HotMusicGenreSection>> loadGenreSections({
    String languageCode = 'de',
  }) async => const [];

  @override
  Future<List<YouTubePlaylistResult>> loadGenrePlaylists({
    required String params,
    String languageCode = 'de',
  }) async => const [];
}

class _TwentyVideoSearchRepository implements YouTubeSearchRepository {
  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    return YouTubeSearchResult(
      videos: List.generate(
        20,
        (index) => YouTubeVideo(
          id: 'prefetch-$index',
          title: 'Video $index',
          description: 'Beschreibung $index',
          thumbnailUrl: '',
        ),
      ),
    );
  }
}

class _FakePlaybackService implements VideoPlaybackService {
  final List<String> resolvedVideoIds = [];
  final Map<String, Completer<ResolvedVideoPlayback>> _requests = {};
  final Map<String, VideoManifestEventCallback?> _callbacks = {};
  int activeRequests = 0;
  int maximumActiveRequests = 0;

  bool hasManifestCallbackFor(String videoId) => _callbacks[videoId] != null;

  @override
  void close() {}

  @override
  Future<List<VideoSubtitleCue>> loadSubtitles(String videoId) async =>
      const [];

  @override
  Future<ResolvedVideoPlayback> resolve(
    String videoId, {
    VideoManifestEventCallback? onManifestEvent,
    bool music = false,
    bool isLive = false,
    String languageCode = 'de',
  }) {
    resolvedVideoIds.add(videoId);
    _callbacks[videoId] = onManifestEvent;
    onManifestEvent?.call(
      VideoManifestLoadEvent(
        videoId: videoId,
        source: VideoManifestSource.standard,
        phase: VideoManifestLoadPhase.requested,
      ),
    );
    activeRequests++;
    if (activeRequests > maximumActiveRequests) {
      maximumActiveRequests = activeRequests;
    }
    final completer = Completer<ResolvedVideoPlayback>();
    _requests[videoId] = completer;
    return completer.future.whenComplete(() => activeRequests--);
  }

  void completeActiveRequests() {
    final requests = Map<String, Completer<ResolvedVideoPlayback>>.from(
      _requests,
    );
    _requests.clear();
    for (final entry in requests.entries) {
      _callbacks
          .remove(entry.key)
          ?.call(
            VideoManifestLoadEvent(
              videoId: entry.key,
              source: VideoManifestSource.standard,
              phase: VideoManifestLoadPhase.available,
            ),
          );
      final quality = VideoQualityOption(
        label: '720p',
        height: 720,
        videoUrl: Uri.parse('https://example.com/${entry.key}.mp4'),
      );
      entry.value.complete(
        ResolvedVideoPlayback(qualities: [quality], defaultQuality: quality),
      );
    }
  }
}

class _ControlledVideoDetailsSource implements YouTubeVideoDetailsSource {
  final List<String> requests = [];
  final Map<String, Completer<String>> _responses = {};

  @override
  Future<String> loadDescription({
    required String videoId,
    required String languageCode,
  }) {
    final key = '$languageCode:$videoId';
    requests.add(key);
    return (_responses[key] = Completer<String>()).future;
  }

  void complete(String key, String description) {
    _responses[key]!.complete(description);
  }

  @override
  void close() {}
}
