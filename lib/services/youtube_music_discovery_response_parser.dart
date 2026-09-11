import 'dart:math';

import 'package:ytmusicapi_dart/mixins/charts.dart' as music_charts;
import 'package:ytmusicapi_dart/navigation.dart';
import 'package:ytmusicapi_dart/parsers/browsing.dart' as music_browsing;
import 'package:ytmusicapi_dart/parsers/explore.dart' as music_explore;
import 'package:ytmusicapi_dart/type_alias.dart';

/// Local compatibility parser for the anonymous YouTube Music discovery
/// endpoints.
///
/// `ytmusicapi_dart 2.4.1` returns unawaited `Future<List>` values from
/// `getExplore` and `getCharts`. Its charts implementation additionally casts
/// an untyped empty map to `JsonMap`. Keeping the workaround here avoids
/// modifying the global Pub cache and makes it independently testable.
class YouTubeMusicDiscoveryResponseParser {
  const YouTubeMusicDiscoveryResponseParser();

  Future<JsonMap> parseExplore(JsonMap response) async {
    final rawSections = nav(response, [...SINGLE_COLUMN_TAB, ...SECTION_LIST]);
    if (rawSections is! List) {
      throw const FormatException(
        'YouTube Music Explore enthält keine Abschnittsliste.',
      );
    }

    final explore = <String, dynamic>{};
    for (final rawSection in rawSections) {
      if (rawSection is! JsonMap) {
        continue;
      }
      final browseId = nav(rawSection, [
        ...CAROUSEL,
        ...CAROUSEL_TITLE,
        ...NAVIGATION_BROWSE_ID,
      ], nullIfAbsent: true);
      if (browseId is! String) {
        continue;
      }
      final rawContents = nav(
        rawSection,
        CAROUSEL_CONTENTS,
        nullIfAbsent: true,
      );
      if (rawContents is! List) {
        continue;
      }
      final contents = List<JsonMap>.from(rawContents);

      switch (browseId) {
        case 'FEmusic_new_releases_albums':
          explore['new_releases'] = await music_browsing.parseContentList(
            contents,
            music_browsing.parseAlbum,
          );
        case 'FEmusic_moods_and_genres':
          explore['moods_and_genres'] = [
            for (final genre in contents)
              {
                'title': nav(genre, CATEGORY_TITLE),
                'params': nav(genre, CATEGORY_PARAMS),
              },
          ];
        case 'FEmusic_top_non_music_audio_episodes':
          explore['top_episodes'] = await music_browsing.parseContentList(
            contents,
            music_explore.parseChartEpisode,
            key: MMRIR,
          );
        case 'FEmusic_new_releases_videos':
          explore['new_videos'] = await music_browsing.parseContentList(
            contents,
            music_browsing.parseVideo,
          );
        default:
          if (browseId.startsWith('VLPL')) {
            explore['top_songs'] = {
              'playlist': browseId,
              'items': await music_browsing.parseContentList(
                contents,
                music_explore.parseChartSong,
                key: MRLIR,
              ),
            };
          } else if (browseId.startsWith('VLOLA')) {
            explore['trending'] = {
              'playlist': browseId,
              'items': await music_browsing.parseContentList(
                contents,
                music_explore.parseTrendingItem,
                key: MRLIR,
              ),
            };
          }
      }
    }
    return explore;
  }

