import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/user_profile.dart';
import '../models/youtube_catalog_item.dart';
import '../models/youtube_video.dart';
import '../services/playlist_import_loader.dart';
import '../services/profile_controller.dart';
import '../services/youtube_search_repository.dart';

Future<bool> showCreateProfileDialog(
  BuildContext context,
  ProfileController controller,
) async {
  var name = '';
  var language = controller.activeProfile?.language ?? ProfileLanguage.english;
  String? errorText;
  final created = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.l10n.newProfile),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('profile-name-field'),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: context.l10n.profileName,
                hintText: context.l10n.profileNameHint,
                errorText: errorText,
              ),
              onChanged: (value) => name = value,
              onFieldSubmitted: (_) => _createProfile(
                dialogContext,
                controller,
                name,
                language,
                (error) => setDialogState(() => errorText = error),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ProfileLanguage>(
              key: const Key('profile-language-field'),
              initialValue: language,
              decoration: InputDecoration(labelText: context.l10n.language),
              items: ProfileLanguage.values
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.label)),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  language = value;
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const Key('create-profile-button'),
            onPressed: () => _createProfile(
              dialogContext,
              controller,
              name,
              language,
              (error) => setDialogState(() => errorText = error),
            ),
            child: Text(context.l10n.create),
          ),
        ],
      ),
    ),
  );
  return created ?? false;
}

Future<void> _createProfile(
  BuildContext dialogContext,
  ProfileController controller,
  String name,
  ProfileLanguage language,
  ValueChanged<String?> showError,
) async {
  final error = controller.validateProfileName(name);
  if (error != null) {
    showError(dialogContext.l10n.translateKnownMessage(error));
    return;
  }
  await controller.createProfile(name, language: language);
  if (dialogContext.mounted) {
    Navigator.of(dialogContext).pop(true);
  }
}

Future<VideoPlaylist?> showCreatePlaylistDialog(
  BuildContext context,
  ProfileController controller, {
  String initialName = '',
}) async {
  var name = initialName;
  String? errorText;
  final playlist = await showDialog<VideoPlaylist>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.l10n.newPlaylist),
        content: TextFormField(
          key: const Key('playlist-name-field'),
          initialValue: initialName,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: context.l10n.playlistName,
            errorText: errorText,
          ),
          onChanged: (value) => name = value,
          onFieldSubmitted: (_) => _createPlaylist(
            dialogContext,
            controller,
            name,
            (error) => setDialogState(() => errorText = error),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const Key('create-playlist-button'),
            onPressed: () => _createPlaylist(
              dialogContext,
              controller,
              name,
              (error) => setDialogState(() => errorText = error),
            ),
            child: Text(context.l10n.create),
          ),
        ],
      ),
    ),
  );
  return playlist;
}

Future<void> showRenamePlaylistDialog(
  BuildContext context,
  ProfileController controller,
  VideoPlaylist playlist,
) async {
  var name = playlist.name;
  String? errorText;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.l10n.renamePlaylist),
        content: TextFormField(
          key: const Key('rename-playlist-name-field'),
          initialValue: playlist.name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: context.l10n.newName,
            errorText: errorText,
          ),
          onChanged: (value) => name = value,
          onFieldSubmitted: (_) => _renamePlaylist(
            dialogContext,
            controller,
            playlist,
            name,
            (error) => setDialogState(() => errorText = error),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const Key('rename-playlist-button'),
            onPressed: () => _renamePlaylist(
              dialogContext,
              controller,
              playlist,
              name,
              (error) => setDialogState(() => errorText = error),
            ),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    ),
  );
}

Future<void> _renamePlaylist(
  BuildContext dialogContext,
  ProfileController controller,
  VideoPlaylist playlist,
  String name,
  ValueChanged<String?> showError,
) async {
  final error = controller.validatePlaylistName(
    name,
    excludingPlaylistId: playlist.id,
  );
  if (error != null) {
    showError(dialogContext.l10n.translateKnownMessage(error));
    return;
  }
  await controller.renamePlaylist(playlist.id, name);
  if (dialogContext.mounted) {
    Navigator.of(dialogContext).pop();
  }
}

Future<void> _createPlaylist(
  BuildContext dialogContext,
  ProfileController controller,
  String name,
  ValueChanged<String?> showError,
) async {
  final error = controller.validatePlaylistName(name);
  if (error != null) {
    showError(dialogContext.l10n.translateKnownMessage(error));
    return;
  }
  final playlist = await controller.createPlaylist(name);
  if (dialogContext.mounted) {
    Navigator.of(dialogContext).pop(playlist);
  }
}

