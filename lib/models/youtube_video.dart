class YouTubeVideo {
  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    this.channelTitle = '',
    this.publishedAt,
    this.duration,
    this.isMusic = false,
    this.isMusicVideo = false,
    this.isLive = false,
  });

  final String id;
  final String title;
  final String description;
  final String thumbnailUrl;
  final String channelTitle;
  final DateTime? publishedAt;
  final Duration? duration;
  final bool isMusic;
  final bool isMusicVideo;
  final bool isLive;

  /// Whether this medium needs a rendered video surface in the player.
  ///
  /// Regular YouTube videos always have one. YouTube Music entries only have
  /// one when they were explicitly identified as music videos.
  bool get hasVideo => !isMusic || isMusicVideo;

  /// Whether YouTube Music should be resolved as an audio-only stream.
  bool get isAudioOnlyMusic => isMusic && !isMusicVideo;

  YouTubeVideo asMusicVideo() {
    if (isMusic && isMusicVideo) {
      return this;
    }
    return YouTubeVideo(
      id: id,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
      channelTitle: channelTitle,
      publishedAt: publishedAt,
      duration: duration,
      isMusic: true,
      isMusicVideo: true,
      isLive: isLive,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'description': description,
    'thumbnailUrl': thumbnailUrl,
    'channelTitle': channelTitle,
    if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
    if (duration != null) 'durationMilliseconds': duration!.inMilliseconds,
    if (isMusic) 'isMusic': true,
    if (isMusicVideo) 'isMusicVideo': true,
    if (isLive) 'isLive': true,
  };

  static YouTubeVideo? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final id = value['id'];
    final title = value['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      return null;
    }
    return YouTubeVideo(
      id: id,
      title: title,
      description: value['description'] is String
          ? value['description'] as String
          : '',
      thumbnailUrl: value['thumbnailUrl'] is String
          ? value['thumbnailUrl'] as String
          : '',
      channelTitle: value['channelTitle'] is String
          ? value['channelTitle'] as String
          : '',
      publishedAt: _readDateTime(value['publishedAt']),
      duration: _readDuration(value['durationMilliseconds']),
      isMusic: value['isMusic'] == true,
      isMusicVideo: value['isMusicVideo'] == true,
      isLive: value['isLive'] == true,
    );
  }

  static YouTubeVideo? fromSearchItem(Map<String, dynamic> item) {
    final idData = item['id'];
    final snippetData = item['snippet'];

    if (idData is! Map<String, dynamic> ||
        snippetData is! Map<String, dynamic>) {
      return null;
    }

    final id = idData['videoId'];
    final title = snippetData['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      return null;
    }

    return YouTubeVideo(
      id: id,
      title: title,
      description: snippetData['description'] is String
          ? snippetData['description'] as String
          : '',
      thumbnailUrl: _readThumbnailUrl(snippetData),
      channelTitle: snippetData['channelTitle'] is String
          ? snippetData['channelTitle'] as String
          : '',
      publishedAt: _readDateTime(snippetData['publishedAt']),
      isLive: snippetData['liveBroadcastContent'] == 'live',
    );
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static Duration? _readDuration(Object? value) {
    if (value is! num || value <= 0) {
      return null;
    }
    return Duration(milliseconds: value.round());
  }

  static String _readThumbnailUrl(Map<String, dynamic> snippet) {
    final thumbnails = snippet['thumbnails'];
    if (thumbnails is! Map<String, dynamic>) {
      return '';
    }

    for (final quality in const ['high', 'medium', 'default']) {
      final thumbnail = thumbnails[quality];
      if (thumbnail is Map<String, dynamic> && thumbnail['url'] is String) {
        return thumbnail['url'] as String;
      }
    }

    return '';
  }
}

class YouTubeSearchResult {
  const YouTubeSearchResult({
    required this.videos,
    this.nextPageToken,
    this.previousPageToken,
  });

  final List<YouTubeVideo> videos;
  final String? nextPageToken;
  final String? previousPageToken;

  YouTubeSearchResult asMusicVideoResult() => YouTubeSearchResult(
    videos: List<YouTubeVideo>.unmodifiable(
      videos.map((video) => video.asMusicVideo()),
    ),
    nextPageToken: nextPageToken,
    previousPageToken: previousPageToken,
  );
}
