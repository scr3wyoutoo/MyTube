import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/services/youtube_music_discovery_response_parser.dart';

void main() {
  const parser = YouTubeMusicDiscoveryResponseParser();

  test('wartet alle direkt nutzbaren Explore-Listen vollständig ab', () async {
    final result = await parser.parseExplore(_exploreResponse());

    expect(result['new_releases'], isA<List>());
    expect(result['new_videos'], isA<List>());
    expect(result['trending'], isA<Map>());
    expect((result['trending'] as Map)['items'], isA<List>());
    expect(result['moods_and_genres'], isA<List>());

    final release = (result['new_releases'] as List).single as Map;
    final video = (result['new_videos'] as List).single as Map;
    final trending =
        ((result['trending'] as Map)['items'] as List).single as Map;
    final mood = (result['moods_and_genres'] as List).single as Map;

    expect(release['audioPlaylistId'], 'OLAK-release');
    expect(release['type'], 'Album');
    expect((release['artists'] as List).single['name'], 'Release Artist');
    expect(video['videoId'], 'new-video');
    expect(trending['videoId'], 'trending-video');
    expect(mood['params'], 'rock-params');
    expect([
      result['new_releases'],
      result['new_videos'],
      (result['trending'] as Map)['items'],
    ], everyElement(isNot(isA<Future<Object?>>())));
  });

  test('parst Charts typkorrekt samt Ländern, Videos und Künstlern', () async {
    final result = await parser.parseCharts(_chartsResponse(), country: 'DE');

    expect(result['countries'], isA<Map<String, dynamic>>());
    final countries = result['countries'] as Map<String, dynamic>;
    expect(countries['options'], ['DE', 'ZZ']);
    expect(result['videos'], isA<List>());
    expect(result['artists'], isA<List>());

    final videoChart = (result['videos'] as List).single as Map;
    final artist = (result['artists'] as List).single as Map;
    expect(videoChart['playlistId'], 'OLAK-chart');
    expect(artist['browseId'], 'UC-chart-artist');
    expect(artist['title'], 'Chart-Künstler');
    expect([
      result['videos'],
      result['artists'],
    ], everyElement(isNot(isA<Future<Object?>>())));
  });

  test(
    'filtert in gemischten Genre-Antworten Songs, Videos und Alben aus',
    () async {
      final result = await parser.parseGenrePlaylists(_mixedGenreResponse());

      expect(result.map((playlist) => playlist['playlistId']), [
        'PL-trending',
        'PL-community',
      ]);
      expect(result.map((playlist) => playlist['title']), [
        'Angesagte Playlist',
        'Community-Playlist',
      ]);
    },
  );

  test(
    'liefert auch für Stimmungen ausschließlich eindeutige Playlists',
    () async {
      final result = await parser.parseGenrePlaylists(_moodPlaylistResponse());

      expect(result.map((playlist) => playlist['playlistId']), [
        'PL-chill',
        'PL-focus',
        'PL-sleep',
      ]);
    },
  );
}

Map<String, dynamic> _mixedGenreResponse() {
  return _singleColumnResponse([
    _carouselSection(
      title: 'Musiktitel',
      contents: [
        {
          'musicResponsiveListItemRenderer': _responsiveSongRenderer(
            title: 'Pop-Song',
            videoId: 'pop-song',
            playlistId: 'RDAMVMpop-song',
          ),
        },
      ],
    ),
    _carouselSection(
      title: 'Angesagte Playlists',
      contents: [
        _playlistItem(title: 'Angesagte Playlist', browseId: 'VLPL-trending'),
        _playlistItem(
          title: 'Angesagte Playlist doppelt',
          browseId: 'VLPL-trending',
        ),
      ],
    ),
    _carouselSection(
      title: 'Musikvideos',
      contents: [_videoItem(title: 'Pop-Video', videoId: 'pop-video')],
    ),
    _carouselSection(
      title: 'Alben',
      contents: [_albumItem(title: 'Pop-Album', browseId: 'MPRE-pop-album')],
    ),
    _carouselSection(
      title: 'Community-Playlists',
      contents: [
        _playlistItem(title: 'Community-Playlist', browseId: 'VLPL-community'),
      ],
    ),
  ]);
}

Map<String, dynamic> _moodPlaylistResponse() {
  return _singleColumnResponse([
    _carouselSection(
      title: 'Chillig',
      contents: [
        _playlistItem(title: 'Chill', browseId: 'VLPL-chill'),
        _albumItem(title: 'Chill-Album', browseId: 'MPRE-chill'),
      ],
    ),
    {
      'gridRenderer': {
        'items': [_playlistItem(title: 'Fokus', browseId: 'VLPL-focus')],
      },
    },
    {
      'musicImmersiveCarouselShelfRenderer': {
        'contents': [_playlistItem(title: 'Schlafen', browseId: 'VLPL-sleep')],
      },
    },
  ]);
}

