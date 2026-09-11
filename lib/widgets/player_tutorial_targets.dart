import 'package:flutter/material.dart';

enum PlayerTutorialStep {
  centerPlayback,
  doubleTapSeek,
  holdSeek,
  transport,
  options,
  autoplay,
  shuffle,
  reactions,
  favorite,
  playlist,
  info;

  int get number => index + 1;

  bool get hasPrevious => this != centerPlayback;
}

class PlayerTutorialTargets {
  PlayerTutorialTargets()
    : leftSurface = GlobalKey(debugLabel: 'tutorial-player-left-surface'),
      centerSurface = GlobalKey(debugLabel: 'tutorial-player-center-surface'),
      rightSurface = GlobalKey(debugLabel: 'tutorial-player-right-surface'),
      transport = GlobalKey(debugLabel: 'tutorial-player-transport'),
      options = GlobalKey(debugLabel: 'tutorial-player-options'),
      autoplay = GlobalKey(debugLabel: 'tutorial-player-autoplay'),
      shuffle = GlobalKey(debugLabel: 'tutorial-player-shuffle'),
      reactions = GlobalKey(debugLabel: 'tutorial-player-reactions'),
      favorite = GlobalKey(debugLabel: 'tutorial-player-favorite'),
      playlist = GlobalKey(debugLabel: 'tutorial-player-playlist'),
      info = GlobalKey(debugLabel: 'tutorial-player-info');

  final GlobalKey leftSurface;
  final GlobalKey centerSurface;
  final GlobalKey rightSurface;
  final GlobalKey transport;
  final GlobalKey options;
  final GlobalKey autoplay;
  final GlobalKey shuffle;
  final GlobalKey reactions;
  final GlobalKey favorite;
  final GlobalKey playlist;
  final GlobalKey info;

  GlobalKey target(PlayerTutorialStep step) => switch (step) {
    PlayerTutorialStep.centerPlayback => centerSurface,
    PlayerTutorialStep.doubleTapSeek ||
    PlayerTutorialStep.holdSeek => leftSurface,
    PlayerTutorialStep.transport => transport,
    PlayerTutorialStep.options => options,
    PlayerTutorialStep.autoplay => autoplay,
    PlayerTutorialStep.shuffle => shuffle,
    PlayerTutorialStep.reactions => reactions,
    PlayerTutorialStep.favorite => favorite,
    PlayerTutorialStep.playlist => playlist,
    PlayerTutorialStep.info => info,
  };

  List<GlobalKey> additionalTargets(PlayerTutorialStep step) => switch (step) {
    PlayerTutorialStep.doubleTapSeek ||
    PlayerTutorialStep.holdSeek => [rightSurface],
    _ => const [],
  };
}
