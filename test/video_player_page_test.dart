import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/hot_music.dart';
import 'package:flutter_browser_app/models/app_tutorial_stage.dart';
import 'package:flutter_browser_app/models/user_profile.dart';
import 'package:flutter_browser_app/models/video_playback.dart';
import 'package:flutter_browser_app/models/video_search_source.dart';
import 'package:flutter_browser_app/models/youtube_catalog_item.dart';
import 'package:flutter_browser_app/models/youtube_search_sort.dart';
import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/screens/video_player_page.dart';
import 'package:flutter_browser_app/services/profile_controller.dart';
import 'package:flutter_browser_app/services/playback_manifest_cache.dart';
import 'package:flutter_browser_app/services/video_playback_service.dart';
import 'package:flutter_browser_app/services/youtube_catalog_repository.dart';
import 'package:flutter_browser_app/services/youtube_music_catalog_repository.dart';
import 'package:flutter_browser_app/services/youtube_music_discovery_repository.dart';
import 'package:flutter_browser_app/services/youtube_search_repository.dart';
import 'package:flutter_browser_app/services/youtube_video_details_repository.dart';
import 'package:flutter_browser_app/widgets/tutorial_coach_overlay.dart';
import 'package:flutter_browser_app/widgets/video_result_card.dart';

void main() {
  testWidgets('führt ohne Zwangsaktionen durch das Player-Tutorial', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profiles = ProfileController.inMemory(tutorialsEnabled: true);
    await profiles.createProfile('Alex');

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _musicVideo,
          searchResults: const [_musicVideo, _otherVideo],
          searchQuery: 'Tutorial',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
          profileController: profiles,
          initiallyPaused: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PopScope>(
            find.byKey(const Key('player-tutorial-navigation-lock')),
          )
          .canPop,
      isFalse,
    );

    const titles = [
      'Start und Pause',
      'Zehn Sekunden springen',
      'Vor- und zurückspulen',
      'Wiedergabesteuerung',
      'Weitere Optionen',
      'Auto-Play',
      'Queue mischen',
      'Like oder Dislike',
      'Als Favorit speichern',
      'Zu einer Playlist hinzufügen',
      'Medien-Informationen',
    ];
    double? nextButtonXWithoutBack;
    for (var index = 0; index < titles.length; index++) {
      final title = tester.widget<Text>(
        find.byKey(const Key('tutorial-coach-title')),
      );
      expect(title.data, titles[index]);
      expect(
        find.text('Player-Tutorial (4/4) · Schritt ${index + 1} von 11'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tutorial-next-button')), findsOneWidget);
      expect(
        find.widgetWithText(
          FilledButton,
          index == titles.length - 1 ? 'Fertig' : 'Weiter',
        ),
        findsOneWidget,
      );
      final nextButtonX = tester
          .getCenter(find.byKey(const Key('tutorial-next-button')))
          .dx;
      if (index == 0) {
        nextButtonXWithoutBack = nextButtonX;
        expect(find.byKey(const Key('tutorial-back-button')), findsNothing);
        expect(
          tester
              .widget<TutorialCoachOverlay>(find.byType(TutorialCoachOverlay))
              .additionalTargetKeys,
          isEmpty,
        );
        expect(find.byKey(const Key('tutorial-highlight-0')), findsOneWidget);
      } else if (index == 1) {
        expect(nextButtonX, nextButtonXWithoutBack);
        expect(
          tester.getCenter(find.byKey(const Key('tutorial-back-button'))).dx,
          greaterThan(nextButtonX),
        );
        expect(
          tester
              .widget<TutorialCoachOverlay>(find.byType(TutorialCoachOverlay))
              .additionalTargetKeys,
          hasLength(1),
        );
        expect(find.byKey(const Key('tutorial-highlight-1')), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('tutorial-next-button')));
      await tester.pumpAndSettle();
    }

    expect(find.byKey(const Key('tutorial-coach-overlay')), findsNothing);
    expect(profiles.isTutorialStageCompleted(AppTutorialStage.player), isTrue);
  });

  testWidgets('überspringt auch im Player alle Tutorial-Abschnitte', (
    tester,
  ) async {
    final profiles = ProfileController.inMemory(tutorialsEnabled: true);
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _musicVideo,
          searchResults: const [_musicVideo],
          searchQuery: 'Tutorial',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
          profileController: profiles,
          initiallyPaused: true,
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

  testWidgets('zeigt im Hochformat Suche und übrige Treffer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detailsRepository = YouTubeVideoDetailsRepository(
      source: _ImmediateVideoDetailsSource(),
    );
    addTearDown(detailsRepository.close);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
          videoDetailsRepository: detailsRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-search-field')), findsOneWidget);
    final sectionNavigation = tester.widget<NavigationBar>(
      find.byKey(const Key('player-section-navigation')),
    );
    expect(sectionNavigation.height, 52);
    expect(
      sectionNavigation.labelBehavior,
      NavigationDestinationLabelBehavior.alwaysHide,
    );
    expect(find.byKey(const Key('player-section-hot-music')), findsOneWidget);
    expect(find.byKey(const Key('player-section-profile')), findsOneWidget);
    expect(
      find.byKey(const Key('player-search-source-dropdown-indicator')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-search-clear-button')), findsOneWidget);
    expect(find.byKey(const Key('video-like-button')), findsOneWidget);
    expect(find.byKey(const Key('video-dislike-button')), findsOneWidget);
    expect(find.byKey(const Key('video-favorite-button')), findsOneWidget);
    expect(find.byKey(const Key('video-add-playlist-button')), findsOneWidget);
    expect(find.byKey(const Key('video-info-button')), findsOneWidget);
    expect(find.byKey(const Key('video-autoplay-switch')), findsOneWidget);
    expect(find.byKey(const Key('video-shuffle-button')), findsOneWidget);
    expect(find.text('Auto-Play'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Auto-Play')).style?.fontSize, 10);
    final autoplayTop = tester
        .getTopLeft(find.byKey(const Key('video-autoplay-switch')))
        .dy;
    final likeTop = tester
        .getTopLeft(find.byKey(const Key('video-like-button')))
        .dy;
    expect((autoplayTop - likeTop).abs(), lessThanOrEqualTo(1));
    expect(find.byKey(const Key('search-favorite-other')), findsOneWidget);
    expect(find.byKey(const Key('search-add-playlist-other')), findsOneWidget);
    expect(find.byKey(const Key('search-info-other')), findsOneWidget);
    final resultCard = tester.widget<VideoResultCard>(
      find.ancestor(
        of: find.byKey(const Key('search-info-other')),
        matching: find.byType(VideoResultCard),
      ),
    );
    expect(resultCard.compact, isFalse);
    expect(find.text('Anderes Video'), findsOneWidget);
    expect(find.text('Ausgewähltes Video'), findsNothing);

    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byKey(const Key('player-search-clear-button')));
    await tester.pump();
    final playerSearchField = tester.widget<TextField>(
      find.byKey(const Key('player-search-field')),
    );
    expect(playerSearchField.controller?.text, isEmpty);
    expect(
      playerSearchField.controller?.selection,
      const TextSelection.collapsed(offset: 0),
    );
    expect(playerSearchField.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const Key('player-search-clear-button')), findsNothing);

    await tester.tap(find.byKey(const Key('video-info-button')));
    await tester.pumpAndSettle();
    expect(find.text('Informationen'), findsOneWidget);
    expect(find.text('Titel'), findsOneWidget);
    expect(find.text('Ausgewähltes Video'), findsOneWidget);
    expect(find.text('Channel'), findsOneWidget);
    expect(find.text('Nicht verfügbar'), findsNWidgets(2));
    expect(find.text('Vollständige Player-Beschreibung'), findsOneWidget);
    expect(find.text('Quelle'), findsOneWidget);
    expect(
      find.text('https://www.youtube.com/watch?v=selected'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-error-details-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('player-test-code-403'), findsOneWidget);
  });

  testWidgets('startet einen Suchhistorien-Treffer auch im Player', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await profiles.recordSearchQuery('Oasis Live');
    await profiles.recordSearchQuery('Arte Doku');
    final repository = _FakeSearchRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: repository,
          playbackService: _FailingPlaybackService(),
          profileController: profiles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('player-search-field')), 'oa');
    await tester.pump();
    expect(
      find.byKey(const Key('player-search-history-dropdown')),
      findsOneWidget,
    );
    expect(find.text('Oasis Live'), findsOneWidget);
    expect(find.text('Arte Doku'), findsNothing);

    await tester.tap(find.text('Oasis Live'));
    await tester.pumpAndSettle();

    expect(repository.queries, ['Oasis Live']);
    expect(profiles.activeProfile!.searchHistory.first, 'Oasis Live');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('player-search-field')))
          .controller
          ?.text,
      'Oasis Live',
    );
    expect(
      find.byKey(const Key('player-search-history-dropdown')),
      findsNothing,
    );
  });

  testWidgets('wechselt im Player zum Profil ohne den Player neu zu laden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    final playbackService = _FailingPlaybackService();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: playbackService,
          profileController: profiles,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final loadsBefore = playbackService.resolvedVideoIds.length;

    await tester.tap(find.byKey(const Key('player-section-profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-selector')), findsOneWidget);
    expect(find.byKey(const Key('player-search-field')), findsNothing);
    expect(playbackService.resolvedVideoIds, hasLength(loadsBefore));

    await tester.tap(find.byKey(const Key('player-section-search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-search-field')), findsOneWidget);
    expect(find.byKey(const Key('profile-selector')), findsNothing);
    expect(playbackService.resolvedVideoIds, hasLength(loadsBefore));
  });

  testWidgets('wechselt bei einem Music-Favoriten in den Music-Suchmodus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await profiles.toggleFavorite(_musicVideo);
    final youtubeRepository = _FakeSearchRepository();
    final musicRepository = _FakeMusicSearchRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo],
          searchQuery: '',
          searchRepository: youtubeRepository,
          youtubeSearchRepository: youtubeRepository,
          musicSearchRepository: musicRepository,
          playbackService: _FailingPlaybackService(),
          profileController: profiles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-section-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Favoriten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music Song'));
    await tester.pumpAndSettle();

    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Künstler'), findsOneWidget);
    expect(find.text('Videos'), findsNothing);
    expect(find.byKey(const Key('music-player-artwork')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('player-search-field')),
      'Oasis',
    );
    await tester.tap(find.byKey(const Key('player-search-button')));
    await tester.pumpAndSettle();

    expect(musicRepository.songQueries, ['Oasis']);
    expect(youtubeRepository.queries, isEmpty);
  });

  testWidgets(
    'wechselt bei einer gespeicherten Video-Playlist in den Video-Suchmodus',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final profiles = ProfileController.inMemory();
      await profiles.createProfile('Alex');
      final playlist = await profiles.createPlaylist('Videosammlung');
      await profiles.addVideoToPlaylist(playlist.id, _selectedVideo);
      final youtubeRepository = _FakeSearchRepository();
      final musicRepository = _FakeMusicSearchRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            video: _musicVideo,
            searchResults: const [_musicVideo],
            searchQuery: '',
            searchRepository: musicRepository,
            youtubeSearchRepository: youtubeRepository,
            musicSearchRepository: musicRepository,
            searchSource: VideoSearchSource.youtubeMusic,
            playbackService: _FailingPlaybackService(),
            profileController: profiles,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('player-section-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Playlist abspielen'));
      await tester.pumpAndSettle();

      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('Songs'), findsNothing);
      expect(find.byKey(const Key('music-player-artwork')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('player-search-field')),
        'Flutter',
      );
      await tester.tap(find.byKey(const Key('player-search-button')));
      await tester.pumpAndSettle();

      expect(youtubeRepository.queries, ['Flutter']);
      expect(musicRepository.songQueries, isEmpty);
    },
  );

  testWidgets('zeigt im Querformat ausschließlich den Player', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-fullscreen-layout')), findsOneWidget);
    expect(find.byKey(const Key('player-search-field')), findsNothing);
    expect(find.text('Anderes Video'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.byTooltip('Zurück'), findsNothing);
  });

  testWidgets('zieht den vorhandenen Player dynamisch nach unten', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = find.byKey(const Key('player-pull-down-surface'));
    final initialRect = tester.getRect(surface);
    final gesture = await tester.startGesture(initialRect.center);
    await gesture.moveBy(const Offset(0, 48));
    await tester.pump();

    final draggedRect = tester.getRect(surface);
    expect(draggedRect.center.dy, greaterThan(initialRect.center.dy));
    expect(draggedRect.height, greaterThan(initialRect.height));
    expect(find.byKey(const Key('player-fullscreen-layout')), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-fullscreen-layout')), findsNothing);
    final restoredRect = tester.getRect(surface);
    expect(restoredRect.top, closeTo(initialRect.top, 0.01));
    expect(restoredRect.height, closeTo(initialRect.height, 0.01));
  });

  testWidgets('schließt einen ausreichend weiten Pull-down als Vollbild ab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = find.byKey(const Key('player-pull-down-surface'));
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-fullscreen-layout')), findsOneWidget);
    expect(find.byKey(const Key('player-search-field')), findsNothing);
    expect(find.byKey(const Key('player-section-navigation')), findsNothing);
  });

  testWidgets('armt den Queue-Pull nur bei Start am ersten Listeneintrag', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final results = <YouTubeVideo>[
      _selectedVideo,
      ...List.generate(
        19,
        (index) => YouTubeVideo(
          id: 'pull-down-${index + 2}',
          title: 'Pull-down ${index + 2}',
          description: '',
          thumbnailUrl: '',
        ),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: results,
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('player-video-results'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    await tester.drag(list, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));

    await tester.drag(list, const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, closeTo(0, 0.01));
    expect(find.byKey(const Key('player-fullscreen-layout')), findsNothing);

    final surface = find.byKey(const Key('player-pull-down-surface'));
    final initialCenter = tester.getCenter(surface);
    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(tester.getCenter(surface).dy, greaterThan(initialCenter.dy));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-fullscreen-layout')), findsOneWidget);
  });

  testWidgets('verlässt Hochkant-Vollbild durch mittigen Pull-up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pullDown = find.byKey(const Key('player-pull-down-surface'));
    final enterGesture = await tester.startGesture(tester.getCenter(pullDown));
    await enterGesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 300));
    await enterGesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-fullscreen-layout')), findsOneWidget);

    final pullUp = find.byKey(const Key('player-pull-up-surface'));
    final initialCenter = tester.getCenter(pullUp);
    final exitGesture = await tester.startGesture(initialCenter);
    await exitGesture.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(tester.getCenter(pullUp).dy, lessThan(initialCenter.dy));
    await tester.pump(const Duration(milliseconds: 300));
    await exitGesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-fullscreen-layout')), findsNothing);
    expect(find.byKey(const Key('player-search-field')), findsOneWidget);
    expect(find.byKey(const Key('player-section-navigation')), findsOneWidget);

    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-fullscreen-layout')), findsOneWidget);
  });

  testWidgets('ignoriert Pull-up außerhalb der Bildschirmmitte', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pullDown = find.byKey(const Key('player-pull-down-surface'));
    final enterGesture = await tester.startGesture(tester.getCenter(pullDown));
    await enterGesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 300));
    await enterGesture.up();
    await tester.pumpAndSettle();

    final pullUp = find.byKey(const Key('player-pull-up-surface'));
    final rect = tester.getRect(pullUp);
    final edgeGesture = await tester.startGesture(
      Offset(rect.left + rect.width * 0.1, rect.center.dy),
    );
    await edgeGesture.moveBy(const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 300));
    await edgeGesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-fullscreen-layout')), findsOneWidget);
  });

  testWidgets(
    'wechselt bei Hochkant-zu-Quer-Rotation automatisch ins Vollbild',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            video: _selectedVideo,
            searchResults: const [_selectedVideo, _otherVideo],
            searchQuery: 'Flutter',
            searchRepository: _FakeSearchRepository(),
            playbackService: _FailingPlaybackService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-fullscreen-layout')), findsNothing);

      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-fullscreen-layout')), findsOneWidget);
      expect(find.byKey(const Key('player-search-field')), findsNothing);
      expect(find.byKey(const Key('player-section-navigation')), findsNothing);
      expect(find.byKey(const Key('player-pull-up-surface')), findsOneWidget);
    },
  );

  testWidgets('fordert bei Pull-up im Querformat den Vollbildaustritt an', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pullUp = find.byKey(const Key('player-pull-up-surface'));
    final gesture = await tester.startGesture(tester.getCenter(pullUp));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      platformCalls.any(
        (call) =>
            call.method == 'SystemChrome.setPreferredOrientations' &&
            call.arguments is List<Object?> &&
            (call.arguments as List<Object?>).contains(
              'DeviceOrientation.portraitUp',
            ),
      ),
      isTrue,
    );

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-fullscreen-layout')), findsNothing);
    expect(find.byKey(const Key('player-search-field')), findsOneWidget);
  });

  testWidgets('beendet eine hängende Player-Suche nach zehn Sekunden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _HangingSearchRepository(),
          playbackService: _FailingPlaybackService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('player-search-field')),
      'Timeout',
    );
    await tester.tap(find.byKey(const Key('player-search-button')));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.text(
        'Die Suche hat länger als 10 Sekunden gedauert. '
        'Bitte versuche es erneut.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('blendet PiP für YouTube-Music-Songs aus', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _musicVideo,
          searchResults: const [_musicVideo],
          searchQuery: 'Oasis',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
          searchSource: VideoSearchSource.youtubeMusic,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('picture-in-picture-button')), findsNothing);
    expect(find.byKey(const Key('player-search-field')), findsOneWidget);
    expect(find.byKey(const Key('music-player-artwork')), findsOneWidget);
    final artwork = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('music-player-artwork')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (artwork.image as NetworkImage).url,
      'https://example.com/music-song.jpg',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Musikvideos nutzen den Videopfad ohne PiP oder Music-Artwork', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playbackService = _FailingPlaybackService();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _visualMusicVideo,
          searchResults: const [_visualMusicVideo],
          searchQuery: '',
          searchRepository: _FakeSearchRepository(),
          playbackService: playbackService,
          searchSource: VideoSearchSource.youtubeMusic,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(playbackService.resolvedMusicModes, [false]);
    expect(find.byKey(const Key('picture-in-picture-button')), findsNothing);
    expect(find.byKey(const Key('music-player-artwork')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('klassifiziert Video-Chart-Inhalte auch im Player als Video', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final musicRepository = _FakeMusicSearchRepository();
    final playbackService = _FailingPlaybackService();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo],
          searchQuery: '',
          searchRepository: _FakeSearchRepository(),
          youtubeSearchRepository: _FakeSearchRepository(),
          musicSearchRepository: musicRepository,
          playbackService: playbackService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-section-hot-music')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-hot-music-section-charts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Player Video Charts'));
    await tester.pumpAndSettle();

    expect(musicRepository.openedPlaylistIds, ['VL-player-video-charts']);
    expect(playbackService.resolvedVideoIds.last, 'playlist-song');
    expect(playbackService.resolvedMusicModes.last, isFalse);
    expect(find.byKey(const Key('music-player-artwork')), findsNothing);
  });

  testWidgets('speichert Player-Aktionen im aktiven Profil', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    final playlist = await profiles.createPlaylist('Training');

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: _FakeSearchRepository(),
          playbackService: _FailingPlaybackService(),
          profileController: profiles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(profiles.activeProfile?.autoplaySearchResults, isFalse);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('video-shuffle-button')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('video-autoplay-switch')));
    await tester.pumpAndSettle();
    expect(profiles.activeProfile?.autoplaySearchResults, isTrue);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('video-autoplay-switch')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('video-shuffle-button')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('video-shuffle-button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('video-shuffle-button')))
          .isSelected,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('video-autoplay-switch')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('video-shuffle-button')))
          .isSelected,
      isFalse,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('video-shuffle-button')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('video-autoplay-switch')));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsNothing);
    expect(find.byIcon(Icons.queue_music), findsNothing);

    await tester.tap(find.byKey(const Key('video-favorite-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('video-like-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('video-add-playlist-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Training'));
    await tester.pumpAndSettle();

    final resultFavorite = find.byKey(const Key('search-favorite-other'));
    await tester.ensureVisible(resultFavorite);
    await tester.tap(resultFavorite);
    await tester.pumpAndSettle();
    final resultPlaylist = find.byKey(const Key('search-add-playlist-other'));
    await tester.ensureVisible(resultPlaylist);
    await tester.tap(resultPlaylist);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Training'));
    await tester.pumpAndSettle();

    expect(profiles.isFavorite(_selectedVideo.id), isTrue);
    expect(profiles.isFavorite(_otherVideo.id), isTrue);
    expect(profiles.reactionFor(_selectedVideo.id), VideoReaction.like);
    expect(
      profiles.activeProfile?.playlists
          .firstWhere((item) => item.id == playlist.id)
          .videos
          .map((video) => video.id),
      [_selectedVideo.id, _otherVideo.id],
    );
  });

  testWidgets(
    'hängt Ergebnisse im Player an ohne den laufenden Player neu zu laden',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final profiles = ProfileController.inMemory();
      await profiles.createProfile('Alex');
      await profiles.setLanguage(ProfileLanguage.english);
      final repository = _FakeSearchRepository();
      final playbackService = _FailingPlaybackService();
      final manifestCache = PlaybackManifestCache(playbackService);

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            video: _selectedVideo,
            searchResults: const [_selectedVideo, _otherVideo],
            searchQuery: 'Flutter',
            searchRepository: repository,
            playbackService: playbackService,
            manifestCache: manifestCache,
            profileController: profiles,
            initialNextPageToken: 'next-page',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selectedLoadsBefore = playbackService.resolvedVideoIds
          .where((videoId) => videoId == _selectedVideo.id)
          .length;

      expect(repository.pageTokens, ['next-page']);
      expect(repository.languageCodes, ['en']);
      expect(find.byKey(const Key('player-next-page')), findsNothing);
      expect(find.text('Anderes Video'), findsOneWidget);
      expect(find.text('Video auf Seite 2'), findsOneWidget);
      expect(find.text('- Keine weiteren Treffer -'), findsOneWidget);
      expect(
        playbackService.resolvedVideoIds
            .where((videoId) => videoId == _selectedVideo.id)
            .length,
        selectedLoadsBefore,
      );
      expect(
        playbackService.resolvedVideoIds,
        isNot(contains(_pageTwoVideo.id)),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(
        playbackService.resolvedVideoIds,
        isNot(contains(_pageTwoVideo.id)),
      );
    },
  );

  testWidgets('begrenzt Player-Suchergebnisse und Queue auf 100 Treffer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    await profiles.setAutoplaySearchResults(true);
    final repository = _FakeSearchRepository();
    final playbackService = _FailingPlaybackService();
    final results = <YouTubeVideo>[
      _selectedVideo,
      ...List.generate(
        119,
        (index) => YouTubeVideo(
          id: 'player-limit-${index + 2}',
          title: 'Player Limit ${index + 2}',
          description: '',
          thumbnailUrl: '',
        ),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: results,
          searchQuery: 'Flutter',
          searchRepository: repository,
          playbackService: playbackService,
          profileController: profiles,
          initialNextPageToken: 'next-page',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('player-video-results')),
      const Offset(0, -100000),
    );
    await tester.pumpAndSettle();

    expect(repository.pageTokens, isEmpty);
    expect(find.text('Player Limit 100'), findsOneWidget);
    expect(find.text('Player Limit 101'), findsNothing);
    expect(find.text('- 100 Treffer -'), findsOneWidget);
    expect(find.byKey(const Key('player-video-result-limit')), findsOneWidget);
  });

  testWidgets('nutzt im Player Relevanz ohne sichtbare Sortiersteuerung', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    final repository = _FakeSearchRepository();
    final catalog = _FakeCatalogRepository();
    final playbackService = _FailingPlaybackService();

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          video: _selectedVideo,
          searchResults: const [_selectedVideo, _otherVideo],
          searchQuery: 'Flutter',
          searchRepository: repository,
          catalogRepository: catalog,
          playbackService: playbackService,
          profileController: profiles,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final playerLoadsBefore = playbackService.resolvedVideoIds.length;

    await tester.tap(find.byKey(const Key('player-search-category-videos')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('player-search-sort-videos-viewCount')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('player-search-category-videos')),
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
      findsNothing,
    );
    expect(repository.sorts, isEmpty);
    expect(
      profiles.activeProfile?.videoSearchSort,
      YouTubeSearchSort.relevance,
    );

    await tester.tap(find.byKey(const Key('player-search-category-playlists')));
    await tester.enterText(
      find.byKey(const Key('player-search-field')),
      'Training',
    );
    await tester.tap(find.byKey(const Key('player-search-button')));
    await tester.pumpAndSettle();
    expect(catalog.playlistSorts, [YouTubeSearchSort.relevance]);

    await tester.tap(find.byKey(const Key('player-search-category-playlists')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('player-search-sort-playlists-uploadDate')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('player-search-category-playlists')),
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
      findsNothing,
    );
    expect(catalog.playlistSorts, [YouTubeSearchSort.relevance]);
    expect(
      profiles.activeProfile?.playlistSearchSort,
      YouTubeSearchSort.relevance,
    );
    expect(playbackService.resolvedVideoIds, hasLength(playerLoadsBefore));
  });

  testWidgets(
    'nutzt Channel-Suche im Player ohne den aktuellen Player neu zu laden',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playbackService = _FailingPlaybackService();
      final catalog = _FakeCatalogRepository();
      final profiles = ProfileController.inMemory();
      await profiles.createProfile('Alex');

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            video: _selectedVideo,
            searchResults: const [_selectedVideo, _otherVideo],
            searchQuery: 'Flutter',
            searchRepository: _FakeSearchRepository(),
            catalogRepository: catalog,
            playbackService: playbackService,
            profileController: profiles,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selectedLoadsBefore = playbackService.resolvedVideoIds.length;

      await tester.tap(
        find.byKey(const Key('player-search-category-channels')),
      );
      await tester.enterText(
        find.byKey(const Key('player-search-field')),
        'Flutter',
      );
      await tester.tap(find.byKey(const Key('player-search-button')));
      await tester.pumpAndSettle();

      expect(find.text('Flutter Channel'), findsOneWidget);
      expect(playbackService.resolvedVideoIds, hasLength(selectedLoadsBefore));

      await tester.tap(
        find.byKey(const ValueKey('catalog-favorite-channel-channel-1')),
      );
      await tester.pumpAndSettle();
      expect(profiles.activeProfile!.favoriteChannels.single.id, 'channel-1');
      expect(profiles.activeProfile!.favorites, isEmpty);

      await tester.tap(find.text('Flutter Channel'));
      await tester.pumpAndSettle();

      expect(find.text('Neuestes Channel-Video'), findsOneWidget);
      await tester.tap(find.byKey(const Key('player-search-category-videos')));
      await tester.pump();
      expect(
        find.byKey(const Key('player-search-sort-videos-rating')),
        findsNothing,
      );
      expect(playbackService.resolvedVideoIds, hasLength(selectedLoadsBefore));
    },
  );

  testWidgets(
    'importiert eine komplette Playlist im Player ohne Playerreload',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playbackService = _FailingPlaybackService();
      final catalog = _FakeCatalogRepository();
      final musicRepository = _FakeMusicSearchRepository();
      final profiles = ProfileController.inMemory();
      await profiles.createProfile('Alex');
      final localPlaylist = await profiles.createPlaylist('Sammlung');

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            video: _selectedVideo,
            searchResults: const [_selectedVideo, _otherVideo],
            searchQuery: 'Flutter',
            searchRepository: _FakeSearchRepository(),
            musicSearchRepository: musicRepository,
            catalogRepository: catalog,
            playbackService: playbackService,
            profileController: profiles,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final playerLoadsBefore = playbackService.resolvedVideoIds.length;

      await tester.tap(
        find.byKey(const Key('player-search-category-playlists')),
      );
      await tester.enterText(
        find.byKey(const Key('player-search-field')),
        'Training',
      );
      await tester.tap(find.byKey(const Key('player-search-button')));
      await tester.pumpAndSettle();

      final addButton = find.byKey(
        const ValueKey('catalog-add-playlist-player-playlist'),
      );
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sammlung'));
      await tester.pumpAndSettle();

      expect(catalog.playlistPageTokens, [null, 'player-playlist-next']);
      expect(
        profiles.activeProfile!.playlists
            .firstWhere((playlist) => playlist.id == localPlaylist.id)
            .videos
            .map((video) => video.id),
        ['player-playlist-video-1', 'player-playlist-video-2'],
      );
      expect(playbackService.resolvedVideoIds, hasLength(playerLoadsBefore));

      await tester.tap(find.byKey(const Key('player-search-source-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-search-source-music')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('player-search-category-playlists')),
      );
      await tester.enterText(
        find.byKey(const Key('player-search-field')),
        'Workout',
      );
      await tester.tap(find.byKey(const Key('player-search-button')));
      await tester.pumpAndSettle();
      final musicAddButton = find.byKey(
        const ValueKey('catalog-add-playlist-music-playlist'),
      );
      await tester.ensureVisible(musicAddButton);
      await tester.tap(musicAddButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sammlung'));
      await tester.pumpAndSettle();

      expect(musicRepository.openedPlaylistIds, ['music-playlist']);
      expect(
        profiles.activeProfile!.playlists
            .firstWhere((playlist) => playlist.id == localPlaylist.id)
            .videos
            .map((video) => video.id),
        ['player-playlist-video-1', 'player-playlist-video-2', 'playlist-song'],
      );
      expect(playbackService.resolvedVideoIds, hasLength(playerLoadsBefore));
    },
  );

  testWidgets(
    'wechselt die Player-Suche zwischen YouTube und Music ohne Playerreload',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final youtubeRepository = _FakeSearchRepository();
      final musicRepository = _FakeMusicSearchRepository();
      final playbackService = _FailingPlaybackService();
      final profiles = ProfileController.inMemory();
      await profiles.createProfile('Alex');

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            video: _selectedVideo,
            searchResults: const [_selectedVideo, _otherVideo],
            searchQuery: 'Flutter',
            searchRepository: youtubeRepository,
            youtubeSearchRepository: youtubeRepository,
            musicSearchRepository: musicRepository,
            playbackService: playbackService,
            profileController: profiles,
            initialNextPageToken: 'obsolete-youtube-page',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final playerLoadsBefore = playbackService.resolvedVideoIds.length;

      await tester.tap(find.byKey(const Key('player-search-source-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-search-source-music')));
      await tester.pumpAndSettle();

      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Künstler'), findsOneWidget);
      expect(find.text('Channels'), findsNothing);
      expect(find.byKey(const Key('player-next-page')), findsNothing);
      expect(playbackService.resolvedVideoIds, hasLength(playerLoadsBefore));

      await tester.enterText(
        find.byKey(const Key('player-search-field')),
        'Oasis',
      );
      await tester.tap(find.byKey(const Key('player-search-button')));
      await tester.pumpAndSettle();

      expect(musicRepository.songQueries, ['Oasis']);
      expect(youtubeRepository.queries, ['Flutter']);
      expect(find.text('Wonderwall'), findsOneWidget);
      expect(playbackService.resolvedVideoIds, hasLength(playerLoadsBefore));

      await tester.tap(
        find.byKey(const Key('player-search-category-channels')),
      );
      await tester.enterText(
        find.byKey(const Key('player-search-field')),
        'Oasis',
      );
      await tester.tap(find.byKey(const Key('player-search-button')));
      await tester.pumpAndSettle();

      expect(musicRepository.artistQueries, ['Oasis']);
      expect(find.text('Oasis Künstler'), findsOneWidget);
      expect(playbackService.resolvedVideoIds, hasLength(playerLoadsBefore));

      await tester.tap(
        find.byKey(const ValueKey('catalog-favorite-channel-oasis')),
      );
      await tester.pumpAndSettle();
      expect(profiles.activeProfile!.favoriteChannels.single.id, 'oasis');
      expect(profiles.activeProfile!.favoriteChannels.single.isMusic, isTrue);
      expect(profiles.activeProfile!.favorites, isEmpty);

      await tester.tap(find.text('Oasis Künstler'));
      await tester.pumpAndSettle();
      expect(musicRepository.openedArtistIds, ['oasis']);
      expect(find.text('Künstler-Song'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('player-search-category-playlists')),
      );
      await tester.enterText(
        find.byKey(const Key('player-search-field')),
        'Workout',
      );
      await tester.tap(find.byKey(const Key('player-search-button')));
      await tester.pumpAndSettle();

      expect(musicRepository.playlistQueries, ['Workout']);
      expect(find.text('Music Workout'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('catalog-add-playlist-music-playlist')),
        findsOneWidget,
      );

      await tester.tap(find.text('Music Workout'));
      await tester.pumpAndSettle();
      expect(musicRepository.openedPlaylistIds, ['music-playlist']);
      expect(find.text('Playlist-Song'), findsOneWidget);
      expect(playbackService.resolvedVideoIds, hasLength(playerLoadsBefore));

      await tester.tap(find.byKey(const Key('player-search-source-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-search-source-youtube')));
      await tester.pumpAndSettle();

      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('Künstler'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('player-search-field')),
        'Flutter',
      );
      await tester.tap(find.byKey(const Key('player-search-button')));
      await tester.pumpAndSettle();

      expect(youtubeRepository.queries, ['Flutter', 'Flutter']);
      expect(musicRepository.songQueries, ['Oasis']);
      expect(playbackService.resolvedVideoIds, hasLength(playerLoadsBefore));
    },
  );
}