Map<String, dynamic> _playlistItem({
  required String title,
  required String browseId,
}) {
  return {
    'musicTwoRowItemRenderer': {
      'title': {
        'runs': [
          {
            'text': title,
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': browseId},
            },
          },
        ],
      },
      'subtitle': {
        'runs': [
          {'text': 'MyTube'},
        ],
      },
      'thumbnailRenderer': _thumbnailRenderer(),
    },
  };
}

Map<String, dynamic> _videoItem({
  required String title,
  required String videoId,
}) {
  return {
    'musicTwoRowItemRenderer': {
      'title': {
        'runs': [
          {'text': title},
        ],
      },
      'navigationEndpoint': {
        'watchEndpoint': {'videoId': videoId},
      },
      'subtitle': {
        'runs': [
          {'text': 'Video'},
        ],
      },
      'thumbnailRenderer': _thumbnailRenderer(),
    },
  };
}

Map<String, dynamic> _albumItem({
  required String title,
  required String browseId,
}) {
  return {
    'musicTwoRowItemRenderer': {
      'title': {
        'runs': [
          {
            'text': title,
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': browseId},
            },
          },
        ],
      },
      'subtitle': {
        'runs': [
          {'text': 'Album'},
        ],
      },
      'thumbnailRenderer': _thumbnailRenderer(),
    },
  };
}

Map<String, dynamic> _exploreResponse() {
  return _singleColumnResponse([
    _carouselSection(
      browseId: 'FEmusic_new_releases_albums',
      title: 'Neue Alben und Singles',
      contents: [
        {
          'musicTwoRowItemRenderer': {
            'title': {
              'runs': [
                {
                  'text': 'Neue Veröffentlichung',
                  'navigationEndpoint': {
                    'browseEndpoint': {'browseId': 'MPRE-release'},
                  },
                },
              ],
            },
            'subtitle': {
              'runs': [
                {'text': 'Album'},
                {'text': ' • '},
                {
                  'text': 'Release Artist',
                  'navigationEndpoint': {
                    'browseEndpoint': {'browseId': 'UC-release-artist'},
                  },
                },
              ],
            },
            'thumbnailOverlay': {
              'musicItemThumbnailOverlayRenderer': {
                'content': {
                  'musicPlayButtonRenderer': {
                    'playNavigationEndpoint': {
                      'watchPlaylistEndpoint': {'playlistId': 'OLAK-release'},
                    },
                  },
                },
              },
            },
            'thumbnailRenderer': _thumbnailRenderer(),
          },
        },
      ],
    ),
    _carouselSection(
      browseId: 'FEmusic_moods_and_genres',
      title: 'Stimmungen & Genres',
      contents: [
        {
          'musicNavigationButtonRenderer': {
            'buttonText': {
              'runs': [
                {'text': 'Rock'},
              ],
            },
            'clickCommand': {
              'browseEndpoint': {'params': 'rock-params'},
            },
          },
        },
      ],
    ),
    _carouselSection(
      browseId: 'VLOLAK-trending',
      title: 'Angesagt',
      contents: [
        {
          'musicResponsiveListItemRenderer': _responsiveSongRenderer(
            title: 'Trending Song',
            videoId: 'trending-video',
            playlistId: 'OLAK-trending',
          ),
        },
      ],
    ),
    _carouselSection(
      browseId: 'FEmusic_new_releases_videos',
      title: 'Neue Musikvideos',
      contents: [
        {
          'musicTwoRowItemRenderer': {
            'title': {
              'runs': [
                {'text': 'Neues Musikvideo'},
              ],
            },
            'subtitle': {
              'runs': [
                {
                  'text': 'Video-Künstler',
                  'navigationEndpoint': {
                    'browseEndpoint': {'browseId': 'UC-video-artist'},
                  },
                },
                {'text': ' • '},
                {'text': '1 Mio. Aufrufe'},
              ],
            },
            'navigationEndpoint': {
              'watchEndpoint': {'videoId': 'new-video'},
            },
            'thumbnailRenderer': _thumbnailRenderer(),
          },
        },
      ],
    ),
  ]);
}

