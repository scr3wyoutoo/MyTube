class YouTubeChannelResult {
  const YouTubeChannelResult({
    required this.id,
    required this.name,
    required this.description,
    required this.thumbnailUrl,
    required this.videoCount,
    this.isMusic = false,
  });

  final String id;
  final String name;
  final String description;
  final String thumbnailUrl;
  final int videoCount;
  final bool isMusic;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'description': description,
    'thumbnailUrl': thumbnailUrl,
    'videoCount': videoCount,
    if (isMusic) 'isMusic': true,
  };

  static YouTubeChannelResult? fromJson(Object? value) {
    if (value is! Map || value['id'] is! String || value['name'] is! String) {
      return null;
    }
    return YouTubeChannelResult(
      id: value['id'] as String,
      name: value['name'] as String,
      description: value['description'] is String
          ? value['description'] as String
          : '',
      thumbnailUrl: value['thumbnailUrl'] is String
          ? value['thumbnailUrl'] as String
          : '',
      videoCount: value['videoCount'] is int ? value['videoCount'] as int : 0,
      isMusic: value['isMusic'] == true,
    );
  }
}

class YouTubePlaylistResult {
  const YouTubePlaylistResult({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.videoCount,
    this.itemsAreMusicVideos = false,
    this.creatorName = '',
    this.typeLabel = '',
  });

  final String id;
  final String title;
  final String thumbnailUrl;
  final int videoCount;
  final bool itemsAreMusicVideos;
  final String creatorName;
  final String typeLabel;
}

class YouTubeCatalogPage<T> {
  const YouTubeCatalogPage({
    required this.items,
    this.nextPageToken,
    this.previousPageToken,
  });

  final List<T> items;
  final String? nextPageToken;
  final String? previousPageToken;
}

enum YouTubeVideoFeedType { keyword, channel, playlist }

class YouTubeVideoFeed {
  const YouTubeVideoFeed.keyword({required this.query})
    : type = YouTubeVideoFeedType.keyword,
      id = null,
      title = null,
      itemsAreMusicVideos = false;

  const YouTubeVideoFeed.channel({
    required String channelId,
    required String channelName,
  }) : type = YouTubeVideoFeedType.channel,
       query = channelName,
       id = channelId,
       title = channelName,
       itemsAreMusicVideos = false;

  const YouTubeVideoFeed.playlist({
    required String playlistId,
    required String playlistTitle,
    this.itemsAreMusicVideos = false,
  }) : type = YouTubeVideoFeedType.playlist,
       query = playlistTitle,
       id = playlistId,
       title = playlistTitle;

  final YouTubeVideoFeedType type;
  final String query;
  final String? id;
  final String? title;
  final bool itemsAreMusicVideos;
}
