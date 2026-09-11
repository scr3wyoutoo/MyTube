import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/user_profile.dart';
import '../models/youtube_catalog_item.dart';
import '../models/youtube_video.dart';
import '../services/profile_controller.dart';
import '../services/app_log.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/video_result_card.dart';
import '../widgets/youtube_catalog_result_card.dart';

typedef ProfileVideoSelected =
    void Function(YouTubeVideo video, List<YouTubeVideo> contextVideos);
typedef ProfilePlaylistSelected =
    void Function(VideoPlaylist playlist, int startIndex);
typedef ProfileChannelSelected = void Function(YouTubeChannelResult channel);

class ProfileTutorialTargets {
  ProfileTutorialTargets()
    : createProfile = GlobalKey(debugLabel: 'tutorial-create-profile'),
      favorites = GlobalKey(debugLabel: 'tutorial-profile-favorites'),
      playlists = GlobalKey(debugLabel: 'tutorial-profile-playlists'),
      channels = GlobalKey(debugLabel: 'tutorial-profile-channels'),
      addProfile = GlobalKey(debugLabel: 'tutorial-add-profile'),
      profileMenu = GlobalKey(debugLabel: 'tutorial-profile-menu');

  final GlobalKey createProfile;
  final GlobalKey favorites;
  final GlobalKey playlists;
  final GlobalKey channels;
  final GlobalKey addProfile;
  final GlobalKey profileMenu;
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.controller,
    required this.onVideoSelected,
    required this.onPlaylistSelected,
    required this.onChannelSelected,
    this.tutorialTargets,
    this.showTutorialMenuPreview = false,
    this.onTutorialMenuOpened,
    this.onTutorialMenuClosed,
    this.onRestartTutorial,
  });

  final ProfileController controller;
  final ProfileVideoSelected onVideoSelected;
  final ProfilePlaylistSelected onPlaylistSelected;
  final ProfileChannelSelected onChannelSelected;
  final ProfileTutorialTargets? tutorialTargets;
  final bool showTutorialMenuPreview;
  final VoidCallback? onTutorialMenuOpened;
  final VoidCallback? onTutorialMenuClosed;
  final Future<void> Function()? onRestartTutorial;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final profile = controller.activeProfile;
        if (profile == null) {
          return _EmptyProfile(
            tutorialTargetKey: tutorialTargets?.createProfile,
            onCreate: () => showCreateProfileDialog(context, controller),
          );
        }
        return Column(
          children: [
            _ProfileHeader(
              controller: controller,
              profile: profile,
              tutorialTargets: tutorialTargets,
              showTutorialMenuPreview: showTutorialMenuPreview,
              onTutorialMenuOpened: onTutorialMenuOpened,
              onTutorialMenuClosed: onTutorialMenuClosed,
              onRestartTutorial: onRestartTutorial,
            ),
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(
                          key: tutorialTargets?.playlists,
                          icon: const Icon(Icons.queue_music),
                          text: context.l10n.playlists,
                        ),
                        Tab(
                          key: tutorialTargets?.favorites,
                          icon: const Icon(Icons.favorite),
                          text: context.l10n.favorites,
                        ),
                        Tab(
                          key: tutorialTargets?.channels,
                          icon: const Icon(Icons.subscriptions),
                          text: context.l10n.channels,
                        ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _PlaylistsView(
                            profile: profile,
                            controller: controller,
                            onPlaylistSelected: onPlaylistSelected,
                          ),
                          _FavoritesView(
                            profile: profile,
                            controller: controller,
                            onVideoSelected: onVideoSelected,
                          ),
                          _ChannelsView(
                            profile: profile,
                            controller: controller,
                            onChannelSelected: onChannelSelected,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.controller,
    required this.profile,
    this.tutorialTargets,
    this.showTutorialMenuPreview = false,
    this.onTutorialMenuOpened,
    this.onTutorialMenuClosed,
    this.onRestartTutorial,
  });

  final ProfileController controller;
  final UserProfile profile;
  final ProfileTutorialTargets? tutorialTargets;
  final bool showTutorialMenuPreview;
  final VoidCallback? onTutorialMenuOpened;
  final VoidCallback? onTutorialMenuClosed;
  final Future<void> Function()? onRestartTutorial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          KeyedSubtree(
            key: tutorialTargets?.profileMenu,
            child: PopupMenuButton<_ProfileMenuAction>(
              key: const Key('profile-avatar-menu'),
              tooltip: context.l10n.profileMenu,
              onOpened: onTutorialMenuOpened,
              onCanceled: onTutorialMenuClosed,
              onSelected: (action) async {
                if (showTutorialMenuPreview) {
                  onTutorialMenuClosed?.call();
                  return;
                }
                switch (action) {
                  case _ProfileMenuAction.language:
                    await _showLanguageDialog(context, controller, profile);
                  case _ProfileMenuAction.tutorial:
                    final restart = onRestartTutorial;
                    if (restart == null) {
                      await controller.restartTutorial();
                    } else {
                      await restart();
                    }
                  case _ProfileMenuAction.logFile:
                    await _showLogFileDialog(context);
                  case _ProfileMenuAction.delete:
                    await _confirmDeleteProfile(context, controller, profile);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const Key('profile-language-menu-item'),
                  value: _ProfileMenuAction.language,
                  enabled: !showTutorialMenuPreview,
                  child: _ProfileMenuItem(
                    icon: Icons.translate,
                    title: context.l10n.language,
                    description: showTutorialMenuPreview
                        ? context.l10n.profileTutorialLanguageDescription
                        : null,
                  ),
                ),
                PopupMenuItem(
                  key: const Key('restart-tutorial-menu-item'),
                  value: _ProfileMenuAction.tutorial,
                  enabled: !showTutorialMenuPreview,
                  child: _ProfileMenuItem(
                    icon: Icons.school_outlined,
                    title: context.l10n.repeatTutorial,
                    description: showTutorialMenuPreview
                        ? context.l10n.profileTutorialRepeatDescription
                        : null,
                  ),
                ),
                PopupMenuItem(
                  key: const Key('log-file-menu-item'),
                  value: _ProfileMenuAction.logFile,
                  enabled: !showTutorialMenuPreview,
                  child: _ProfileMenuItem(
                    icon: Icons.description_outlined,
                    title: context.l10n.logFile,
                  ),
                ),
                PopupMenuItem(
                  key: const Key('delete-profile-menu-item'),
                  value: _ProfileMenuAction.delete,
                  enabled: !showTutorialMenuPreview,
                  child: _ProfileMenuItem(
                    icon: Icons.delete_outline,
                    title: context.l10n.deleteProfile,
                    description: showTutorialMenuPreview
                        ? context.l10n.profileTutorialDeleteDescription
                        : null,
                  ),
                ),
              ],
              child: CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  profile.name.characters.first.toUpperCase(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: context.l10n.activeProfile,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('profile-selector'),
                  value: profile.id,
                  isExpanded: true,
                  isDense: true,
                  items: controller.profiles
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (profileId) {
                    if (profileId != null) {
                      controller.selectProfile(profileId);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          KeyedSubtree(
            key: tutorialTargets?.addProfile,
            child: IconButton.filledTonal(
              key: const Key('add-profile-button'),
              tooltip: context.l10n.newProfile,
              onPressed: () => showCreateProfileDialog(context, controller),
              icon: const Icon(Icons.person_add_alt_1),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ProfileMenuAction { language, tutorial, logFile, delete }

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    this.description,
  });

  final IconData icon;
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon)),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _showLanguageDialog(
  BuildContext context,
  ProfileController controller,
  UserProfile profile,
) async {
  final language = await showDialog<ProfileLanguage>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.language),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: ProfileLanguage.values
            .map(
              (language) => ListTile(
                key: ValueKey('profile-language-${language.code}'),
                leading: Icon(
                  language == profile.language
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(language.label),
                onTap: () => Navigator.of(dialogContext).pop(language),
              ),
            )
            .toList(growable: false),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.l10n.cancel),
        ),
      ],
    ),
  );
  if (language != null) {
    await controller.setLanguage(language);
  }
}

