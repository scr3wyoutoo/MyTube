import 'search_history.dart';
import 'youtube_catalog_item.dart';
import 'youtube_search_sort.dart';
import 'youtube_video.dart';

enum VideoReaction { none, like, dislike }

enum ProfileLanguage {
  german(code: 'de', label: 'Deutsch'),
  english(code: 'en', label: 'English');

  const ProfileLanguage({required this.code, required this.label});

  final String code;
  final String label;

  static ProfileLanguage fromCode(Object? value) {
    return values.firstWhere(
      (language) => language.code == value,
      orElse: () => german,
    );
  }
}

class VideoPlaylist {
  const VideoPlaylist({
    required this.id,
    required this.name,
    this.videos = const [],
  });

  final String id;
  final String name;
  final List<YouTubeVideo> videos;

  VideoPlaylist copyWith({String? name, List<YouTubeVideo>? videos}) {
    return VideoPlaylist(
      id: id,
      name: name ?? this.name,
      videos: videos ?? this.videos,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'videos': videos.map((video) => video.toJson()).toList(),
  };

  static VideoPlaylist? fromJson(Object? value) {
    if (value is! Map || value['id'] is! String || value['name'] is! String) {
      return null;
    }
    final videos = (value['videos'] as List? ?? const [])
        .map(YouTubeVideo.fromJson)
        .whereType<YouTubeVideo>()
        .toList(growable: false);
    return VideoPlaylist(
      id: value['id'] as String,
      name: value['name'] as String,
      videos: videos,
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    this.favorites = const [],
    this.favoriteChannels = const [],
    this.playlists = const [],
    this.likedVideoIds = const {},
    this.dislikedVideoIds = const {},
    this.language = ProfileLanguage.german,
    this.autoplaySearchResults = false,
    this.videoSearchSort = YouTubeSearchSort.relevance,
    this.playlistSearchSort = YouTubeSearchSort.relevance,
    this.searchHistory = const [],
  });

  final String id;
  final String name;
  final List<YouTubeVideo> favorites;
  final List<YouTubeChannelResult> favoriteChannels;
  final List<VideoPlaylist> playlists;
  final Set<String> likedVideoIds;
  final Set<String> dislikedVideoIds;
  final ProfileLanguage language;
  final bool autoplaySearchResults;
  final YouTubeSearchSort videoSearchSort;
  final YouTubeSearchSort playlistSearchSort;
  final List<String> searchHistory;

  VideoReaction reactionFor(String videoId) {
    if (likedVideoIds.contains(videoId)) {
      return VideoReaction.like;
    }
    if (dislikedVideoIds.contains(videoId)) {
      return VideoReaction.dislike;
    }
    return VideoReaction.none;
  }

  UserProfile copyWith({
    String? name,
    List<YouTubeVideo>? favorites,
    List<YouTubeChannelResult>? favoriteChannels,
    List<VideoPlaylist>? playlists,
    Set<String>? likedVideoIds,
    Set<String>? dislikedVideoIds,
    ProfileLanguage? language,
    bool? autoplaySearchResults,
    YouTubeSearchSort? videoSearchSort,
    YouTubeSearchSort? playlistSearchSort,
    List<String>? searchHistory,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      favorites: favorites ?? this.favorites,
      favoriteChannels: favoriteChannels ?? this.favoriteChannels,
      playlists: playlists ?? this.playlists,
      likedVideoIds: likedVideoIds ?? this.likedVideoIds,
      dislikedVideoIds: dislikedVideoIds ?? this.dislikedVideoIds,
      language: language ?? this.language,
      autoplaySearchResults:
          autoplaySearchResults ?? this.autoplaySearchResults,
      videoSearchSort: videoSearchSort ?? this.videoSearchSort,
      playlistSearchSort: playlistSearchSort ?? this.playlistSearchSort,
      searchHistory: searchHistory ?? this.searchHistory,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'favorites': favorites.map((video) => video.toJson()).toList(),
    'favoriteChannels': favoriteChannels
        .map((channel) => channel.toJson())
        .toList(),
    'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
    'likedVideoIds': likedVideoIds.toList(),
    'dislikedVideoIds': dislikedVideoIds.toList(),
    'language': language.code,
    'autoplaySearchResults': autoplaySearchResults,
    'videoSearchSort': videoSearchSort.storageValue,
    'playlistSearchSort': playlistSearchSort.storageValue,
    'searchHistory': searchHistory,
  };

  static UserProfile? fromJson(Object? value) {
    if (value is! Map || value['id'] is! String || value['name'] is! String) {
      return null;
    }
    final favorites = (value['favorites'] as List? ?? const [])
        .map(YouTubeVideo.fromJson)
        .whereType<YouTubeVideo>()
        .toList(growable: false);
    final playlists = (value['playlists'] as List? ?? const [])
        .map(VideoPlaylist.fromJson)
        .whereType<VideoPlaylist>()
        .toList(growable: false);
    final favoriteChannels = (value['favoriteChannels'] as List? ?? const [])
        .map(YouTubeChannelResult.fromJson)
        .whereType<YouTubeChannelResult>()
        .toList(growable: false);
    return UserProfile(
      id: value['id'] as String,
      name: value['name'] as String,
      favorites: favorites,
      favoriteChannels: favoriteChannels,
      playlists: playlists,
      likedVideoIds: Set<String>.from(
        (value['likedVideoIds'] as List? ?? const []).whereType<String>(),
      ),
      dislikedVideoIds: Set<String>.from(
        (value['dislikedVideoIds'] as List? ?? const []).whereType<String>(),
      ),
      language: ProfileLanguage.fromCode(value['language']),
      autoplaySearchResults: value['autoplaySearchResults'] == true,
      videoSearchSort: YouTubeSearchSort.fromStorage(value['videoSearchSort']),
      playlistSearchSort: YouTubeSearchSort.fromStorage(
        value['playlistSearchSort'],
      ),
      searchHistory: sanitizeSearchHistory(
        (value['searchHistory'] as List? ?? const []).whereType<String>(),
      ),
    );
  }
}
