import 'dart:convert';

const _rendererKeys = <String>{
  'videoRenderer',
  'playlistVideoRenderer',
  'gridVideoRenderer',
  'lockupViewModel',
};

/// Detects YouTube's language-independent members-only metadata and keeps
/// localized badge/playability text as a defensive fallback.
bool isYouTubeMembersOnlyRenderer(Object? node) {
  return _containsMembersOnlyMarker(node, insideIndicatorContext: false);
}

Set<String> extractYouTubeMembersOnlyVideoIds(Object? response) {
  final ids = <String>{};
  if (response is String) {
    _collectIdsFromRawResponse(response, ids);
  } else {
    _collectIdsFromDecodedResponse(response, ids);
  }
  return ids;
}

/// Protects playback paths which did not originate in a raw web renderer,
/// for example the optional YouTube Data API backend.
bool isYouTubeMembersOnlyPlaybackFailure(Object? error) {
  final normalized = _normalize(error.toString());
  return normalized.contains('badge_style_type_members_only') ||
      normalized.contains('sponsors_only_video') ||
      normalized.contains('members-only content') ||
      normalized.contains('members only content') ||
      normalized.contains('members-only video') ||
      normalized.contains('members only video') ||
      normalized.contains('join this channel to get access') ||
      normalized.contains('nur fur kanalmitglieder') ||
      normalized.contains('nur fur mitglieder') ||
      normalized.contains('exklusive inhalte fur kanalmitglieder') ||
      normalized.contains('werde kanalmitglied, um zugriff');
}

bool _containsMembersOnlyMarker(
  Object? node, {
  required bool insideIndicatorContext,
}) {
  if (node is List) {
    return node.any(
      (child) => _containsMembersOnlyMarker(
        child,
        insideIndicatorContext: insideIndicatorContext,
      ),
    );
  }
  if (node is! Map) {
    return false;
  }

  for (final entry in node.entries) {
    final key = _normalize(entry.key.toString()).replaceAll(' ', '');
    final value = entry.value;
    final childIndicatorContext =
        insideIndicatorContext || _isIndicatorContextKey(key);

    if (value is String) {
      final normalized = _normalize(value);
      final structural = normalized.replaceAll(' ', '_');
      if ((structural.contains('badge_style_type_members_only') &&
              (insideIndicatorContext || key.contains('style'))) ||
          (normalized == 'sponsors_only_video' &&
              (insideIndicatorContext || key == 'offerid'))) {
        return true;
      }
      if (childIndicatorContext &&
          ((key == 'icontype' &&
                  insideIndicatorContext &&
                  normalized == 'sponsorship_star') ||
              _containsLocalizedMembersOnlyText(normalized))) {
        return true;
      }
    }

    if (_containsMembersOnlyMarker(
      value,
      insideIndicatorContext: childIndicatorContext,
    )) {
      return true;
    }
  }
  return false;
}

bool _isIndicatorContextKey(String key) {
  return key.contains('badge') ||
      key.contains('accessibility') ||
      key.contains('overlay') ||
      key.contains('playability') ||
      key.contains('error') ||
      key.contains('offer') ||
      key == 'style';
}

bool _containsLocalizedMembersOnlyText(String value) {
  return value.contains('members only') ||
      value.contains('members-only') ||
      value.contains('nur fur kanalmitglieder') ||
      value.contains('nur fur mitglieder') ||
      value.contains('exklusive inhalte fur kanalmitglieder');
}

String _normalize(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[‐‑‒–—−]'), '-')
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'\s+'), ' ');
}

void _collectIdsFromDecodedResponse(Object? node, Set<String> ids) {
  if (node is List) {
    for (final child in node) {
      _collectIdsFromDecodedResponse(child, ids);
    }
    return;
  }
  if (node is! Map) {
    return;
  }

  for (final rendererKey in _rendererKeys) {
    final renderer = node[rendererKey];
    if (renderer is Map && isYouTubeMembersOnlyRenderer(renderer)) {
      final videoId = _readVideoId(renderer);
      if (videoId != null) {
        ids.add(videoId);
      }
    }
  }
  for (final child in node.values) {
    _collectIdsFromDecodedResponse(child, ids);
  }
}

void _collectIdsFromRawResponse(String response, Set<String> ids) {
  for (final rendererKey in _rendererKeys) {
    final marker = '"$rendererKey"';
    var searchOffset = 0;
    while (searchOffset < response.length) {
      final markerIndex = response.indexOf(marker, searchOffset);
      if (markerIndex < 0) {
        break;
      }
      final objectStart = response.indexOf('{', markerIndex + marker.length);
      if (objectStart < 0) {
        break;
      }
      final objectEnd = _findJsonObjectEnd(response, objectStart);
      if (objectEnd < 0) {
        searchOffset = objectStart + 1;
        continue;
      }
      try {
        final renderer = jsonDecode(response.substring(objectStart, objectEnd));
        if (renderer is Map && isYouTubeMembersOnlyRenderer(renderer)) {
          final videoId = _readVideoId(renderer);
          if (videoId != null) {
            ids.add(videoId);
          }
        }
      } on FormatException {
        // A malformed renderer must not make the otherwise valid search fail.
      }
      searchOffset = objectEnd;
    }
  }
}

String? _readVideoId(Map renderer) {
  for (final key in const ['videoId', 'contentId']) {
    final value = renderer[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return _findFirstVideoId(renderer);
}

String? _findFirstVideoId(Object? node) {
  if (node is List) {
    for (final child in node) {
      final result = _findFirstVideoId(child);
      if (result != null) {
        return result;
      }
    }
    return null;
  }
  if (node is! Map) {
    return null;
  }
  final value = node['videoId'];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  for (final child in node.values) {
    final result = _findFirstVideoId(child);
    if (result != null) {
      return result;
    }
  }
  return null;
}

int _findJsonObjectEnd(String value, int start) {
  var depth = 0;
  var insideString = false;
  var escaped = false;
  for (var index = start; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    if (insideString) {
      if (escaped) {
        escaped = false;
      } else if (codeUnit == 0x5c) {
        escaped = true;
      } else if (codeUnit == 0x22) {
        insideString = false;
      }
      continue;
    }
    if (codeUnit == 0x22) {
      insideString = true;
    } else if (codeUnit == 0x7b) {
      depth++;
    } else if (codeUnit == 0x7d) {
      depth--;
      if (depth == 0) {
        return index + 1;
      }
    }
  }
  return -1;
}
