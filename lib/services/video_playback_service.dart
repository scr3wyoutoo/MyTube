import 'dart:convert';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';
// ignore: implementation_imports
import 'package:youtube_explode_dart/src/reverse_engineering/pages/watch_page.dart';

import '../models/video_playback.dart';
import '../utils/media_duration.dart';
import '../utils/youtube_audio_track_preference.dart';
import 'playback_youtube_explode_factory.dart';
import 'youtube_members_only_detection.dart';

abstract interface class VideoPlaybackService {
  Future<ResolvedVideoPlayback> resolve(
    String videoId, {
    VideoManifestEventCallback? onManifestEvent,
    bool music = false,
    bool isLive = false,
    String languageCode = 'de',
  });

  Future<List<VideoSubtitleCue>> loadSubtitles(String videoId);

  void close();
}

class YouTubeExplodePlaybackService implements VideoPlaybackService {
  YouTubeExplodePlaybackService({
    YoutubeExplode? youtubeExplode,
    Future<String> Function(YoutubeExplode client, String videoId)?
    liveStreamUrlLoader,
  }) : _liveStreamUrlLoader = liveStreamUrlLoader,
       _sessionFuture = youtubeExplode != null
           ? Future.value(PlaybackYoutubeExplodeSession(client: youtubeExplode))
           : createPlaybackYoutubeExplode();

  static const _timeout = Duration(seconds: 20);
  static const _playerApiUrl =
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';

