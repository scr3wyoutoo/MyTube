import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_tutorial_stage.dart';
import '../models/user_profile.dart';
import '../models/search_history.dart';
import '../models/youtube_catalog_item.dart';
import '../models/youtube_search_sort.dart';
import '../models/youtube_video.dart';
import 'app_log.dart';

abstract interface class ProfileStorage {
  Future<String?> read();

  Future<void> write(String value);
}

class SharedPreferencesProfileStorage implements ProfileStorage {
  static const _storageKey = 'local_profiles_v1';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_storageKey);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, value);
  }
}

class MemoryProfileStorage implements ProfileStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

class ProfileController extends ChangeNotifier {
  ProfileController._(
    this._storage, {
    List<UserProfile> profiles = const [],
    String? activeProfileId,
    Set<AppTutorialStage> completedTutorialStages = const {},
    bool tutorialCompleted = false,
    this.tutorialsEnabled = true,
  }) : _profiles = List<UserProfile>.of(profiles),
       _activeProfileId = activeProfileId,
       _completedTutorialStages = Set<AppTutorialStage>.of(
         completedTutorialStages,
       ),
       _tutorialCompleted = tutorialCompleted;

  final ProfileStorage _storage;
  List<UserProfile> _profiles;
  String? _activeProfileId;
  Set<AppTutorialStage> _completedTutorialStages;
  bool _tutorialCompleted;
  bool _manualTutorialReplayActive = false;
  final bool tutorialsEnabled;
  int _idSequence = 0;
  Future<void> _pendingWrite = Future<void>.value();

  static Future<ProfileController> load({ProfileStorage? storage}) async {
    final resolvedStorage = storage ?? SharedPreferencesProfileStorage();
    final rawData = await resolvedStorage.read();
    if (rawData == null || rawData.isEmpty) {
      return ProfileController._(resolvedStorage);
    }
    try {
      final data = jsonDecode(rawData);
      if (data is! Map) {
        return ProfileController._(resolvedStorage);
      }
      final profiles = (data['profiles'] as List? ?? const [])
          .map(UserProfile.fromJson)
          .whereType<UserProfile>()
          .toList(growable: false);
      final requestedActiveId = data['activeProfileId'];
      final activeId =
          requestedActiveId is String &&
              profiles.any((profile) => profile.id == requestedActiveId)
          ? requestedActiveId
          : profiles.firstOrNull?.id;
      final storedCompletedTutorialStages =
          data['completedTutorialStages'] as List? ?? const [];
      final completedTutorialStages = tutorialCompletionPersistenceEnabled
          ? storedCompletedTutorialStages
                .map(AppTutorialStageStorage.fromStorageKey)
                .whereType<AppTutorialStage>()
                .toSet()
          : <AppTutorialStage>{};
      final tutorialCompleted =
          tutorialCompletionPersistenceEnabled &&
          (data['tutorialCompleted'] == true ||
              AppTutorialStage.values.every(completedTutorialStages.contains));
      if (tutorialCompleted) {
        completedTutorialStages.addAll(AppTutorialStage.values);
      }
      final controller = ProfileController._(
        resolvedStorage,
        profiles: profiles,
        activeProfileId: activeId,
        completedTutorialStages: completedTutorialStages,
        tutorialCompleted: tutorialCompleted,
      );
      if (!tutorialCompletionPersistenceEnabled &&
          storedCompletedTutorialStages.isNotEmpty) {
        await controller._persist();
      }
      return controller;
    } on FormatException {
      return ProfileController._(resolvedStorage);
    }
  }

  factory ProfileController.inMemory({bool tutorialsEnabled = false}) {
    return ProfileController._(
      MemoryProfileStorage(),
      tutorialsEnabled: tutorialsEnabled,
    );
  }

  List<UserProfile> get profiles => List.unmodifiable(_profiles);

  String? get activeProfileId => _activeProfileId;

  bool isTutorialStageCompleted(AppTutorialStage stage) =>
      _completedTutorialStages.contains(stage);