Future<void> showAddToPlaylistDialog(
  BuildContext context,
  ProfileController controller,
  YouTubeVideo video,
) async {
  await showAddVideosToPlaylistDialog(context, controller, [
    video,
  ], singleVideo: true);
}

Future<void> showAddVideosToPlaylistDialog(
  BuildContext context,
  ProfileController controller,
  List<YouTubeVideo> videos, {
  String suggestedPlaylistName = '',
  bool singleVideo = false,
}) async {
  if (videos.isEmpty) {
    return;
  }
  if (controller.activeProfile == null) {
    final created = await showCreateProfileDialog(context, controller);
    if (!created || !context.mounted) {
      return;
    }
  }

  final selectedPlaylist = await showDialog<VideoPlaylist>(
    context: context,
    builder: (dialogContext) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final playlists = controller.activeProfile?.playlists ?? const [];
        return AlertDialog(
          title: Text(context.l10n.addToPlaylist),
          content: SizedBox(
            width: 420,
            child: playlists.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(context.l10n.noPlaylistsCreated),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final existingIds = playlist.videos
                          .map((video) => video.id)
                          .toSet();
                      final addableCount = videos
                          .map((video) => video.id)
                          .toSet()
                          .where((id) => !existingIds.contains(id))
                          .length;
                      final alreadyAdded = addableCount == 0;
                      return ListTile(
                        leading: const Icon(Icons.playlist_play),
                        title: Text(playlist.name),
                        subtitle: Text(
                          singleVideo
                              ? context.l10n.videoCount(playlist.videos.length)
                              : context.l10n.newContentCount(
                                  playlist.videos.length,
                                  addableCount,
                                ),
                        ),
                        trailing: alreadyAdded
                            ? const Icon(Icons.check_circle)
                            : const Icon(Icons.add_circle_outline),
                        enabled: !alreadyAdded,
                        onTap: alreadyAdded
                            ? null
                            : () => Navigator.of(dialogContext).pop(playlist),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final created = await showCreatePlaylistDialog(
                  dialogContext,
                  controller,
                  initialName: suggestedPlaylistName,
                );
                if (created != null && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(created);
                }
              },
              icon: const Icon(Icons.add),
              label: Text(context.l10n.newPlaylist),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.close),
            ),
          ],
        );
      },
    ),
  );

  if (selectedPlaylist == null) {
    return;
  }
  final addedCount = await controller.addVideosToPlaylist(
    selectedPlaylist.id,
    videos,
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          addedCount > 0
              ? context.l10n.addedToPlaylist(
                  selectedPlaylist.name,
                  single: singleVideo,
                  count: addedCount,
                )
              : context.l10n.alreadyInPlaylist(
                  selectedPlaylist.name,
                  single: singleVideo,
                ),
        ),
      ),
    );
  }
}

Future<void> showImportCatalogPlaylistDialog(
  BuildContext context,
  ProfileController controller,
  YouTubePlaylistResult playlist, {
  required PlaylistPageLoader loadPage,
}) async {
  if (controller.activeProfile == null) {
    final created = await showCreateProfileDialog(context, controller);
    if (!created || !context.mounted) {
      return;
    }
  }

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(dialogContext.l10n.playlistLoading),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(dialogContext.l10n.fetchingAllItems)),
            ],
          ),
        ),
      ),
    ),
  );

  final List<YouTubeVideo> videos;
  try {
    videos = await const PlaylistImportLoader().loadAll(loadPage);
  } on PlaylistImportException catch (error) {
    if (!context.mounted) {
      return;
    }
    _finishPlaylistImportWithError(context, error.message);
    return;
  } on YouTubeSearchException catch (error) {
    if (!context.mounted) {
      return;
    }
    _finishPlaylistImportWithError(context, error.message);
    return;
  } on Object {
    if (!context.mounted) {
      return;
    }
    _finishPlaylistImportWithError(context, context.l10n.playlistLoadFailed);
    return;
  }

  if (!context.mounted) {
    return;
  }
  Navigator.of(context, rootNavigator: true).pop();
  if (videos.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.playlistEmpty)));
    return;
  }
  await showAddVideosToPlaylistDialog(
    context,
    controller,
    videos,
    suggestedPlaylistName: playlist.title,
  );
}

void _finishPlaylistImportWithError(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  Navigator.of(context, rootNavigator: true).pop();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.l10n.translateKnownMessage(message))),
  );
}