  final Future<PlaybackYoutubeExplodeSession> _sessionFuture;
  final Future<String> Function(YoutubeExplode client, String videoId)?
  _liveStreamUrlLoader;
  final YoutubeHttpClient _liveHttpClient = YoutubeHttpClient();
  PlaybackYoutubeExplodeSession? _session;
  bool _closed = false;

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _liveHttpClient.close();
    final session = _session;
    if (session != null) {
      session.client.close();
    } else {
      _sessionFuture.then((createdSession) => createdSession.client.close());
    }
  }

  @override
  Future<ResolvedVideoPlayback> resolve(
    String videoId, {
    VideoManifestEventCallback? onManifestEvent,
    bool music = false,
    bool isLive = false,
    String languageCode = 'de',
  }) async {
    try {
      final session = await _sessionFuture;
      final youtubeExplode = session.client;
      if (_closed) {
        youtubeExplode.close();
        throw const VideoPlaybackException(
          'Der Video-Dienst wurde bereits geschlossen.',
        );
      }
      _session = session;
      if (isLive && !music) {
        try {
          return await _resolveLive(
            youtubeExplode,
            videoId,
            onManifestEvent: onManifestEvent,
            languageCode: languageCode,
          );
        } on Object catch (liveError, liveStackTrace) {
          try {
            return await _resolveFromSource(
              youtubeExplode,
              videoId,
              startSource: VideoManifestSource.standard,
              onManifestEvent: onManifestEvent,
              music: music,
              languageCode: languageCode,
            );
          } on Object catch (standardError, standardStackTrace) {
            throw VideoPlaybackException(
              'Der Live-Stream konnte nicht geladen werden.',
              cause:
                  'Live-HLS:\n$liveError\n$liveStackTrace\n\n'
                  'Standardpfad:\n$standardError\n$standardStackTrace',
              stackTrace: liveStackTrace,
            );
          }
        }
      }

      try {
        return await _resolveFromSource(
          youtubeExplode,
          videoId,
          startSource: VideoManifestSource.standard,
          onManifestEvent: onManifestEvent,
          music: music,
          languageCode: languageCode,
        );
      } on VideoPlaybackException catch (standardError) {
        if (music || !_looksLikeLiveManifestParserFailure(standardError)) {
          rethrow;
        }
        try {
          return await _resolveLive(
            youtubeExplode,
            videoId,
            onManifestEvent: onManifestEvent,
            languageCode: languageCode,
          );
        } on Object catch (liveError, liveStackTrace) {
          throw VideoPlaybackException(
            'Der Live-Stream konnte nicht geladen werden.',
            cause:
                'Standardpfad:\n${standardError.cause}\n\n'
                'Direkter Live-HLS-Pfad:\n$liveError\n$liveStackTrace',
            stackTrace: liveStackTrace,
          );
        }
      }
    } on VideoPlaybackException {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw VideoPlaybackException(
        'Das Video konnte nicht geladen werden. Bitte versuche es erneut.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<ResolvedVideoPlayback> _resolveLive(
    YoutubeExplode youtubeExplode,
    String videoId, {
    VideoManifestEventCallback? onManifestEvent,
    bool allowUrlRefresh = true,
    required String languageCode,
  }) async {
    onManifestEvent?.call(
      VideoManifestLoadEvent(
        videoId: videoId,
        source: VideoManifestSource.standard,
        phase: VideoManifestLoadPhase.requested,
      ),
    );
    try {
      final injectedLoader = _liveStreamUrlLoader;
      final rawUrl =
          await (injectedLoader != null
                  ? injectedLoader(youtubeExplode, videoId)
                  : _loadLiveStreamUrlFromPlayerApi(videoId, languageCode))
              .timeout(_timeout);
      final url = Uri.tryParse(rawUrl);
      if (url == null || !url.hasScheme || url.host.isEmpty) {
        throw StateError('YouTube lieferte keine gültige Live-HLS-URL.');
      }
      final quality = VideoQualityOption(
        label: 'Auto (Live)',
        height: 0,
        videoUrl: url,
        isHls: true,
        transportLabel: 'YouTube Live HLS',
      );
      onManifestEvent?.call(
        VideoManifestLoadEvent(
          videoId: videoId,
          source: VideoManifestSource.standard,
          phase: VideoManifestLoadPhase.available,
        ),
      );
      return ResolvedVideoPlayback(
        qualities: [quality],
        defaultQuality: quality,
        pictureInPictureQuality: quality,
        isLive: true,
        fallbackLoader: allowUrlRefresh
            ? () => _resolveLive(
                youtubeExplode,
                videoId,
                onManifestEvent: onManifestEvent,
                allowUrlRefresh: false,
                languageCode: languageCode,
              )
            : null,
      );
    } on Object {
      onManifestEvent?.call(
        VideoManifestLoadEvent(
          videoId: videoId,
          source: VideoManifestSource.standard,
          phase: VideoManifestLoadPhase.failed,
        ),
      );
      rethrow;
    }
  }

  Future<String> _loadLiveStreamUrlFromPlayerApi(
    String videoId,
    String languageCode,
  ) async {
    final watchPage = await WatchPage.get(_liveHttpClient, videoId);
    final clients = <YoutubeApiClient>[
      _visionOsClient(languageCode),
      _androidVrClient(languageCode),
      _androidSdklessClient(languageCode),
    ];
    final failures = <String>[];
    for (final client in clients) {
      final clientData = client.payload['context']?['client'];
      final clientName = clientData is Map
          ? clientData['clientName']?.toString() ?? 'Unbekannt'
          : 'Unbekannt';
      try {
        final body = <String, dynamic>{
          ...client.payload,
          'videoId': videoId,
          if (watchPage.ytCfg['STS'] != null)
            'playbackContext': {
              'contentPlaybackContext': {
                'html5Preference': 'HTML5_PREF_WANTS',
                'signatureTimestamp': watchPage.ytCfg['STS'].toString(),
              },
            },
        };
        final headers = <String, String>{
          if (clientData is Map && clientData['userAgent'] != null)
            'User-Agent': clientData['userAgent'].toString(),
          if (clientData is Map && clientData['clientName'] != null)
            'X-Youtube-Client-Name': clientData['clientName'].toString(),
          if (clientData is Map && clientData['clientVersion'] != null)
            'X-Youtube-Client-Version': clientData['clientVersion'].toString(),
          'Origin': 'https://www.youtube.com',
          'Sec-Fetch-Mode': 'navigate',
          'Content-Type': 'application/json',
          'Cookie': watchPage.cookieString,
          for (final entry in client.headers.entries)
            entry.key: entry.value.toString(),
        };
        final visitorData = _readNestedString(watchPage.ytCfg, const [
          'INNERTUBE_CONTEXT',
          'client',
          'visitorData',
        ]);
        if (visitorData != null && visitorData.isNotEmpty) {
          headers['X-Goog-Visitor-Id'] = visitorData;
        }

        final rawResponse = await _liveHttpClient.postString(
          client.apiUrl,
          body: body,
          headers: headers,
        );
        final response = jsonDecode(rawResponse);
        if (response is! Map) {
          throw const FormatException(
            'YouTubes Player-Antwort war kein JSON-Objekt.',
          );
        }
        final status = _readNestedString(response, const [
          'playabilityStatus',
          'status',
        ]);
        final reason = _readNestedString(response, const [
          'playabilityStatus',
          'reason',
        ]);
        if (status != 'OK') {
          throw StateError(
            'YouTube meldete ${status ?? 'keinen Status'}'
            '${reason == null || reason.isEmpty ? '' : ': $reason'}.',
          );
        }
        final hlsManifestUrl = _readNestedString(response, const [
          'streamingData',
          'hlsManifestUrl',
        ]);
        if (hlsManifestUrl == null || hlsManifestUrl.isEmpty) {
          throw StateError(
            'Die Player-Antwort enthielt keine Live-HLS-Master-URL.',
          );
        }
        return hlsManifestUrl;
      } on Object catch (error) {
        failures.add('$clientName: $error');
      }
    }
    throw StateError(
      'Keiner der Player-Clients lieferte eine Live-HLS-Master-URL.\n'
      '${failures.join('\n')}',
    );
  }

  String? _readNestedString(Object? root, List<String> path) {
    Object? current = root;
    for (final segment in path) {
      if (current is! Map) {
        return null;
      }
      current = current[segment];
    }
    return current is String ? current : null;
  }

  bool _looksLikeLiveManifestParserFailure(VideoPlaybackException error) {
    final details = '${error.cause}\n${error.stackTrace}';
    return details.contains('HlsManifest.streams') &&
        details.contains('Null check operator used on a null value');
  }

  Future<ResolvedVideoPlayback> _resolveFromSource(
    YoutubeExplode youtubeExplode,
    String videoId, {
    required VideoManifestSource startSource,
    VideoManifestEventCallback? onManifestEvent,
    required bool music,
    required String languageCode,
  }) async {
    final failures = <String>[];
    final sources = VideoManifestSource.values;
    for (var index = startSource.index; index < sources.length; index++) {
      final source = sources[index];
      onManifestEvent?.call(
        VideoManifestLoadEvent(
          videoId: videoId,
          source: source,
          phase: VideoManifestLoadPhase.requested,
        ),
      );
      try {
        final manifest = await _loadManifest(
          youtubeExplode,
          videoId,
          source,
          languageCode: languageCode,
        );
        final transportLabel = _transportLabel(source);
        final qualities = music
            ? _buildMusicQualityOptions(
                manifest,
                transportLabel: transportLabel,
                languageCode: languageCode,
              )
            : source == VideoManifestSource.secondFallback
            ? _buildFinalFallbackQualities(
                manifest,
                transportLabel: transportLabel,
                languageCode: languageCode,
              )
            : _buildPrimaryQualityOptions(
                manifest,
                transportLabel: transportLabel,
                languageCode: languageCode,
              );
        if (qualities.isEmpty) {
          throw StateError('$transportLabel: keine abspielbaren Streams');
        }
        onManifestEvent?.call(
          VideoManifestLoadEvent(
            videoId: videoId,
            source: source,
            phase: VideoManifestLoadPhase.available,
          ),
        );

        VideoPlaybackFallbackLoader? fallbackLoader;
        if (index + 1 < sources.length) {
          Future<ResolvedVideoPlayback>? fallbackFuture;
          fallbackLoader = () => fallbackFuture ??= _resolveFromSource(
            youtubeExplode,
            videoId,
            startSource: sources[index + 1],
            onManifestEvent: onManifestEvent,
            music: music,
            languageCode: languageCode,
          );
        }
        return ResolvedVideoPlayback(
          qualities: qualities,
          defaultQuality: chooseDefaultVideoQuality(qualities),
          manifestSource: source,
          fallbackLoader: fallbackLoader,
        );
      } on Object catch (error, stackTrace) {
        onManifestEvent?.call(
          VideoManifestLoadEvent(
            videoId: videoId,
            source: source,
            phase: VideoManifestLoadPhase.failed,
          ),
        );
        if (isYouTubeMembersOnlyPlaybackFailure(error)) {
          throw VideoPlaybackException(
            'Dieses Video ist nur für Kanalmitglieder verfügbar.',
            cause: error,
            stackTrace: stackTrace,
          );
        }
        failures.add(
          '${source.label} (${_transportLabel(source)}):\n'
          '${error.runtimeType}: $error\n$stackTrace',
        );
      }
    }

    throw VideoPlaybackException(
      'Für dieses Video wurde kein abspielbarer Stream gefunden.',
      cause: failures.join('\n\n'),
    );
  }

  Future<StreamManifest> _loadManifest(
    YoutubeExplode youtubeExplode,
    String videoId,
    VideoManifestSource source, {
    required String languageCode,
  }) {
    return switch (source) {
      VideoManifestSource.standard =>
        youtubeExplode.videos.streams
            .getManifest(videoId, ytClients: [_visionOsClient(languageCode)])
            .timeout(_timeout),
      VideoManifestSource.firstFallback =>
        youtubeExplode.videos.streams
            .getManifest(videoId, ytClients: [_androidVrClient(languageCode)])
            .timeout(_timeout),
      VideoManifestSource.secondFallback =>
        youtubeExplode.videos.streams
            .getManifest(
              videoId,
              ytClients: [_androidSdklessClient(languageCode)],
            )
            .timeout(_timeout),
    };
  }

  String _transportLabel(VideoManifestSource source) => switch (source) {
    VideoManifestSource.standard => 'VisionOS Standard',
    VideoManifestSource.firstFallback => 'Android VR Fallback',
    VideoManifestSource.secondFallback => 'Android 360p-Fallback',
  };

  List<VideoQualityOption> _buildMusicQualityOptions(
    StreamManifest manifest, {
    required String transportLabel,
    required String languageCode,
  }) {
    if (manifest.audioOnly.isNotEmpty) {
      final audio = _chooseAudioStream(
        manifest.audioOnly,
        languageCode: languageCode,
      );
      final audioLabel = _audioTrackLabel(audio);
      return [
        VideoQualityOption(
          label: 'Audio',
          height: 0,
          videoUrl: audio.url,
          expectedDuration: youtubeStreamDuration(audio.url),
          requiresSegmentedProxy: true,
          transportLabel: '$transportLabel · progressive Audiospur$audioLabel',
        ),
      ];
    }

    final hlsAudio = manifest.hls.whereType<HlsAudioStreamInfo>().toList();
    if (hlsAudio.isNotEmpty) {
      hlsAudio.sort((first, second) => first.bitrate.compareTo(second.bitrate));
      return [
        VideoQualityOption(
          label: 'Audio',
          height: 0,
          videoUrl: hlsAudio.last.url,
          expectedDuration: youtubeStreamDuration(hlsAudio.last.url),
          isHls: true,
          transportLabel: '$transportLabel · einzelne HLS-Audiospur',
        ),
      ];
    }

    final muxed = _buildMuxedFallback(
      manifest,
      transportLabel: '$transportLabel · kombinierter Music-Fallback',
    );
    return muxed == null ? const [] : [muxed];
  }

  List<VideoQualityOption> _buildFinalFallbackQualities(
    StreamManifest manifest, {
    required String transportLabel,
    required String languageCode,
  }) {
    final explicitLanguage = _buildExplicitLanguageQualityOptions(
      manifest,
      transportLabel: transportLabel,
      languageCode: languageCode,
    );
    if (explicitLanguage.isNotEmpty) {
      return explicitLanguage;
    }
    final muxed = _buildMuxedFallback(manifest, transportLabel: transportLabel);
    if (muxed != null) {
      return <VideoQualityOption>[muxed];
    }
    return _buildPrimaryQualityOptions(
      manifest,
      transportLabel: transportLabel,
      languageCode: languageCode,
    );
  }

  @override
  Future<List<VideoSubtitleCue>> loadSubtitles(String videoId) async {
    try {
      final session = await _sessionFuture;
      if (_closed) {
        return const [];
      }
      _session = session;
      return _loadSubtitles(session.client, videoId);
    } on Exception {
      return const [];
    }
  }

  List<VideoQualityOption> _buildPrimaryQualityOptions(
    StreamManifest manifest, {
    required String transportLabel,
    required String languageCode,
  }) {
    final explicitLanguage = _buildExplicitLanguageQualityOptions(
      manifest,
      transportLabel: transportLabel,
      languageCode: languageCode,
    );
    if (explicitLanguage.isNotEmpty) {
      return explicitLanguage;
    }
    final hlsQualities = _buildHlsQualityOptions(
      manifest,
      transportLabel: '$transportLabel HLS',
    );
    if (hlsQualities.isNotEmpty) {
      return hlsQualities;
    }
    final progressiveQualities = _buildQualityOptions(
      manifest,
      transportLabel: transportLabel,
    );
    return progressiveQualities;
  }

  List<VideoQualityOption> _buildHlsQualityOptions(
    StreamManifest manifest, {
    required String transportLabel,
    String? requiredAudioTag,
  }) {
    final audioByTag = <String, HlsAudioStreamInfo>{
      for (final stream in manifest.hls.whereType<HlsAudioStreamInfo>())
        stream.tag.toString(): stream,
    };
    final streamsByHeight = <int, List<HlsVideoStreamInfo>>{};
    for (final stream in manifest.hls.whereType<HlsVideoStreamInfo>()) {
      if (!audioByTag.containsKey(stream.audioItag.toString())) {
        continue;
      }
      if (requiredAudioTag != null &&
          stream.audioItag.toString() != requiredAudioTag) {
        continue;
      }
      final height = _qualityHeight(
        stream.qualityLabel,
        stream.videoResolution,
      );
      streamsByHeight.putIfAbsent(height, () => []).add(stream);
    }

    final options = <VideoQualityOption>[];
    for (final entry in streamsByHeight.entries) {
      // Legacy HLS itags are the broadly supported AVC variants. Prefer them
      // over the newer VP9/AV1 alternatives on Android and iOS.
      final avcCandidates = entry.value
          .where((stream) => _itagValue(stream.tag) < 600)
          .toList(growable: false);
      final stream = (avcCandidates.isNotEmpty ? avcCandidates : entry.value)
          .sortByBitrate()
          .last;
      final audio = audioByTag[stream.audioItag.toString()]!;
      options.add(
        VideoQualityOption(
          label: stream.qualityLabel,
          height: entry.key,
          videoUrl: stream.url,
          expectedDuration: canonicalPlaybackDuration(
            streamDuration: youtubeStreamDuration(stream.url),
            catalogDuration: youtubeStreamDuration(audio.url),
          ),
          hlsMasterPlaylist: _buildHlsMasterPlaylist(stream, audio),
          isHls: true,
          transportLabel: '$transportLabel (gemeinsame A/V-Zeitachse)',
        ),
      );
    }
    return filterSelectableVideoQualities(options);
  }

  int _qualityHeight(String label, VideoResolution resolution) {
    final labelHeight = int.tryParse(
      RegExp(r'(\d+)p').firstMatch(label)?.group(1) ?? '',
    );
    if (labelHeight != null) {
      return labelHeight;
    }
    return resolution.width < resolution.height
        ? resolution.width
        : resolution.height;
  }

  int _itagValue(Object tag) => int.tryParse(tag.toString()) ?? 9999;

  String _buildHlsMasterPlaylist(
    HlsVideoStreamInfo video,
    HlsAudioStreamInfo audio,
  ) {
    final audioUri = _escapeHlsAttribute(audio.url.toString());
    final videoUri = video.url.toString();
    final bandwidth = video.bitrate.bitsPerSecond + audio.bitrate.bitsPerSecond;
    final resolution = video.videoResolution;
    final frameRate =
        RegExp(r'[\d.]+').firstMatch(video.framerate.toString())?.group(0) ??
        '30';
    return '#EXTM3U\n'
        '#EXT-X-VERSION:6\n'
        '#EXT-X-INDEPENDENT-SEGMENTS\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="youtube-audio",'
        'NAME="Default",DEFAULT=YES,AUTOSELECT=YES,URI="$audioUri"\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth,'
        'RESOLUTION=${resolution.width}x${resolution.height},'
        'FRAME-RATE=$frameRate,AUDIO="youtube-audio"\n'
        '$videoUri\n';
  }

  String _escapeHlsAttribute(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  List<VideoQualityOption> _buildQualityOptions(
    StreamManifest manifest, {
    required String transportLabel,
    AudioOnlyStreamInfo? preferredAudio,
    String? languageCode,
  }) {
    final options = <VideoQualityOption>[];

    if (manifest.videoOnly.isNotEmpty && manifest.audioOnly.isNotEmpty) {
      final audio =
          preferredAudio ??
          _chooseAudioStream(manifest.audioOnly, languageCode: languageCode);
      final audioUrl = audio.url;
      final streamsByHeight = <int, List<VideoOnlyStreamInfo>>{};
      for (final stream in manifest.videoOnly) {
        streamsByHeight
            .putIfAbsent(stream.videoResolution.height, () => [])
            .add(stream);
      }

      for (final entry in streamsByHeight.entries) {
        final stream = _chooseVideoStream(entry.value);
        options.add(
          VideoQualityOption(
            label: stream.qualityLabel,
            height: entry.key,
            videoUrl: stream.url,
            audioUrl: audioUrl,
            expectedDuration: canonicalPlaybackDuration(
              streamDuration: youtubeStreamDuration(audioUrl),
              catalogDuration: youtubeStreamDuration(stream.url),
            ),
            transportLabel: transportLabel,
          ),
        );
      }
    } else {
      final streamsByHeight = <int, List<MuxedStreamInfo>>{};
      for (final stream in manifest.muxed) {
        streamsByHeight
            .putIfAbsent(stream.videoResolution.height, () => [])
            .add(stream);
      }
      for (final entry in streamsByHeight.entries) {
        final stream = _preferUnthrottled(entry.value).sortByBitrate().last;
        options.add(
          VideoQualityOption(
            label: stream.qualityLabel,
            height: entry.key,
            videoUrl: stream.url,
            expectedDuration: youtubeStreamDuration(stream.url),
            transportLabel: transportLabel,
          ),
        );
      }
    }

    return filterSelectableVideoQualities(options);
  }

  VideoQualityOption? _buildMuxedFallback(
    StreamManifest manifest, {
    required String transportLabel,
  }) {
    if (manifest.muxed.isEmpty) {
      return null;
    }
    final stream = _preferUnthrottled(manifest.muxed).bestQuality;
    return VideoQualityOption(
      label: stream.qualityLabel,
      height: stream.videoResolution.height,
      videoUrl: stream.url,
      expectedDuration: youtubeStreamDuration(stream.url),
      transportLabel: transportLabel,
    );
  }

  YoutubeApiClient _visionOsClient(String languageCode) {
    final language = languageCode == 'en' ? 'en' : 'de';
    final region = language == 'en' ? 'US' : 'DE';
    return YoutubeApiClient(
      {
        'context': {
          'client': {
            'clientName': 'VISIONOS',
            'clientVersion': '1.02',
            'deviceMake': 'Apple',
            'deviceModel': 'RealityDevice17,1',
            'userAgent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) '
                'AppleWebKit/605.1.15 (KHTML, like Gecko) '
                'Version/26.0 Safari/605.1.15',
            'osName': 'visionOS',
            'osVersion': '26.5.23O471',
            'hl': language,
            'gl': region,
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
          },
        },
      },
      _playerApiUrl,
      headers: {
        'Content-Type': 'application/json',
        'X-YouTube-Client-Name': '101',
        'X-YouTube-Client-Version': '1.02',
        'Accept-Language': language == 'en'
            ? 'en-US,en;q=0.9'
            : 'de-DE,de;q=0.9',
      },
    );
  }

  YoutubeApiClient _androidVrClient(String languageCode) {
    final language = languageCode == 'en' ? 'en' : 'de';
    final region = language == 'en' ? 'US' : 'DE';
    return YoutubeApiClient(
      {
        'context': {
          'client': {
            'clientName': 'ANDROID_VR',
            'clientVersion': '1.65.10',
            'deviceMake': 'Oculus',
            'deviceModel': 'Quest 3',
            'androidSdkVersion': 32,
            'userAgent':
                'com.google.android.apps.youtube.vr.oculus/1.65.10 '
                '(Linux; U; Android 12L; '
                'eureka-user Build/SQ3A.220605.009.A1) gzip',
            'osName': 'Android',
            'osVersion': '12L',
            'hl': language,
            'gl': region,
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
          },
        },
      },
      _playerApiUrl,
      headers: {
        'Content-Type': 'application/json',
        'X-YouTube-Client-Name': '28',
        'X-YouTube-Client-Version': '1.65.10',
        'Accept-Language': language == 'en'
            ? 'en-US,en;q=0.9'
            : 'de-DE,de;q=0.9',
      },
    );
  }

  YoutubeApiClient _androidSdklessClient(String languageCode) {
    final language = languageCode == 'en' ? 'en' : 'de';
    final region = language == 'en' ? 'US' : 'DE';
    return YoutubeApiClient(
      {
        'context': {
          'client': {
            'clientName': 'ANDROID',
            'clientVersion': '20.10.38',
            'userAgent':
                'com.google.android.youtube/20.10.38 '
                '(Linux; U; Android 11) gzip',
            'hl': language,
            'gl': region,
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
            'osName': 'Android',
            'osVersion': '11',
          },
        },
      },
      _playerApiUrl,
      headers: {
        'Content-Type': 'application/json',
        'X-YouTube-Client-Name': '3',
        'X-YouTube-Client-Version': '20.10.38',
        'Accept-Language': language == 'en'
            ? 'en-US,en;q=0.9'
            : 'de-DE,de;q=0.9',
      },
    );
  }

  AudioOnlyStreamInfo _chooseAudioStream(
    Iterable<AudioOnlyStreamInfo> streams, {
    String? languageCode,
  }) {
    final preferred = _preferUnthrottled(streams);
    if (languageCode != null) {
      final languageMatch = _chooseLanguageAudioStream(preferred, languageCode);
      if (languageMatch != null) {
        return languageMatch;
      }
    }
    final mp4 = preferred
        .where((stream) => stream.container == StreamContainer.mp4)
        .toList(growable: false);
    return (mp4.isNotEmpty ? mp4 : preferred).withHighestBitrate();
  }

  List<VideoQualityOption> _buildExplicitLanguageQualityOptions(
    StreamManifest manifest, {
    required String transportLabel,
    required String languageCode,
  }) {
    if (!_hasMultipleAudioTracks(manifest.audioOnly)) {
      return const [];
    }
    final audio = _chooseLanguageAudioStream(
      _preferUnthrottled(manifest.audioOnly),
      languageCode,
    );
    if (audio == null) {
      return const [];
    }

    final audioLabel = _audioTrackLabel(audio);
    final hls = _buildHlsQualityOptions(
      manifest,
      transportLabel: '$transportLabel HLS$audioLabel',
      requiredAudioTag: audio.tag.toString(),
    );
    if (hls.isNotEmpty) {
      return hls;
    }
    return _buildQualityOptions(
      manifest,
      transportLabel: '$transportLabel · progressive A/V$audioLabel',
      preferredAudio: audio,
      languageCode: languageCode,
    );
  }

  AudioOnlyStreamInfo? _chooseLanguageAudioStream(
    Iterable<AudioOnlyStreamInfo> streams,
    String languageCode,
  ) {
    AudioOnlyStreamInfo? best;
    var bestScore = -1;
    for (final stream in streams) {
      final track = stream.audioTrack;
      if (track == null) {
        continue;
      }
      final score = youtubeAudioTrackLanguageScore(
        languageCode: languageCode,
        trackId: track.id,
        displayName: track.displayName,
        isDefault: track.audioIsDefault,
      );
      if (score < 0) {
        continue;
      }
      final bestIsMp4 = best?.container == StreamContainer.mp4;
      final streamIsMp4 = stream.container == StreamContainer.mp4;
      if (best == null ||
          score > bestScore ||
          (score == bestScore && streamIsMp4 && !bestIsMp4) ||
          (score == bestScore &&
              streamIsMp4 == bestIsMp4 &&
              stream.bitrate.compareTo(best.bitrate) > 0)) {
        best = stream;
        bestScore = score;
      }
    }
    return best;
  }

  bool _hasMultipleAudioTracks(Iterable<AudioOnlyStreamInfo> streams) {
    final identities = <String>{};
    for (final stream in streams) {
      final track = stream.audioTrack;
      if (track == null) {
        continue;
      }
      identities.add('${track.id}\u0000${track.displayName}');
      if (identities.length > 1) {
        return true;
      }
    }
    return false;
  }

  String _audioTrackLabel(AudioOnlyStreamInfo stream) {
    final track = stream.audioTrack;
    if (track == null || track.displayName.trim().isEmpty) {
      return '';
    }
    return ' · Audio: ${track.displayName.trim()}';
  }

  VideoOnlyStreamInfo _chooseVideoStream(
    Iterable<VideoOnlyStreamInfo> streams,
  ) {
    final preferred = _preferUnthrottled(streams);
    final h264 = preferred
        .where(
          (stream) =>
              stream.container == StreamContainer.mp4 &&
              stream.videoCodec.toLowerCase().contains('avc'),
        )
        .toList(growable: false);
    if (h264.isNotEmpty) {
      return h264.sortByBitrate().last;
    }
    final mp4 = preferred
        .where((stream) => stream.container == StreamContainer.mp4)
        .toList(growable: false);
    return (mp4.isNotEmpty ? mp4 : preferred).sortByBitrate().last;
  }

  List<T> _preferUnthrottled<T extends StreamInfo>(Iterable<T> streams) {
    final all = streams.toList(growable: false);
    final unthrottled = all
        .where((stream) => !stream.isThrottled)
        .toList(growable: false);
    return unthrottled.isNotEmpty ? unthrottled : all;
  }

  Future<List<VideoSubtitleCue>> _loadSubtitles(
    YoutubeExplode youtubeExplode,
    String videoId,
  ) async {
    try {
      final manifest = await youtubeExplode.videos.closedCaptions
          .getManifest(videoId)
          .timeout(_timeout);
      if (manifest.tracks.isEmpty) {
        return const [];
      }

      final track = await youtubeExplode.videos.closedCaptions
          .get(manifest.tracks.first)
          .timeout(_timeout);
      final cues = track.captions
          .map(
            (caption) => VideoSubtitleCue(
              start: caption.offset,
              end: caption.end,
              text: caption.text,
            ),
          )
          .toList(growable: false);
      cues.sort((first, second) => first.start.compareTo(second.start));
      return List.unmodifiable(cues);
    } on Exception {
      // Untertitel sind optional und dürfen das Abspielen nicht verhindern.
      return const [];
    }
  }
}

class VideoPlaybackException implements Exception {
  const VideoPlaybackException(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  String get technicalDetails {
    final details = StringBuffer('VideoPlaybackException: $message');
    if (cause != null) {
      details
        ..writeln()
        ..writeln()
        ..writeln('Cause (${cause.runtimeType}):')
        ..write(cause);
    }
    if (stackTrace != null) {
      details
        ..writeln()
        ..writeln()
        ..writeln('Stack trace:')
        ..write(stackTrace);
    }
    return details.toString();
  }

  @override
  String toString() => message;
}