  bool get tutorialCompleted => _tutorialCompleted;

  bool shouldShowTutorialStage(AppTutorialStage stage) =>
      tutorialsEnabled &&
      (_manualTutorialReplayActive || !_tutorialCompleted) &&
      !isTutorialStageCompleted(stage);

  Future<void> completeTutorialStage(AppTutorialStage stage) async {
    if (!_completedTutorialStages.add(stage)) {
      return;
    }
    if (AppTutorialStage.values.every(_completedTutorialStages.contains)) {
      _tutorialCompleted = true;
      _manualTutorialReplayActive = false;
    }
    notifyListeners();
    await _persist();
    AppLog.instance.info(
      'tutorial.stage.completed',
      fields: {'stage': stage.name, 'allCompleted': _tutorialCompleted},
    );
  }

  Future<void> completeAllTutorialStages() async {
    final alreadyComplete =
        _tutorialCompleted &&
        !_manualTutorialReplayActive &&
        AppTutorialStage.values.every(_completedTutorialStages.contains);
    if (alreadyComplete) {
      return;
    }
    _completedTutorialStages.addAll(AppTutorialStage.values);
    _tutorialCompleted = true;
    _manualTutorialReplayActive = false;
    notifyListeners();
    await _persist();
    AppLog.instance.info('tutorial.all_skipped');
  }

  Future<void> restartTutorial() async {
    if (_completedTutorialStages.isEmpty) {
      return;
    }
    _completedTutorialStages.clear();
    _manualTutorialReplayActive = true;
    notifyListeners();
    await _persist();
    AppLog.instance.info('tutorial.restarted');
  }

  UserProfile? get activeProfile {
    final activeId = _activeProfileId;
    if (activeId == null) {
      return null;
    }
    for (final profile in _profiles) {
      if (profile.id == activeId) {
        return profile;
      }
    }
    return null;
  }

  String? validateProfileName(String value) {
    final name = value.trim();
    if (name.isEmpty) {
      return 'Bitte gib einen Profilnamen ein.';
    }
    if (_profiles.any(
      (profile) => profile.name.toLowerCase() == name.toLowerCase(),
    )) {
      return 'Dieser Profilname ist auf dem Gerät bereits vergeben.';
    }
    return null;
  }

  String? validatePlaylistName(String value, {String? excludingPlaylistId}) {
    final name = value.trim();
    if (name.isEmpty) {
      return 'Bitte gib einen Namen für die Playlist ein.';
    }
    if (activeProfile?.playlists.any(
          (playlist) =>
              playlist.id != excludingPlaylistId &&
              playlist.name.toLowerCase() == name.toLowerCase(),
        ) ==
        true) {
      return 'In diesem Profil gibt es bereits eine Playlist mit diesem Namen.';
    }
    return null;
  }

  Future<void> createProfile(
    String value, {
    ProfileLanguage language = ProfileLanguage.german,
  }) async {
    final error = validateProfileName(value);
    if (error != null) {
      throw ArgumentError(error);
    }
    final profile = UserProfile(
      id: _newId('profile'),
      name: value.trim(),
      language: language,
    );
    _profiles = [..._profiles, profile];
    _activeProfileId = profile.id;
    notifyListeners();
    await _persist();
    AppLog.instance.info(
      'profile.created',
      fields: {
        'profile': AppLog.instance.opaqueId(profile.id),
        'language': language.code,
        'profileCount': _profiles.length,
      },
    );
  }

  Future<void> selectProfile(String profileId) async {
    if (_activeProfileId == profileId ||
        !_profiles.any((profile) => profile.id == profileId)) {
      return;
    }
    _activeProfileId = profileId;
    notifyListeners();
    await _persist();
    AppLog.instance.info(
      'profile.selected',
      fields: {'profile': AppLog.instance.opaqueId(profileId)},
    );
  }

