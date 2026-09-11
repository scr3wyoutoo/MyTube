import 'package:youtube_explode_dart/youtube_explode_dart.dart' as explode;

import 'youtube_live_detection.dart';
import 'youtube_members_only_detection.dart';

class LocalizedYoutubeHttpClient extends explode.YoutubeHttpClient {
  LocalizedYoutubeHttpClient(this.languageCode);

  final String languageCode;
  Set<String> _liveVideoIds = const {};
  Set<String> _membersOnlyVideoIds = const {};

  bool isKnownLiveVideo(String videoId) => _liveVideoIds.contains(videoId);

  bool isKnownMembersOnlyVideo(String videoId) =>
      _membersOnlyVideoIds.contains(videoId);

  @override
  Map<String, String> get headers {
    final english = languageCode == 'en';
    final regionCode = english ? 'US' : 'DE';
    return {
      ...super.headers,
      'accept-language': english ? 'en-US,en;q=0.9' : 'de-DE,de;q=0.9',
      'cookie': 'CONSENT=YES+cb; PREF=hl=$languageCode&gl=$regionCode',
    };
  }

  @override
  Future<String> getString(
    dynamic url, {
    Map<String, String> headers = const {},
    bool validate = true,
  }) async {
    var response = await super.getString(
      url,
      headers: headers,
      validate: validate,
    );
    _liveVideoIds = extractYouTubeLiveVideoIds(response);
    _membersOnlyVideoIds = extractYouTubeMembersOnlyVideoIds(response);
    response = normalizeYouTubeSearchViewCountRuns(response);
    if (languageCode != 'de') {
      return response;
    }
    return response.replaceAllMapped(
      RegExp(
        r'("publishedTimeText"\s*:\s*\{[^{}]*?"simpleText"\s*:\s*")'
        r'([^"]*)(")',
      ),
      (match) {
        final normalized = normalizeGermanYouTubePublishedTime(match.group(2)!);
        return normalized == null
            ? match.group(0)!
            : '${match.group(1)}$normalized${match.group(3)}';
      },
    );
  }

  @override
  Future<Map<String, dynamic>> sendPost(
    String action,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) async {
    final regionCode = languageCode == 'en' ? 'US' : 'DE';
    final response = await super.sendPost(action, {
      ...data,
      'context': {
        'client': {
          'browserName': 'Chrome',
          'browserVersion': '105.0.0.0',
          'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
          'clientName': 'WEB',
          'clientVersion': '2.20220921.00.00',
          'hl': languageCode,
          'gl': regionCode,
        },
      },
    }, headers: headers);
    _liveVideoIds = extractYouTubeLiveVideoIds(response);
    _membersOnlyVideoIds = extractYouTubeMembersOnlyVideoIds(response);
    if (languageCode == 'de') {
      _normalizeGermanPublishedTimes(response);
    }
    return response;
  }

  void _normalizeGermanPublishedTimes(Object? node) {
    if (node is List<Object?>) {
      for (final value in node) {
        _normalizeGermanPublishedTimes(value);
      }
      return;
    }
    if (node is! Map) {
      return;
    }

    final publishedTime = node['publishedTimeText'];
    if (publishedTime is Map) {
      final text = _textFromRenderer(publishedTime);
      final normalized = text == null
          ? null
          : normalizeGermanYouTubePublishedTime(text);
      if (normalized != null) {
        publishedTime
          ..remove('runs')
          ..['simpleText'] = normalized;
      }
    }

    for (final value in node.values) {
      _normalizeGermanPublishedTimes(value);
    }
  }

  String? _textFromRenderer(Map renderer) {
    final simpleText = renderer['simpleText'];
    if (simpleText is String) {
      return simpleText;
    }
    final runs = renderer['runs'];
    if (runs is! List) {
      return null;
    }
    final buffer = StringBuffer();
    for (final run in runs) {
      if (run is Map && run['text'] is String) {
        buffer.write(run['text']);
      }
    }
    return buffer.isEmpty ? null : buffer.toString();
  }
}

/// youtube_explode_dart 3.1.0 assumes that `viewCountText` either contains
/// `simpleText` or no `runs`. YouTube now emits two `runs` for live viewer
/// counts; the library otherwise invokes a Map extension dynamically and
/// throws a NoSuchMethodError before it can return any search results.
String normalizeYouTubeSearchViewCountRuns(String value) {
  return value.replaceAllMapped(
    RegExp(
      r'"viewCountText"\s*:\s*\{\s*"runs"\s*:\s*\[\s*'
      r'\{\s*"text"\s*:\s*"([^"]*)"\s*\}\s*,\s*'
      r'\{\s*"text"\s*:\s*"([^"]*)"\s*\}\s*\]\s*\}',
    ),
    (match) =>
        '"viewCountText":{"simpleText":"${match.group(1)}${match.group(2)}"}',
  );
}

/// Normalizes YouTube's German relative upload time for the library's
/// English-only date parser. Other localized metadata remains unchanged.
String? normalizeGermanYouTubePublishedTime(String value) {
  final match = RegExp(
    r'\bvor\s+(?:(\d+)|ein(?:e|er|em|en)?)\s+'
    r'(Sekunden?|Minuten?|Stunden?|Tage?n?|Wochen?|Monate?n?|Jahre?n?)\b',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) {
    if (value.toLowerCase().contains('gerade eben')) {
      return '0 seconds ago';
    }
    return null;
  }

  final amount = int.tryParse(match.group(1) ?? '') ?? 1;
  final germanUnit = match.group(2)!.toLowerCase();
  final unit = switch (germanUnit) {
    final value when value.startsWith('sekunde') => 'second',
    final value when value.startsWith('minute') => 'minute',
    final value when value.startsWith('stunde') => 'hour',
    final value when value.startsWith('tag') => 'day',
    final value when value.startsWith('woche') => 'week',
    final value when value.startsWith('monat') => 'month',
    _ => 'year',
  };
  return '$amount $unit${amount == 1 ? '' : 's'} ago';
}