  Future<JsonMap> parseCharts(
    JsonMap response, {
    required String country,
  }) async {
    final rawSections = nav(response, [...SINGLE_COLUMN_TAB, ...SECTION_LIST]);
    if (rawSections is! List || rawSections.isEmpty) {
      throw const FormatException(
        'YouTube Music Charts enthält keine Abschnittsliste.',
      );
    }
    final sections = List<JsonMap>.from(rawSections);
    final charts = <String, dynamic>{'countries': <String, dynamic>{}};
    final countries = charts['countries'] as JsonMap;

    final menu = nav(sections.first, [
      ...MUSIC_SHELF,
      'subheaders',
      0,
      'musicSideAlignedItemRenderer',
      'startItems',
      0,
      'musicSortFilterButtonRenderer',
    ]);
    countries['selected'] = nav(menu, TITLE);
    final rawMutations = nav(response, FRAMEWORK_MUTATIONS, nullIfAbsent: true);
    countries['options'] = [
      if (rawMutations is List)
        for (final mutation in rawMutations)
          nav(mutation, [
            'payload',
            'musicFormBooleanChoice',
            'opaqueToken',
          ], nullIfAbsent: true),
    ].whereType<String>().toList(growable: false);

    final carousels = <List<JsonMap>>[];
    for (final section in sections.skip(1)) {
      final rawContents = nav(section, CAROUSEL_CONTENTS, nullIfAbsent: true);
      if (rawContents is List && rawContents.isNotEmpty) {
        carousels.add(List<JsonMap>.from(rawContents));
      }
    }
    final playlistCarousels = carousels
        .where(music_charts.isPlaylistCarousel)
        .toList(growable: false);
    final artistCarousels = carousels
        .where(music_charts.isArtistCarousel)
        .toList(growable: false);

    final playlistNames = <String>['videos'];
    final extraCategory = music_charts.COUNTRY_EXTRA_CATEGORY[country];
    if (extraCategory != null) {
      playlistNames.add(extraCategory);
    }
    if (playlistCarousels.length > playlistNames.length) {
      playlistNames
        ..clear()
        ..addAll(['daily', 'weekly', ?extraCategory]);
    }

    final playlistCount = min(playlistNames.length, playlistCarousels.length);
    for (var index = 0; index < playlistCount; index++) {
      charts[playlistNames[index]] = await music_browsing.parseContentList(
        playlistCarousels[index],
        music_explore.parseChartPlaylist,
      );
    }
    if (artistCarousels.isNotEmpty) {
      charts['artists'] = await music_browsing.parseContentList(
        artistCarousels.first,
        music_explore.parseChartArtist,
        key: MRLIR,
      );
    }
    return charts;
  }

  /// Parses the contents behind a YouTube Music mood or genre category.
  ///
  /// These pages are heterogeneous: depending on the selected category,
  /// YouTube can return songs, playlists, videos and albums in adjacent
  /// sections. The app's genre detail level intentionally exposes playlists
  /// only. A playlist browse target always uses the `VL` prefix; checking that
  /// structural identifier keeps the filter independent of localized titles.
  Future<List<JsonMap>> parseGenrePlaylists(JsonMap response) async {
    final rawSections = nav(response, [
      ...SINGLE_COLUMN_TAB,
      ...SECTION_LIST,
    ], nullIfAbsent: true);
    if (rawSections is! List) {
      throw const FormatException(
        'YouTube Music Genres enthalten keine Abschnittsliste.',
      );
    }

    final playlists = <JsonMap>[];
    final knownPlaylistIds = <String>{};
    for (final rawSection in rawSections) {
      if (rawSection is! JsonMap) {
        continue;
      }
      final rawContents = _genreSectionContents(rawSection);
      if (rawContents is! List) {
        continue;
      }
      for (final rawItem in rawContents) {
        if (rawItem is! JsonMap || rawItem[MTRIR] is! JsonMap) {
          continue;
        }
        final renderer = rawItem[MTRIR] as JsonMap;
        final browseId = nav(renderer, [
          ...TITLE,
          ...NAVIGATION_BROWSE_ID,
        ], nullIfAbsent: true);
        if (browseId is! String ||
            browseId.length <= 2 ||
            !browseId.startsWith('VL')) {
          continue;
        }

        try {
          final playlist = music_browsing.parsePlaylist(renderer);
          final playlistId = playlist['playlistId'];
          if (playlistId is String &&
              playlistId.isNotEmpty &&
              knownPlaylistIds.add(playlistId)) {
            playlists.add(playlist);
          }
        } on Object {
          // A malformed external item must not hide valid playlists in later
          // sections of the same mood or genre response.
          continue;
        }
      }
    }
    return List<JsonMap>.unmodifiable(playlists);
  }

  Object? _genreSectionContents(JsonMap section) {
    if (section.containsKey('gridRenderer')) {
      return nav(section, GRID_ITEMS, nullIfAbsent: true);
    }
    if (section.containsKey('musicCarouselShelfRenderer')) {
      return nav(section, CAROUSEL_CONTENTS, nullIfAbsent: true);
    }
    if (section.containsKey('musicImmersiveCarouselShelfRenderer')) {
      return nav(section, const [
        'musicImmersiveCarouselShelfRenderer',
        'contents',
      ], nullIfAbsent: true);
    }
    return null;
  }
}