  Future<void> deleteProfile(String profileId) async {
    final index = _profiles.indexWhere((profile) => profile.id == profileId);
    if (index == -1) {
      return;
    }
    _profiles = [..._profiles]..removeAt(index);
    if (_activeProfileId == profileId) {
      if (_profiles.isEmpty) {
        _activeProfileId = null;
      } else {
        final nextIndex = index.clamp(0, _profiles.length - 1);
        _activeProfileId = _profiles[nextIndex].id;
      }
    }
    notifyListeners();
    await _persist();
    AppLog.instance.info(
      'profile.deleted',
      fields: {
        'profile': AppLog.instance.opaqueId(profileId),
        'remainingProfiles': _profiles.length,
      },
    );
  }

  bool isFavorite(String videoId) {
    return activeProfile?.favorites.any((video) => video.id == videoId) ??
        false;
  }

  bool isChannelFavorite(String channelId) {
    return activeProfile?.favoriteChannels.any(
          (channel) => channel.id == channelId,
        ) ??
        false;
  }

  VideoReaction reactionFor(String videoId) {
    return activeProfile?.reactionFor(videoId) ?? VideoReaction.none;
  }

  Future<void> toggleFavorite(YouTubeVideo video) async {
    final profile = _requireActiveProfile();
    final favorites = List<YouTubeVideo>.of(profile.favorites);
    final index = favorites.indexWhere((item) => item.id == video.id);
    if (index == -1) {
      favorites.add(video);
    } else {
      favorites.removeAt(index);
    }
    await _replaceActiveProfile(profile.copyWith(favorites: favorites));
    AppLog.instance.info(
      'profile.favorite.changed',
      fields: {
        'mediaId': video.id,
        'mediaType': video.isAudioOnlyMusic ? 'audio' : 'video',
        'favorite': index == -1,
        'favoriteCount': favorites.length,
      },
    );
  }

  Future<void> toggleFavoriteChannel(YouTubeChannelResult channel) async {
    final profile = _requireActiveProfile();
    final channels = List<YouTubeChannelResult>.of(profile.favoriteChannels);
    final index = channels.indexWhere((item) => item.id == channel.id);
    if (index == -1) {
      channels.add(channel);
    } else {
      channels.removeAt(index);
    }
    await _replaceActiveProfile(profile.copyWith(favoriteChannels: channels));
    AppLog.instance.info(
      'profile.channel_favorite.changed',
      fields: {
        'channel': AppLog.instance.opaqueId(channel.id),
        'music': channel.isMusic,
        'favorite': index == -1,
        'favoriteCount': channels.length,
      },
    );
  }

  Future<void> setReaction(YouTubeVideo video, VideoReaction reaction) async {
    final profile = _requireActiveProfile();
    final likes = Set<String>.of(profile.likedVideoIds)..remove(video.id);
    final dislikes = Set<String>.of(profile.dislikedVideoIds)..remove(video.id);
    if (reaction == VideoReaction.like) {
      likes.add(video.id);
    } else if (reaction == VideoReaction.dislike) {
      dislikes.add(video.id);
    }
    await _replaceActiveProfile(
      profile.copyWith(likedVideoIds: likes, dislikedVideoIds: dislikes),
    );
    AppLog.instance.info(
      'profile.reaction.changed',
      fields: {'mediaId': video.id, 'reaction': reaction.name},
    );
  }

  Future<void> setLanguage(ProfileLanguage language) async {
    final profile = _requireActiveProfile();
    if (profile.language == language) {
      return;
    }
    await _replaceActiveProfile(profile.copyWith(language: language));
    AppLog.instance.info(
      'profile.language.changed',
      fields: {'language': language.code},
    );
  }

  Future<void> setAutoplaySearchResults(bool enabled) async {
    final profile = _requireActiveProfile();
    if (profile.autoplaySearchResults == enabled) {
      return;
    }
    await _replaceActiveProfile(
      profile.copyWith(autoplaySearchResults: enabled),
    );
    AppLog.instance.info(
      'profile.autoplay.changed',
      fields: {'enabled': enabled},
    );
  }