Map<String, dynamic> _chartsResponse() {
  final response = _singleColumnResponse([
    {
      'musicShelfRenderer': {
        'subheaders': [
          {
            'musicSideAlignedItemRenderer': {
              'startItems': [
                {
                  'musicSortFilterButtonRenderer': {
                    'title': {
                      'runs': [
                        {'text': 'Deutschland'},
                      ],
                    },
                  },
                },
              ],
            },
          },
        ],
      },
    },
    _carouselSection(
      title: 'Video-Charts',
      contents: [
        {
          'musicTwoRowItemRenderer': {
            'title': {
              'runs': [
                {
                  'text': 'Top 20 Deutschland',
                  'navigationEndpoint': {
                    'browseEndpoint': {'browseId': 'VLOLAK-chart'},
                  },
                },
              ],
            },
            'thumbnailRenderer': _thumbnailRenderer(),
          },
        },
      ],
    ),
    _carouselSection(
      title: 'Top-Künstler',
      contents: [
        {
          'musicResponsiveListItemRenderer': {
            'flexColumns': [
              _flexColumn([
                {'text': 'Chart-Künstler'},
              ]),
              _flexColumn([
                {'text': '1 Mio. Abonnenten'},
              ]),
            ],
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'UC-chart-artist'},
            },
            'thumbnail': {
              'musicThumbnailRenderer': {
                'thumbnail': {
                  'thumbnails': [_thumbnail()],
                },
              },
            },
            'customIndexColumn': {
              'musicCustomIndexColumnRenderer': {
                'text': {
                  'runs': [
                    {'text': '1'},
                  ],
                },
                'icon': {'iconType': 'ARROW_CHART_NEUTRAL'},
              },
            },
          },
        },
      ],
    ),
  ]);
  response['frameworkUpdates'] = {
    'entityBatchUpdate': {
      'mutations': [
        {
          'payload': {'musicForm': <String, dynamic>{}},
        },
        {
          'payload': {
            'musicFormBooleanChoice': {'opaqueToken': 'DE', 'selected': true},
          },
        },
        {
          'payload': {
            'musicFormBooleanChoice': {'opaqueToken': 'ZZ', 'selected': false},
          },
        },
      ],
    },
  };
  return response;
}

Map<String, dynamic> _singleColumnResponse(
  List<Map<String, dynamic>> sections,
) {
  return {
    'contents': {
      'singleColumnBrowseResultsRenderer': {
        'tabs': [
          {
            'tabRenderer': {
              'content': {
                'sectionListRenderer': {'contents': sections},
              },
            },
          },
        ],
      },
    },
  };
}

Map<String, dynamic> _carouselSection({
  String? browseId,
  required String title,
  required List<Map<String, dynamic>> contents,
}) {
  return {
    'musicCarouselShelfRenderer': {
      'header': {
        'musicCarouselShelfBasicHeaderRenderer': {
          'title': {
            'runs': [
              {
                'text': title,
                if (browseId != null)
                  'navigationEndpoint': {
                    'browseEndpoint': {'browseId': browseId},
                  },
              },
            ],
          },
        },
      },
      'contents': contents,
    },
  };
}

Map<String, dynamic> _responsiveSongRenderer({
  required String title,
  required String videoId,
  required String playlistId,
}) {
  return {
    'flexColumns': [
      _flexColumn([
        {
          'text': title,
          'navigationEndpoint': {
            'watchEndpoint': {'videoId': videoId},
          },
        },
      ]),
      _flexColumn([
        {
          'text': 'Trending-Künstler',
          'navigationEndpoint': {
            'browseEndpoint': {'browseId': 'UC-trending-artist'},
          },
        },
        {'text': ' • '},
        {'text': '1 Mio. Aufrufe'},
      ]),
    ],
    'overlay': {
      'musicItemThumbnailOverlayRenderer': {
        'content': {
          'musicPlayButtonRenderer': {
            'playNavigationEndpoint': {
              'watchEndpoint': {
                'videoId': videoId,
                'playlistId': playlistId,
                'watchEndpointMusicSupportedConfigs': {
                  'watchEndpointMusicConfig': {
                    'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV',
                  },
                },
              },
            },
          },
        },
      },
    },
    'thumbnail': {
      'musicThumbnailRenderer': {
        'thumbnail': {
          'thumbnails': [_thumbnail()],
        },
      },
    },
  };
}

Map<String, dynamic> _flexColumn(List<Map<String, dynamic>> runs) {
  return {
    'musicResponsiveListItemFlexColumnRenderer': {
      'text': {'runs': runs},
    },
  };
}

Map<String, dynamic> _thumbnailRenderer() {
  return {
    'musicThumbnailRenderer': {
      'thumbnail': {
        'thumbnails': [_thumbnail()],
      },
    },
  };
}

Map<String, dynamic> _thumbnail() {
  return {'url': 'https://example.com/cover.jpg', 'width': 544, 'height': 544};
}
