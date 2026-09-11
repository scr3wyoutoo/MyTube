import 'package:flutter/material.dart';

import '../models/youtube_search_category.dart';

class SearchTutorialTargets {
  SearchTutorialTargets()
    : sourceSelector = GlobalKey(debugLabel: 'tutorial-search-source'),
      searchButton = GlobalKey(debugLabel: 'tutorial-search-button'),
      videos = GlobalKey(debugLabel: 'tutorial-search-videos'),
      channels = GlobalKey(debugLabel: 'tutorial-search-channels'),
      playlists = GlobalKey(debugLabel: 'tutorial-search-playlists');

  final GlobalKey sourceSelector;
  final GlobalKey searchButton;
  final GlobalKey videos;
  final GlobalKey channels;
  final GlobalKey playlists;

  GlobalKey category(YouTubeSearchCategory category) => switch (category) {
    YouTubeSearchCategory.videos => videos,
    YouTubeSearchCategory.channels => channels,
    YouTubeSearchCategory.playlists => playlists,
  };
}