Future<void> _showLogFileDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AppLogDialog());

class _AppLogDialog extends StatefulWidget {
  const _AppLogDialog();

  @override
  State<_AppLogDialog> createState() => _AppLogDialogState();
}

class _AppLogDialogState extends State<_AppLogDialog> {
  final ScrollController _scrollController = ScrollController();
  String _contents = '';
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    AppLog.instance.info('diagnostics.log_viewer.opened');
    try {
      final contents = await AppLog.instance.read();
      if (!mounted) {
        return;
      }
      setState(() {
        _contents = contents;
        _loading = false;
      });
      _scrollToNewestEntry();
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'diagnostics.log_file.read_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  void _scrollToNewestEntry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _clear() async {
    try {
      await AppLog.instance.clear();
      if (mounted) {
        setState(() {
          _contents = '';
          _loadFailed = false;
        });
      }
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'diagnostics.log_file.clear_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _loadFailed = true);
      }
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _contents));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.logFileCopied)));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _loadFailed
        ? context.l10n.logFileLoadFailed
        : _contents.isEmpty
        ? context.l10n.logFileEmpty
        : _contents;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.logFile,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            key: const Key('log-file-scroll-view'),
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              text,
                              key: const Key('log-file-contents'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontFamily: 'monospace'),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    key: const Key('clear-log-file-button'),
                    onPressed: _loading ? null : _clear,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(context.l10n.clearLogFile),
                  ),
                  TextButton.icon(
                    key: const Key('copy-log-file-button'),
                    onPressed: _loading || _loadFailed ? null : _copy,
                    icon: const Icon(Icons.copy),
                    label: Text(context.l10n.copy),
                  ),
                  FilledButton(
                    key: const Key('close-log-file-button'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.close),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmDeleteProfile(
  BuildContext context,
  ProfileController controller,
  UserProfile profile,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.deleteProfileQuestion),
      content: Text(dialogContext.l10n.deleteProfileMessage(profile.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.l10n.cancel),
        ),
        FilledButton(
          key: const Key('confirm-delete-profile-button'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.l10n.deleteProfile),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.deleteProfile(profile.id);
  }
}

