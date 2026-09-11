import 'youtube_video.dart';

enum VideoSearchSource { youtube, youtubeMusic }

VideoSearchSource videoSearchSourceForMedia(YouTubeVideo video) =>
    video.isMusic ? VideoSearchSource.youtubeMusic : VideoSearchSource.youtube;

extension VideoSearchSourceLabel on VideoSearchSource {
  String get label => switch (this) {
    VideoSearchSource.youtube => 'YouTube',
    VideoSearchSource.youtubeMusic => 'YouTube Music',
  };

  String get searchLabel => switch (this) {
    VideoSearchSource.youtube => 'YouTube-Suche',
    VideoSearchSource.youtubeMusic => 'YouTube-Music-Suche',
  };

  String get searchHint => switch (this) {
    VideoSearchSource.youtube => 'Suchbegriff eingeben',
    VideoSearchSource.youtubeMusic => 'Song, Künstler oder Album',
  };
}
