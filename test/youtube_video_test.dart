import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/services/youtube_explode_catalog_repository.dart';

void main() {
  test('speichert den Music-Video-Typ dauerhaft', () {
    const musicVideo = YouTubeVideo(
      id: 'music-video',
      title: 'Music Video',
      description: '',
      thumbnailUrl: '',
      isMusic: true,
      isMusicVideo: true,
    );

    final restored = YouTubeVideo.fromJson(musicVideo.toJson());

    expect(restored?.isMusic, isTrue);
    expect(restored?.isMusicVideo, isTrue);
    expect(restored?.hasVideo, isTrue);
    expect(restored?.isAudioOnlyMusic, isFalse);
  });

  test('speichert die kanonische Mediendauer dauerhaft', () {
    const song = YouTubeVideo(
      id: 'song-with-duration',
      title: 'Song',
      description: '',
      thumbnailUrl: '',
      duration: Duration(minutes: 2, seconds: 33),
      isMusic: true,
    );

    final restored = YouTubeVideo.fromJson(song.toJson());

    expect(restored?.duration, const Duration(minutes: 2, seconds: 33));
    expect(song.asMusicVideo().duration, song.duration);
  });

  test('behandelt alte Music-Eintraege ohne neue Flag weiter als Audio', () {
    final restored = YouTubeVideo.fromJson(const {
      'id': 'legacy-song',
      'title': 'Legacy Song',
      'isMusic': true,
    });

    expect(restored?.isMusicVideo, isFalse);
    expect(restored?.hasVideo, isFalse);
    expect(restored?.isAudioOnlyMusic, isTrue);
  });

  test('klassifiziert eine komplette Ergebnisseite als Music-Videos', () {
    const result = YouTubeSearchResult(
      videos: [
        YouTubeVideo(
          id: 'chart-video',
          title: 'Chart Video',
          description: '',
          thumbnailUrl: '',
          isMusic: true,
        ),
      ],
      nextPageToken: 'next',
      previousPageToken: 'previous',
    );

    final classified = result.asMusicVideoResult();

    expect(classified.videos.single.isMusic, isTrue);
    expect(classified.videos.single.isMusicVideo, isTrue);
    expect(classified.videos.single.hasVideo, isTrue);
    expect(classified.nextPageToken, 'next');
    expect(classified.previousPageToken, 'previous');
  });

  test('speichert und lädt das Live-Kennzeichen lokal', () {
    const video = YouTubeVideo(
      id: 'live-id',
      title: 'Live-Übertragung',
      description: '',
      thumbnailUrl: '',
      isLive: true,
    );

    final restored = YouTubeVideo.fromJson(video.toJson());

    expect(restored?.isLive, isTrue);
  });

  test('übernimmt das Live-Kennzeichen aus einem API-Suchergebnis', () {
    final video = YouTubeVideo.fromSearchItem({
      'id': {'videoId': 'live-id'},
      'snippet': {
        'title': 'Live-Übertragung',
        'description': '',
        'liveBroadcastContent': 'live',
      },
    });

    expect(video?.isLive, isTrue);
  });

  test('erkennt Live-Badges in Channel- und Playlist-Renderern', () {
    expect(
      isYouTubeLiveVideoRenderer({
        'thumbnailOverlays': [
          {
            'thumbnailOverlayTimeStatusRenderer': {
              'style': 'LIVE',
              'text': {'simpleText': 'LIVE'},
            },
          },
        ],
      }),
      isTrue,
    );
    expect(
      isYouTubeLiveVideoRenderer({
        'badges': [
          {
            'badgeViewModel': {
              'badgeText': 'JETZT LIVE',
              'badgeStyle': 'THUMBNAIL_OVERLAY_BADGE_STYLE_LIVE',
            },
          },
        ],
      }),
      isTrue,
    );
    expect(
      isYouTubeLiveVideoRenderer({
        'title': {'simpleText': 'Ein normales Video über Live-Musik'},
        'style': 'DEFAULT',
      }),
      isFalse,
    );
  });
}
