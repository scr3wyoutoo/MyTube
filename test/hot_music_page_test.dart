import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/hot_music.dart';
import 'package:flutter_browser_app/models/youtube_catalog_item.dart';
import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/screens/hot_music_page.dart';
import 'package:flutter_browser_app/services/profile_controller.dart';
import 'package:flutter_browser_app/services/youtube_music_discovery_repository.dart';

void main() {
  test('rotiert die Hot-Music-Queue um das gewählte Medium', () {
    final videos = List.generate(
      4,
      (index) => YouTubeVideo(
        id: '$index',
        title: 'Song $index',
        description: '',
        thumbnailUrl: '',
        isMusic: true,
      ),
    );

    expect(rotateHotMusicQueue(videos, videos[2]).map((video) => video.id), [
      '2',
      '3',
      '0',
      '1',
    ]);
  });

  testWidgets('filtert Explore lokal und zeigt vollständige Songaktionen', (
    tester,
  ) async {
    final repository = _FakeDiscoveryRepository();
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    YouTubeVideo? selected;
    List<YouTubeVideo>? selectedQueue;

    await tester.pumpWidget(
      _HotMusicTestApp(
        repository: repository,
        profiles: profiles,
        onVideoSelected: (video, queue, _) {
          selected = video;
          selectedQueue = queue;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.exploreLoads, 1);
    expect(find.text('Trending Song'), findsOneWidget);
    expect(find.text('Entdecken: Trending'), findsNothing);
    expect(find.text('Trending'), findsNothing);
    expect(
      find.byKey(const Key('test-hot-filter-heading-Trending Songs')),
      findsOneWidget,
    );
    expect(find.text('Trending Songs'), findsOneWidget);
    expect(
      find.byKey(const Key('search-favorite-trending-song')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('search-add-playlist-trending-song')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('search-info-trending-song')), findsOneWidget);

    await tester.tap(find.text('Trending Song'));
    expect(selected?.id, 'trending-song');
    expect(selectedQueue?.single.id, 'trending-song');

    await tester.tap(find.byKey(const Key('test-hot-section-explore')));
    await tester.pumpAndSettle();
    expect(find.text('Trending Songs'), findsNWidgets(2));
    expect(
      find.byKey(const Key('test-hot-explore-filter-moodsAndGenres')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const Key('test-hot-explore-filter-newVideos')),
    );
    await tester.pumpAndSettle();

    expect(repository.exploreLoads, 1);
    expect(find.text('Neues Musikvideo'), findsOneWidget);
    expect(find.text('Trending Song'), findsNothing);
    expect(
      find.byKey(const Key('test-hot-filter-heading-Neue Videos')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('test-hot-section-explore')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('test-hot-explore-filter-newReleases')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Neues Album'), findsOneWidget);
    expect(find.text('Album Artist'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-type-badge-OLAK-new')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('test-hot-filter-heading-Neuerscheinungen')),
      findsOneWidget,
    );
  });

  testWidgets('lädt Charts nach valider Länderwahl neu', (tester) async {
    final repository = _FakeDiscoveryRepository();
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    YouTubePlaylistResult? selectedPlaylist;
    await tester.pumpWidget(
      _HotMusicTestApp(
        repository: repository,
        profiles: profiles,
        onPlaylistSelected: (playlist) => selectedPlaylist = playlist,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('test-hot-section-charts')));
    await tester.pumpAndSettle();
    expect(repository.chartCountries, ['DE']);
    expect(find.text('Deutschland Charts'), findsOneWidget);
    expect(find.text('Charts: Videos'), findsNothing);
    expect(
      find.byKey(const Key('test-hot-filter-heading-Videos')),
      findsOneWidget,
    );
    await tester.tap(find.text('Deutschland Charts'));
    expect(selectedPlaylist?.itemsAreMusicVideos, isTrue);

    await tester.tap(find.byKey(const Key('test-hot-country-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-hot-country-US')));
    await tester.pumpAndSettle();

    expect(repository.chartCountries, ['DE', 'US']);
    expect(find.text('USA Charts'), findsOneWidget);

    await tester.tap(find.byKey(const Key('test-hot-section-charts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-hot-charts-filter-artists')));
    await tester.pumpAndSettle();
    expect(find.text('Chart Artist'), findsOneWidget);
    expect(
      find.byKey(const Key('test-hot-filter-heading-Künstler')),
      findsOneWidget,
    );
  });

  testWidgets('öffnet Genre-Playlists auf einer internen Ebene', (
    tester,
  ) async {
    final repository = _FakeDiscoveryRepository();
    final profiles = ProfileController.inMemory();
    await profiles.createProfile('Alex');
    YouTubePlaylistResult? selectedPlaylist;
    await tester.pumpWidget(
      _HotMusicTestApp(
        repository: repository,
        profiles: profiles,
        onPlaylistSelected: (playlist) => selectedPlaylist = playlist,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('test-hot-section-genres')));
    await tester.pumpAndSettle();
    expect(find.text('Stimmungen und Momente'), findsOneWidget);
    expect(find.text('Chill'), findsOneWidget);
    expect(find.text('Rock'), findsNothing);

    await tester.tap(find.byKey(const Key('test-hot-section-genres')));
    await tester.pumpAndSettle();
    expect(find.text('Stimmungen'), findsOneWidget);
    expect(find.text('Genres'), findsWidgets);
    await tester.tap(find.byKey(const Key('test-hot-genres-filter-genres')));
    await tester.pumpAndSettle();
    expect(find.text('Stimmungen und Momente'), findsNothing);
    expect(find.text('Chill'), findsNothing);
    expect(find.text('Rock'), findsOneWidget);

    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    expect(repository.genreParams, ['rock-token']);
    expect(find.byKey(const Key('hot-music-genre-back')), findsOneWidget);
    expect(find.text('Rock Classics'), findsOneWidget);

    await tester.tap(find.text('Rock Classics'));
    expect(selectedPlaylist?.id, 'PL-rock');

    await tester.tap(find.byKey(const Key('hot-music-genre-back')));
    await tester.pumpAndSettle();
    expect(find.text('Stimmungen und Momente'), findsNothing);
    expect(find.text('Rock'), findsOneWidget);

    await tester.tap(find.byKey(const Key('test-hot-section-genres')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-hot-genres-filter-moods')));
    await tester.pumpAndSettle();
    expect(find.text('Stimmungen und Momente'), findsOneWidget);
    expect(find.text('Chill'), findsOneWidget);
    expect(find.text('Rock'), findsNothing);
  });
}

class _HotMusicTestApp extends StatelessWidget {
  const _HotMusicTestApp({
    required this.repository,
    required this.profiles,
    this.onVideoSelected,
    this.onPlaylistSelected,
  });

  final YouTubeMusicDiscoveryRepository repository;
  final ProfileController profiles;
  final HotMusicVideoSelected? onVideoSelected;
  final HotMusicPlaylistSelected? onPlaylistSelected;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: HotMusicPage(
          active: true,
          repository: repository,
          profileController: profiles,
          onVideoSelected: onVideoSelected ?? (_, _, _) {},
          onPlaylistSelected: onPlaylistSelected ?? (_) {},
          onArtistSelected: (_) {},
          onToggleVideoFavorite: (_) async {},
          onAddVideoToPlaylist: (_) async {},
          onImportPlaylist: (_) async {},
          onToggleArtistFavorite: (_) async {},
          keyPrefix: 'test-hot',
        ),
      ),
    );
  }
}

class _FakeDiscoveryRepository implements YouTubeMusicDiscoveryRepository {
  int exploreLoads = 0;
  final List<String> chartCountries = [];
  final List<String> genreParams = [];

  @override
  Future<HotMusicExploreResult> loadExplore({
    String languageCode = 'de',
  }) async {
    exploreLoads++;
    return const HotMusicExploreResult(
      trending: [
        YouTubeVideo(
          id: 'trending-song',
          title: 'Trending Song',
          description: 'Beschreibung',
          thumbnailUrl: '',
          isMusic: true,
        ),
      ],
      newVideos: [
        YouTubeVideo(
          id: 'new-video',
          title: 'Neues Musikvideo',
          description: '',
          thumbnailUrl: '',
          isMusic: true,
          isMusicVideo: true,
        ),
      ],
      newReleases: [
        YouTubePlaylistResult(
          id: 'OLAK-new',
          title: 'Neues Album',
          thumbnailUrl: '',
          videoCount: 0,
          creatorName: 'Album Artist',
          typeLabel: 'Album',
        ),
      ],
      moodsAndGenres: [HotMusicCategory(title: 'Chill', params: 'chill-token')],
    );
  }

  @override
  Future<HotMusicChartsResult> loadCharts({
    required String countryCode,
    String languageCode = 'de',
  }) async {
    chartCountries.add(countryCode);
    return HotMusicChartsResult(
      countryCode: countryCode,
      countryCodes: const ['DE', 'US', 'ZZ'],
      videos: [
        YouTubePlaylistResult(
          id: 'PL-$countryCode',
          title: countryCode == 'US' ? 'USA Charts' : 'Deutschland Charts',
          thumbnailUrl: '',
          videoCount: 50,
          itemsAreMusicVideos: true,
        ),
      ],
      artists: const [
        YouTubeChannelResult(
          id: 'UC-chart',
          name: 'Chart Artist',
          description: '',
          thumbnailUrl: '',
          videoCount: 0,
          isMusic: true,
        ),
      ],
    );
  }

  @override
  Future<List<HotMusicGenreSection>> loadGenreSections({
    String languageCode = 'de',
  }) async => const [
    HotMusicGenreSection(
      title: 'Stimmungen und Momente',
      categories: [HotMusicCategory(title: 'Chill', params: 'chill-token')],
    ),
    HotMusicGenreSection(
      title: 'Genres',
      categories: [HotMusicCategory(title: 'Rock', params: 'rock-token')],
    ),
  ];

  @override
  Future<List<YouTubePlaylistResult>> loadGenrePlaylists({
    required String params,
    String languageCode = 'de',
  }) async {
    genreParams.add(params);
    return const [
      YouTubePlaylistResult(
        id: 'PL-rock',
        title: 'Rock Classics',
        thumbnailUrl: '',
        videoCount: 20,
      ),
    ];
  }
}
