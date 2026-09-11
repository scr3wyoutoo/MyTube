import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class PlayerTransportControls extends StatelessWidget {
  const PlayerTransportControls({
    super.key,
    required this.playing,
    required this.previousEnabled,
    required this.nextEnabled,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    required this.showPictureInPicture,
    required this.onPictureInPicture,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onOpenSettings,
    this.tutorialKey,
    this.settingsTutorialKey,
  });

  final bool playing;
  final bool previousEnabled;
  final bool nextEnabled;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlayback;
  final VoidCallback onNext;
  final bool showPictureInPicture;
  final VoidCallback? onPictureInPicture;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onOpenSettings;
  final Key? tutorialKey;
  final Key? settingsTutorialKey;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: tutorialKey,
      child: Row(
        key: const Key('player-transport-controls'),
        children: [
          const SizedBox(width: 4),
          IconButton(
            key: const Key('player-history-back-button'),
            tooltip: context.l10n.previousTitle,
            onPressed: previousEnabled ? onPrevious : null,
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton(
            key: const Key('player-play-pause-button'),
            tooltip: playing ? context.l10n.pause : context.l10n.play,
            onPressed: onTogglePlayback,
            color: Colors.white,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(
            key: const Key('player-forward-button'),
            tooltip: context.l10n.nextTitle,
            onPressed: nextEnabled ? onNext : null,
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.skip_next),
          ),
          const Spacer(),
          if (showPictureInPicture)
            IconButton(
              key: const Key('picture-in-picture-button'),
              tooltip: context.l10n.pictureInPicture,
              onPressed: onPictureInPicture,
              color: Colors.white,
              disabledColor: Colors.white38,
              icon: const Icon(Icons.picture_in_picture_alt),
            ),
          IconButton(
            key: const Key('fullscreen-button'),
            tooltip: fullscreen
                ? context.l10n.exitFullscreen
                : context.l10n.fullscreen,
            onPressed: onToggleFullscreen,
            color: Colors.white,
            icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
          ),
          KeyedSubtree(
            key: settingsTutorialKey,
            child: IconButton(
              key: const Key('player-settings-button'),
              tooltip: context.l10n.moreOptions,
              onPressed: onOpenSettings,
              color: Colors.white,
              icon: const Icon(Icons.more_vert),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
