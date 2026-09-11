import 'package:youtube_explode_dart/youtube_explode_dart.dart' as explode;

import '../models/youtube_search_sort.dart';

explode.SearchFilter youtubeExplodeVideoSearchFilter(YouTubeSearchSort sort) {
  return explode.SearchFilter(switch (sort) {
    YouTubeSearchSort.relevance => 'CAASAhAB',
    YouTubeSearchSort.uploadDate => 'CAISAhAB',
    YouTubeSearchSort.viewCount => 'CAMSAhAB',
    YouTubeSearchSort.rating => 'CAESAhAB',
  });
}

explode.SearchFilter youtubeExplodePlaylistSearchFilter(
  YouTubeSearchSort sort,
) {
  return explode.SearchFilter(switch (sort) {
    YouTubeSearchSort.relevance => 'CAASAhAD',
    YouTubeSearchSort.uploadDate => 'CAISAhAD',
    YouTubeSearchSort.viewCount => 'CAMSAhAD',
    YouTubeSearchSort.rating => 'CAESAhAD',
  });
}
