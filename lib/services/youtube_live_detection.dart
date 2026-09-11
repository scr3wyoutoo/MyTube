import 'dart:convert';

bool isYouTubeLiveRenderer(Object? node) {
  if (node is List) {
    return node.any(isYouTubeLiveRenderer);
  }
  if (node is! Map) {
    return false;
  }
  for (final entry in node.entries) {
    final key = entry.key.toString().toLowerCase();
    final value = entry.value;
    if ((key == 'islive' || key == 'islivecontent') && value == true) {
      return true;
    }
    if (value is String) {
      final normalized = value.trim().toUpperCase();
      if (key == 'livebroadcastcontent' && normalized == 'LIVE') {
        return true;
      }
      if (key.contains('style') && normalized.contains('LIVE')) {
        return true;
      }
      if ((key == 'icontype' || key == 'label' || key == 'badgetext') &&
          const {'LIVE', 'LIVE NOW', 'JETZT LIVE'}.contains(normalized)) {
        return true;
      }
    }
    if (isYouTubeLiveRenderer(value)) {
      return true;
    }
  }
  return false;
}

Set<String> extractYouTubeLiveVideoIds(Object? response) {
  final ids = <String>{};
  if (response is String) {
    _collectLiveIdsFromRawResponse(response, ids);
  } else {
    _collectLiveIdsFromDecodedResponse(response, ids);
  }
  return ids;
}

void _collectLiveIdsFromDecodedResponse(Object? node, Set<String> ids) {
  if (node is List) {
    for (final child in node) {
      _collectLiveIdsFromDecodedResponse(child, ids);
    }
    return;
  }
  if (node is! Map) {
    return;
  }

  final renderer = node['videoRenderer'];
  if (renderer is Map && isYouTubeLiveRenderer(renderer)) {
    final videoId = renderer['videoId'];
    if (videoId is String && videoId.isNotEmpty) {
      ids.add(videoId);
    }
  }
  for (final child in node.values) {
    _collectLiveIdsFromDecodedResponse(child, ids);
  }
}

void _collectLiveIdsFromRawResponse(String response, Set<String> ids) {
  const marker = '"videoRenderer"';
  var searchOffset = 0;
  while (searchOffset < response.length) {
    final markerIndex = response.indexOf(marker, searchOffset);
    if (markerIndex < 0) {
      return;
    }
    final objectStart = response.indexOf('{', markerIndex + marker.length);
    if (objectStart < 0) {
      return;
    }
    final objectEnd = _findJsonObjectEnd(response, objectStart);
    if (objectEnd < 0) {
      searchOffset = objectStart + 1;
      continue;
    }
    try {
      final renderer = jsonDecode(response.substring(objectStart, objectEnd));
      if (renderer is Map && isYouTubeLiveRenderer(renderer)) {
        final videoId = renderer['videoId'];
        if (videoId is String && videoId.isNotEmpty) {
          ids.add(videoId);
        }
      }
    } on FormatException {
      // A malformed renderer must not make the otherwise valid search fail.
    }
    searchOffset = objectEnd;
  }
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