class _ImmediateVideoDetailsSource implements YouTubeVideoDetailsSource {
  @override
  Future<String> loadDescription({
    required String videoId,
    required String languageCode,
  }) async => 'Vollständige Player-Beschreibung';

  @override
  void close() {}
}

const _selectedVideo = YouTubeVideo(
  id: 'selected',
  title: 'Ausgewähltes Video',
  description: 'Beschreibung',
  thumbnailUrl: '',
);

const _otherVideo = YouTubeVideo(
  id: 'other',
  title: 'Anderes Video',
  description: 'Beschreibung',
  thumbnailUrl: '',
);

const _pageTwoVideo = YouTubeVideo(
  id: 'page-two',
  title: 'Video auf Seite 2',
  description: 'Beschreibung',
  thumbnailUrl: '',
);

const _musicVideo = YouTubeVideo(
  id: 'music-song',
  title: 'Music Song',
  description: 'Künstler • Album',
  thumbnailUrl: 'https://example.com/music-song.jpg',
  isMusic: true,
);

const _visualMusicVideo = YouTubeVideo(
  id: 'visual-music-video',
  title: 'Visual Music Video',
  description: 'Kuenstler',
  thumbnailUrl: 'https://example.com/visual-music-video.jpg',
  isMusic: true,
  isMusicVideo: true,
);