  Future<void> setVideoSearchSort(YouTubeSearchSort sort) async {
    final profile = _requireActiveProfile();
    if (profile.videoSearchSort == sort) {
      return;
    }
    await _replaceActiveProfile(profile.copyWith(videoSearchSort: sort));
  }

  Future<void> setPlaylistSearchSort(YouTubeSearchSort sort) async {
    final profile = _requireActiveProfile();
    if (profile.playlistSearchSort == sort) {
      return;
    }
    await _replaceActiveProfile(profile.copyWith(playlistSearchSort: sort));
  }

  Future<void> recordSearchQuery(String query) async {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }
    final history = addSearchHistoryEntry(profile.searchHistory, query);
    if (listEquals(history, profile.searchHistory)) {
      return;
    }
    await _replaceActiveProfile(profile.copyWith(searchHistory: history));
    AppLog.instance.info(
      'search.history.recorded',
      fields: {
        'query': AppLog.instance.opaqueId(query.trim().toLowerCase()),
        'queryLength': query.trim().length,
        'historyCount': history.length,
      },
    );
  }

  Future<void> deleteSearchHistoryEntry(String query) async {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }
    final history = removeSearchHistoryEntry(profile.searchHistory, query);
    if (listEquals(history, profile.searchHistory)) {
      return;
    }
    await _replaceActiveProfile(profile.copyWith(searchHistory: history));
    AppLog.instance.info(
      'search.history.deleted',
      fields: {
        'query': AppLog.instance.opaqueId(query.trim().toLowerCase()),
        'historyCount': history.length,
      },
    );
  }

  Future<VideoPlaylist> createPlaylist(String value) async {
    final error = validatePlaylistName(value);
    if (error != null) {
      throw ArgumentError(error);
    }
    final profile = _requireActiveProfile();
    final playlist = VideoPlaylist(id: _newId('playlist'), name: value.trim());
    await _replaceActiveProfile(
      profile.copyWith(playlists: [...profile.playlists, playlist]),
    );
    AppLog.instance.info(
      'playlist.created',
      fields: {
        'playlist': AppLog.instance.opaqueId(playlist.id),
        'playlistCount': profile.playlists.length + 1,
      },
    );
    return playlist;
  }

  Future<void> renamePlaylist(String playlistId, String value) async {
    final error = validatePlaylistName(value, excludingPlaylistId: playlistId);
    if (error != null) {
      throw ArgumentError(error);
    }
    final profile = _requireActiveProfile();
    final name = value.trim();
    var changed = false;
    final playlists = profile.playlists
        .map((playlist) {
          if (playlist.id != playlistId || playlist.name == name) {
            return playlist;
          }
          changed = true;
          return playlist.copyWith(name: name);
        })
        .toList(growable: false);
    if (changed) {
      await _replaceActiveProfile(profile.copyWith(playlists: playlists));
      AppLog.instance.info(
        'playlist.renamed',
        fields: {'playlist': AppLog.instance.opaqueId(playlistId)},
      );
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    final profile = _requireActiveProfile();
    final existed = profile.playlists.any((item) => item.id == playlistId);
    await _replaceActiveProfile(
      profile.copyWith(
        playlists: profile.playlists
            .where((playlist) => playlist.id != playlistId)
            .toList(growable: false),
      ),
    );
    if (existed) {
      AppLog.instance.info(
        'playlist.deleted',
        fields: {
          'playlist': AppLog.instance.opaqueId(playlistId),
          'playlistCount': profile.playlists.length - 1,
        },
      );
    }
  }

  Future<bool> addVideoToPlaylist(String playlistId, YouTubeVideo video) async {
    return await addVideosToPlaylist(playlistId, [video]) == 1;
  }

  Future<int> addVideosToPlaylist(
    String playlistId,
    Iterable<YouTubeVideo> videos,
  ) async {
    final profile = _requireActiveProfile();
    var addedCount = 0;
    final playlists = profile.playlists
        .map((playlist) {
          if (playlist.id != playlistId) {
            return playlist;
          }
          final knownIds = playlist.videos.map((video) => video.id).toSet();
          final newVideos = <YouTubeVideo>[];
          for (final video in videos) {
            if (knownIds.add(video.id)) {
              newVideos.add(video);
            }
          }
          addedCount = newVideos.length;
          return newVideos.isEmpty
              ? playlist
              : playlist.copyWith(videos: [...playlist.videos, ...newVideos]);
        })
        .toList(growable: false);
    if (addedCount > 0) {
      await _replaceActiveProfile(profile.copyWith(playlists: playlists));
    }
    AppLog.instance.info(
      'playlist.media_added',
      fields: {
        'playlist': AppLog.instance.opaqueId(playlistId),
        'requestedCount': videos.length,
        'addedCount': addedCount,
      },
    );
    return addedCount;
  }

  Future<void> removeVideoFromPlaylist(
    String playlistId,
    String videoId,
  ) async {
    final profile = _requireActiveProfile();
    final playlists = profile.playlists
        .map((playlist) {
          if (playlist.id != playlistId) {
            return playlist;
          }
          return playlist.copyWith(
            videos: playlist.videos
                .where((video) => video.id != videoId)
                .toList(growable: false),
          );
        })
        .toList(growable: false);
    await _replaceActiveProfile(profile.copyWith(playlists: playlists));
    AppLog.instance.info(
      'playlist.media_removed',
      fields: {
        'playlist': AppLog.instance.opaqueId(playlistId),
        'mediaId': videoId,
      },
    );
  }

  Future<void> reorderPlaylistVideo(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final profile = _requireActiveProfile();
    var changed = false;
    final playlists = profile.playlists
        .map((playlist) {
          if (playlist.id != playlistId ||
              oldIndex < 0 ||
              oldIndex >= playlist.videos.length ||
              newIndex < 0 ||
              newIndex > playlist.videos.length) {
            return playlist;
          }
          var targetIndex = newIndex;
          if (targetIndex > oldIndex) {
            targetIndex--;
          }
          if (targetIndex == oldIndex) {
            return playlist;
          }
          final videos = List<YouTubeVideo>.of(playlist.videos);
          final video = videos.removeAt(oldIndex);
          videos.insert(targetIndex, video);
          changed = true;
          return playlist.copyWith(videos: videos);
        })
        .toList(growable: false);
    if (changed) {
      await _replaceActiveProfile(profile.copyWith(playlists: playlists));
      AppLog.instance.info(
        'playlist.media_reordered',
        fields: {
          'playlist': AppLog.instance.opaqueId(playlistId),
          'from': oldIndex,
          'to': newIndex,
        },
      );
    }
  }

  UserProfile _requireActiveProfile() {
    final profile = activeProfile;
    if (profile == null) {
      throw StateError('Es ist kein Profil ausgewählt.');
    }
    return profile;
  }

  Future<void> _replaceActiveProfile(UserProfile updated) async {
    _profiles = _profiles
        .map((profile) => profile.id == updated.id ? updated : profile)
        .toList(growable: false);
    notifyListeners();
    await _persist();
  }

  String _newId(String prefix) {
    _idSequence++;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idSequence';
  }

  Future<void> _persist() {
    final value = jsonEncode(<String, dynamic>{
      'version': 1,
      'activeProfileId': _activeProfileId,
      'tutorialCompleted': tutorialCompletionPersistenceEnabled
          ? _tutorialCompleted
          : false,
      'completedTutorialStages': tutorialCompletionPersistenceEnabled
          ? _completedTutorialStages
                .map((stage) => stage.storageKey)
                .toList(growable: false)
          : const <String>[],
      'profiles': _profiles.map((profile) => profile.toJson()).toList(),
    });
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await _storage.write(value);
      } on Object catch (error, stackTrace) {
        AppLog.instance.error(
          'profile.storage.write_failed',
          error: error,
          stackTrace: stackTrace,
          fields: {'bytes': value.length},
        );
        rethrow;
      }
    });
    return _pendingWrite;
  }
}