class _EmptyProfile extends StatelessWidget {
  const _EmptyProfile({required this.onCreate, this.tutorialTargetKey});

  final VoidCallback onCreate;
  final GlobalKey? tutorialTargetKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.personalArea,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.createProfileDescription,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            KeyedSubtree(
              key: tutorialTargetKey,
              child: FilledButton.icon(
                key: const Key('first-profile-button'),
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: Text(context.l10n.createProfile),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesView extends StatelessWidget {
  const _FavoritesView({
    required this.profile,
    required this.controller,
    required this.onVideoSelected,
  });

  final UserProfile profile;
  final ProfileController controller;
  final ProfileVideoSelected onVideoSelected;

  @override
  Widget build(BuildContext context) {
    if (profile.favorites.isEmpty) {
      return _LibraryEmptyState(
        icon: Icons.favorite_border,
        message: context.l10n.noFavorites,
      );
    }
    return ListView.separated(
      key: const Key('profile-favorites-list'),
      padding: const EdgeInsets.all(12),
      itemCount: profile.favorites.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final video = profile.favorites[index];
        return VideoResultCard(
          video: video,
          compact: true,
          onTap: () => onVideoSelected(video, profile.favorites),
          trailing: IconButton(
            tooltip: context.l10n.removeFromFavorites,
            onPressed: () => controller.toggleFavorite(video),
            icon: const Icon(Icons.favorite, color: Colors.red),
          ),
        );
      },
    );
  }
}

class _ChannelsView extends StatelessWidget {
  const _ChannelsView({
    required this.profile,
    required this.controller,
    required this.onChannelSelected,
  });

  final UserProfile profile;
  final ProfileController controller;
  final ProfileChannelSelected onChannelSelected;

  @override
  Widget build(BuildContext context) {
    if (profile.favoriteChannels.isEmpty) {
      return _LibraryEmptyState(
        icon: Icons.subscriptions_outlined,
        message: context.l10n.noChannels,
      );
    }
    return ListView.separated(
      key: const Key('profile-channels-list'),
      padding: const EdgeInsets.all(12),
      itemCount: profile.favoriteChannels.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final channel = profile.favoriteChannels[index];
        return YouTubeChannelResultCard(
          key: ValueKey('profile-channel-${channel.id}'),
          channel: channel,
          onTap: () => onChannelSelected(channel),
          isFavorite: true,
          onToggleFavorite: () => controller.toggleFavoriteChannel(channel),
        );
      },
    );
  }
}

class _PlaylistsView extends StatelessWidget {
  const _PlaylistsView({
    required this.profile,
    required this.controller,
    required this.onPlaylistSelected,
  });

