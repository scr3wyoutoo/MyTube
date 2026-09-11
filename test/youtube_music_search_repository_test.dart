import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/services/youtube_music_search_repository_io.dart';

void main() {
  test('wandelt Music-Songs um und stellt sie in 20er-Seiten bereit', () async {
    final source = _FakeMusicSearchSource(_rawSongs(45));
    final repository = YouTubeMusicSearchRepository(source: source);

    final firstPage = await repository.searchVideos(query: 'Testmusik');
    final secondPage = await repository.searchVideos(
      query: 'Testmusik',
      pageToken: firstPage.nextPageToken,
    );
    final thirdPage = await repository.searchVideos(
      query: 'Testmusik',
      pageToken: secondPage.nextPageToken,
    );

    expect(firstPage.videos, hasLength(20));
    expect(firstPage.videos.first.title, 'Song 0');
    expect(firstPage.videos.first.description, 'Künstler 0 • Album 0 • 3:00');
    expect(firstPage.videos.first.duration, const Duration(minutes: 3));
    expect(
      firstPage.videos.first.thumbnailUrl,
      'https://example.com/high-0.jpg',
    );
    expect(secondPage.videos, hasLength(20));
    expect(thirdPage.videos, hasLength(5));
    expect(thirdPage.nextPageToken, isNull);
    expect(source.requestedLimits, [31, 51]);
    expect(source.languageCodes, ['de', 'de']);

    repository.close();
    expect(source.wasClosed, isTrue);
  });

  test('reicht die englische Profilsprache an Music weiter', () async {
    final source = _FakeMusicSearchSource(_rawSongs(1));
    final repository = YouTubeMusicSearchRepository(source: source);

    await repository.searchVideos(query: 'Test', languageCode: 'en');

    expect(source.languageCodes, ['en']);
  });

  test('ignoriert nicht verfügbare und ungültige Music-Treffer', () async {
    final source = _FakeMusicSearchSource([
      ..._rawSongs(1),
      {'videoId': 'blocked', 'title': 'Gesperrt', 'isAvailable': false},
      {'title': 'Ohne Video-ID'},
      'kein Ergebnisobjekt',
    ]);
    final repository = YouTubeMusicSearchRepository(source: source);

    final result = await repository.searchVideos(query: 'Test');

    expect(result.videos.map((video) => video.id), ['music-0']);
    expect(result.nextPageToken, isNull);
  });

  test('sucht Künstler und Playlists und lädt deren Songs', () async {
    final source = _FakeMusicSearchSource(
      const [],
      artistResults: const [
        {
          'browseId': 'artist-1',
          'artist': 'Oasis',
          'subscribers': '4 Mio.',
          'thumbnails': [],
        },
      ],
      playlistResults: const [
        {
          'browseId': 'VLplaylist-1',
          'title': 'Oasis Essentials',
          'itemCount': '25 songs',
          'thumbnails': [],
        },
      ],
      artistSongs: _rawSongs(2),
      playlistSongs: _rawSongs(3),
    );
    final repository = YouTubeMusicSearchRepository(source: source);

    final artists = await repository.searchArtists(query: 'Oasis');
    final playlists = await repository.searchMusicPlaylists(query: 'Oasis');
    final artistSongs = await repository.loadArtistSongs(
      artistId: artists.items.single.id,
    );
    final playlistSongs = await repository.loadMusicPlaylistSongs(
      playlistId: playlists.items.single.id,
    );

    expect(artists.items.single.name, 'Oasis');
    expect(playlists.items.single.videoCount, 25);
    expect(artistSongs.videos, hasLength(2));
    expect(playlistSongs.videos, hasLength(3));
    expect(artistSongs.videos.every((song) => song.isMusic), isTrue);
    expect(
      YouTubeVideo.fromJson(artistSongs.videos.first.toJson())?.isMusic,
      isTrue,
    );
    expect(
      YouTubeVideo.fromJson(artistSongs.videos.first.toJson())?.duration,
      const Duration(minutes: 3),
    );
    expect(source.openedArtistIds, ['artist-1']);
    expect(source.openedPlaylistIds, ['VLplaylist-1']);
  });

  test('wandelt Explore-Inhalte robust in Hot-Music-Modelle um', () async {
    final discovery = _FakeMusicDiscoverySource(
      explore: {
        'trending': {
          'items': [
            ..._rawSongs(2),
            {
              'videoId': 'podcast',
              'title': 'Podcast',
              'videoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
            },
          ],
        },
        'new_videos': _rawSongs(1),
        'new_releases': [
          {
            'title': 'Neues Album',
            'audioPlaylistId': 'OLAK-album',
            'thumbnails': const [],
            'artists': const [
              {'name': 'Album Artist', 'id': 'UC-album-artist'},
              {'name': 'Gast Artist', 'id': 'UC-guest-artist'},
            ],
            'type': 'Album',
          },
        ],
        'moods_and_genres': const [
          {'title': 'Rock', 'params': 'rock-token'},
        ],
      },
    );
    final repository = YouTubeMusicSearchRepository(
      source: _FakeMusicSearchSource(const []),
      discoverySource: discovery,
    );

    final result = await repository.loadExplore();

    expect(result.trending.map((video) => video.id), ['music-0', 'music-1']);
    expect(result.trending.every((video) => video.isMusic), isTrue);
    expect(result.trending.every((video) => !video.isMusicVideo), isTrue);
    expect(result.newVideos.single.id, 'music-0');
    expect(result.newVideos.single.isMusic, isTrue);
    expect(result.newVideos.single.isMusicVideo, isTrue);
    expect(result.newVideos.single.hasVideo, isTrue);
    expect(result.newReleases.single.id, 'OLAK-album');
    expect(result.newReleases.single.creatorName, 'Album Artist, Gast Artist');
    expect(result.newReleases.single.typeLabel, 'Album');
    expect(result.moodsAndGenres.single.params, 'rock-token');
  });

  test('normalisiert bekannte und unbekannte Neuerscheinungstypen', () async {
    final discovery = _FakeMusicDiscoverySource(
      explore: {
        'new_releases': const [
          {'title': 'Neue EP', 'audioPlaylistId': 'OLAK-ep', 'type': 'EP'},
          {
            'title': 'Neue Single',
            'audioPlaylistId': 'OLAK-single',
            'type': 'Single',
          },
          {
            'title': 'Unbekannter Typ',
            'audioPlaylistId': 'OLAK-unknown',
            'type': 'Mixtape',
          },
        ],
      },
    );
    final repository = YouTubeMusicSearchRepository(
      source: _FakeMusicSearchSource(const []),
      discoverySource: discovery,
    );

    final result = await repository.loadExplore();

    expect(result.newReleases.map((item) => item.typeLabel), [
      'EP',
      'Single',
      'Veröffentlichung',
    ]);
  });

  test('liest valide Chart-Länder, Playlists und Künstler', () async {
    final discovery = _FakeMusicDiscoverySource(
      charts: {
        'countries': {
          'options': ['DE', 'US', 'ZZ'],
        },
        'videos': const [
          {
            'title': 'Top Music Videos Deutschland',
            'playlistId': 'PL-chart',
            'thumbnails': [],
          },
        ],
        'artists': const [
          {'title': 'Chart Artist', 'browseId': 'UC-artist', 'thumbnails': []},
        ],
      },
    );
    final repository = YouTubeMusicSearchRepository(
      source: _FakeMusicSearchSource(const []),
      discoverySource: discovery,
    );

    final result = await repository.loadCharts(countryCode: 'de');

    expect(result.countryCode, 'DE');
    expect(result.countryCodes, ['DE', 'US', 'ZZ']);
    expect(result.videos.single.id, 'PL-chart');
    expect(result.videos.single.itemsAreMusicVideos, isTrue);
    expect(result.artists.single.id, 'UC-artist');
    expect(result.artists.single.isMusic, isTrue);
  });

  test('lädt Genre-Ebenen und cached Discovery-Antworten', () async {
    final discovery = _FakeMusicDiscoverySource(
      genreSections: const {
        'Stimmungen und Momente': [
          {'title': 'Chill', 'params': 'chill-token'},
        ],
        'Genres': [
          {'title': 'Rock', 'params': 'rock-token'},
        ],
      },
      genrePlaylists: const [
        {'title': 'Rock Classics', 'playlistId': 'PL-rock', 'thumbnails': []},
      ],
    );
    final repository = YouTubeMusicSearchRepository(
      source: _FakeMusicSearchSource(const []),
      discoverySource: discovery,
    );

    final firstSections = await repository.loadGenreSections();
    final secondSections = await repository.loadGenreSections();
    final firstPlaylists = await repository.loadGenrePlaylists(
      params: 'rock-token',
    );
    final secondPlaylists = await repository.loadGenrePlaylists(
      params: 'rock-token',
    );

    expect(firstSections, same(secondSections));
    expect(firstSections.map((section) => section.title), [
      'Stimmungen und Momente',
      'Genres',
    ]);
    expect(firstPlaylists, same(secondPlaylists));
    expect(firstPlaylists.single.id, 'PL-rock');
    expect(discovery.genreSectionLoads, 1);
    expect(discovery.genrePlaylistLoads, 1);
  });
}