class _FailingPlaybackService implements VideoPlaybackService {
  final List<String> resolvedVideoIds = [];
  final List<bool> resolvedMusicModes = [];

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
  }) async {
    resolvedVideoIds.add(videoId);
    resolvedMusicModes.add(music);
    throw VideoPlaybackException(
      'Testfehler',
      cause: StateError('player-test-code-403'),
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
        videos: [_pageTwoVideo],
        previousPageToken: 'previous-page',
      );
    }
    return const YouTubeSearchResult(videos: [_otherVideo]);
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

class _FakeMusicSearchRepository
    implements
        YouTubeSearchRepository,
        YouTubeMusicCatalogRepository,
        YouTubeMusicDiscoveryRepository {
  final List<String> songQueries = [];
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
    songQueries.add(query);
    return const YouTubeSearchResult(
      videos: [
        YouTubeVideo(
          id: 'wonderwall',
          title: 'Wonderwall',
          description: 'Oasis',
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
          id: 'oasis',
          name: 'Oasis Künstler',
          description: '',
          thumbnailUrl: '',
          videoCount: 1,
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
          id: 'music-playlist',
          title: 'Music Workout',
          thumbnailUrl: '',
          videoCount: 1,
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
          description: 'Oasis',
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
          description: 'Artist',
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
        id: 'player-hot-trending',
        title: 'Player Hot Trending',
        description: '',
        thumbnailUrl: '',
        isMusic: true,
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
        id: 'VL-player-video-charts',
        title: 'Player Video Charts',
        thumbnailUrl: '',
        videoCount: 20,
        itemsAreMusicVideos: true,
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

class _FakeCatalogRepository implements YouTubeCatalogRepository {
  final List<String?> playlistPageTokens = [];
  final List<YouTubeSearchSort> playlistSorts = [];

  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> loadChannelVideos({
    required String channelId,
    String? pageToken,
    String languageCode = 'de',
  }) async => const YouTubeSearchResult(
    videos: [
      YouTubeVideo(
        id: 'channel-video',
        title: 'Neuestes Channel-Video',
        description: 'Beschreibung',
        thumbnailUrl: '',
      ),
    ],
  );

  @override
  Future<YouTubeSearchResult> loadPlaylistVideos({
    required String playlistId,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    playlistPageTokens.add(pageToken);
    if (pageToken == 'player-playlist-next') {
      return const YouTubeSearchResult(
        videos: [
          YouTubeVideo(
            id: 'player-playlist-video-2',
            title: 'Playlist-Video 2',
            description: '',
            thumbnailUrl: '',
          ),
        ],
      );
    }
    return const YouTubeSearchResult(
      videos: [
        YouTubeVideo(
          id: 'player-playlist-video-1',
          title: 'Playlist-Video 1',
          description: '',
          thumbnailUrl: '',
        ),
      ],
      nextPageToken: 'player-playlist-next',
    );
  }

  @override
  Future<YouTubeCatalogPage<YouTubeChannelResult>> searchChannels({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) async => const YouTubeCatalogPage(
    items: [
      YouTubeChannelResult(
        id: 'channel-1',
        name: 'Flutter Channel',
        description: '',
        thumbnailUrl: '',
        videoCount: 1,
      ),
    ],
  );

  @override
  Future<YouTubeCatalogPage<YouTubePlaylistResult>> searchPlaylists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    playlistSorts.add(sort);
    return const YouTubeCatalogPage(
      items: [
        YouTubePlaylistResult(
          id: 'player-playlist',
          title: 'Training Playlist',
          thumbnailUrl: '',
          videoCount: 2,
        ),
      ],
    );
  }
}