  final UserProfile profile;
  final ProfileController controller;
  final ProfilePlaylistSelected onPlaylistSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              key: const Key('new-playlist-button'),
              onPressed: () => showCreatePlaylistDialog(context, controller),
              icon: const Icon(Icons.playlist_add),
              label: Text(context.l10n.newPlaylist),
            ),
          ),
        ),
        Expanded(
          child: profile.playlists.isEmpty
              ? _LibraryEmptyState(
                  icon: Icons.queue_music,
                  message: context.l10n.noPlaylists,
                )
              : ListView.separated(
                  key: const Key('profile-playlists-list'),
                  padding: const EdgeInsets.all(12),
                  itemCount: profile.playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final playlist = profile.playlists[index];
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ExpansionTile(
                        key: PageStorageKey('playlist-${playlist.id}'),
                        leading: CircleAvatar(
                          child: Text('${playlist.videos.length}'),
                        ),
                        title: Text(
                          playlist.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          context.l10n.videoCount(playlist.videos.length),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: context.l10n.playPlaylist,
                              onPressed: playlist.videos.isEmpty
                                  ? null
                                  : () => onPlaylistSelected(playlist, 0),
                              icon: const Icon(Icons.play_circle_fill),
                            ),
                            PopupMenuButton<String>(
                              key: ValueKey('playlist-menu-${playlist.id}'),
                              onSelected: (value) {
                                if (value == 'rename') {
                                  showRenamePlaylistDialog(
                                    context,
                                    controller,
                                    playlist,
                                  );
                                } else if (value == 'delete') {
                                  _confirmDeletePlaylist(
                                    context,
                                    controller,
                                    playlist,
                                  );
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  key: const Key('rename-playlist-menu-item'),
                                  value: 'rename',
                                  child: ListTile(
                                    leading: const Icon(Icons.edit_outlined),
                                    title: Text(context.l10n.rename),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: const Icon(Icons.delete_outline),
                                    title: Text(context.l10n.delete),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        children: [
                          if (playlist.videos.isEmpty)
                            ListTile(
                              title: Text(context.l10n.addVideosFromPlayer),
                            )
                          else
                            ReorderableListView.builder(
                              key: PageStorageKey(
                                'playlist-order-${playlist.id}',
                              ),
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              itemCount: playlist.videos.length,
                              onReorder: (oldIndex, newIndex) =>
                                  controller.reorderPlaylistVideo(
                                    playlist.id,
                                    oldIndex,
                                    newIndex,
                                  ),
                              itemBuilder: (context, videoIndex) {
                                final video = playlist.videos[videoIndex];
                                return ListTile(
                                  key: ValueKey('${playlist.id}-${video.id}'),
                                  leading: ReorderableDragStartListener(
                                    key: ValueKey(
                                      'playlist-drag-${playlist.id}-${video.id}',
                                    ),
                                    index: videoIndex,
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.drag_handle),
                                    ),
                                  ),
                                  title: Text(
                                    video.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () =>
                                      onPlaylistSelected(playlist, videoIndex),
                                  trailing: IconButton(
                                    tooltip: context.l10n.removeFromPlaylist,
                                    onPressed: () =>
                                        controller.removeVideoFromPlaylist(
                                          playlist.id,
                                          video.id,
                                        ),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<void> _confirmDeletePlaylist(
  BuildContext context,
  ProfileController controller,
  VideoPlaylist playlist,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.deletePlaylistTitle),
      content: Text(dialogContext.l10n.deletePlaylistQuestion(playlist.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.deletePlaylist(playlist.id);
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 50, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message),
        ],
      ),
    );
  }
}