List<Object?> _rawSongs(int count) {
  return List<Object?>.generate(count, (index) {
    return <String, Object?>{
      'videoId': 'music-$index',
      'title': 'Song $index',
      'artists': [
        {'name': 'Künstler $index'},
      ],
      'album': {'name': 'Album $index'},
      'duration': '3:${index.toString().padLeft(2, '0')}',
      'isAvailable': true,
      'isExplicit': false,
      'thumbnails': [
        {
          'url': 'https://example.com/low-$index.jpg',
          'width': 120,
          'height': 120,
        },
        {
          'url': 'https://example.com/high-$index.jpg',
          'width': 544,
          'height': 544,
        },
      ],
    };
  });
}

class _FakeMusicSearchSource implements YouTubeMusicSearchSource {
  _FakeMusicSearchSource(
    this.results, {
    this.artistResults = const [],
    this.playlistResults = const [],
    this.artistSongs = const [],
    this.playlistSongs = const [],
  });

  final List<Object?> results;
  final List<Object?> artistResults;
  final List<Object?> playlistResults;
  final List<Object?> artistSongs;
  final List<Object?> playlistSongs;
  final List<int> requestedLimits = [];
  final List<String> languageCodes = [];
  final List<String> openedArtistIds = [];
  final List<String> openedPlaylistIds = [];
  bool wasClosed = false;

