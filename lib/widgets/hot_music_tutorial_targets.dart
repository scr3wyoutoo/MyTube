import 'package:flutter/material.dart';

import '../models/hot_music.dart';

enum HotMusicTutorialStep {
  explore,
  charts,
  genres,
  favorite,
  playlist,
  info;

  int get number => index + 1;

  bool get hasPrevious => this != explore;

  bool get highlightsSongAction => switch (this) {
    favorite || playlist || info => true,
    explore || charts || genres => false,
  };

  HotMusicSection? get section => switch (this) {
    explore => HotMusicSection.explore,
    charts => HotMusicSection.charts,
    genres => HotMusicSection.genres,
    favorite || playlist || info => null,
  };
}

class HotMusicTutorialTargets {
  HotMusicTutorialTargets()
    : explore = GlobalKey(debugLabel: 'tutorial-hot-music-explore'),
      charts = GlobalKey(debugLabel: 'tutorial-hot-music-charts'),
      genres = GlobalKey(debugLabel: 'tutorial-hot-music-genres'),
      favorite = GlobalKey(debugLabel: 'tutorial-hot-music-favorite'),
      playlist = GlobalKey(debugLabel: 'tutorial-hot-music-playlist'),
      info = GlobalKey(debugLabel: 'tutorial-hot-music-info');

  final GlobalKey explore;
  final GlobalKey charts;
  final GlobalKey genres;
  final GlobalKey favorite;
  final GlobalKey playlist;
  final GlobalKey info;

  GlobalKey section(HotMusicSection section) => switch (section) {
    HotMusicSection.explore => explore,
    HotMusicSection.charts => charts,
    HotMusicSection.genres => genres,
  };

  GlobalKey action(HotMusicTutorialStep step) => switch (step) {
    HotMusicTutorialStep.favorite => favorite,
    HotMusicTutorialStep.playlist => playlist,
    HotMusicTutorialStep.info => info,
    HotMusicTutorialStep.explore => explore,
    HotMusicTutorialStep.charts => charts,
    HotMusicTutorialStep.genres => genres,
  };
}
