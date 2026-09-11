enum YouTubeSearchCategory { videos, channels, playlists }

extension YouTubeSearchCategoryLabel on YouTubeSearchCategory {
  String get label => switch (this) {
    YouTubeSearchCategory.videos => 'Videos',
    YouTubeSearchCategory.channels => 'Channels',
    YouTubeSearchCategory.playlists => 'Playlists',
  };

  String get singularLabel => switch (this) {
    YouTubeSearchCategory.videos => 'Video',
    YouTubeSearchCategory.channels => 'Channel',
    YouTubeSearchCategory.playlists => 'Playlist',
  };
}