  @override
  Future<List<Object?>> searchSongs(
    String query, {
    required int limit,
    required String languageCode,
  }) async {
    requestedLimits.add(limit);
    languageCodes.add(languageCode);
    return results.take(limit).toList(growable: false);
  }

  @override
  Future<List<Object?>> searchArtists(
    String query, {
    required int limit,
    required String languageCode,
  }) async => artistResults.take(limit).toList(growable: false);

  @override
  Future<List<Object?>> searchPlaylists(
    String query, {
    required int limit,
    required String languageCode,
  }) async => playlistResults.take(limit).toList(growable: false);

  @override
  Future<List<Object?>> loadArtistSongs(
    String artistId, {
    required int limit,
    required String languageCode,
  }) async {
    openedArtistIds.add(artistId);
    return artistSongs.take(limit).toList(growable: false);
  }

  @override
  Future<List<Object?>> loadPlaylistSongs(
    String playlistId, {
    required int limit,
    required String languageCode,
  }) async {
    openedPlaylistIds.add(playlistId);
    return playlistSongs.take(limit).toList(growable: false);
  }

  @override
  void close() => wasClosed = true;
}

class _FakeMusicDiscoverySource implements YouTubeMusicDiscoverySource {
  _FakeMusicDiscoverySource({
    this.explore = const {},
    this.charts = const {},
    this.genreSections = const {},
    this.genrePlaylists = const [],
  });

  final Map<String, Object?> explore;
  final Map<String, Object?> charts;
  final Map<String, Object?> genreSections;
  final List<Object?> genrePlaylists;
  int genreSectionLoads = 0;
  int genrePlaylistLoads = 0;

  @override
  Future<Map<String, Object?>> loadExplore({
    required String languageCode,
  }) async => explore;

  @override
  Future<Map<String, Object?>> loadCharts({
    required String countryCode,
    required String languageCode,
  }) async => charts;

  @override
  Future<Map<String, Object?>> loadGenreSections({
    required String languageCode,
  }) async {
    genreSectionLoads++;
    return genreSections;
  }

  @override
  Future<List<Object?>> loadGenrePlaylists({
    required String params,
    required String languageCode,
  }) async {
    genrePlaylistLoads++;
    return genrePlaylists;
  }
}
