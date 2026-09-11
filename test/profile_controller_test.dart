import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/app_tutorial_stage.dart';
import 'package:flutter_browser_app/models/user_profile.dart';
import 'package:flutter_browser_app/models/youtube_catalog_item.dart';
import 'package:flutter_browser_app/models/youtube_search_sort.dart';
import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/services/profile_controller.dart';

void main() {
  test('speichert den Tutorial-Abschluss dauerhaft', () async {
    final storage = MemoryProfileStorage();
    final controller = await ProfileController.load(storage: storage);

    expect(controller.tutorialCompleted, isFalse);
    expect(
      controller.shouldShowTutorialStage(AppTutorialStage.profile),
      isTrue,
    );

    await controller.completeTutorialStage(AppTutorialStage.profile);
    expect(controller.tutorialCompleted, isFalse);
    final partiallyReloaded = await ProfileController.load(storage: storage);
    expect(
      partiallyReloaded.shouldShowTutorialStage(AppTutorialStage.profile),
      isFalse,
    );
    expect(
      partiallyReloaded.shouldShowTutorialStage(AppTutorialStage.search),
      isTrue,
    );

    await partiallyReloaded.completeTutorialStage(AppTutorialStage.search);
    await partiallyReloaded.completeTutorialStage(AppTutorialStage.hotMusic);
    expect(partiallyReloaded.tutorialCompleted, isFalse);
    await partiallyReloaded.completeTutorialStage(AppTutorialStage.player);
    expect(partiallyReloaded.tutorialCompleted, isTrue);
    expect(storage.value, contains('"tutorialCompleted":true'));

    final completedReloaded = await ProfileController.load(storage: storage);
    expect(completedReloaded.tutorialCompleted, isTrue);
    expect(
      AppTutorialStage.values.any(completedReloaded.shouldShowTutorialStage),
      isFalse,
    );
  });

  test('manuelle Wiederholung lässt den Abschlussstatus unverändert', () async {
    final storage = MemoryProfileStorage();
    final controller = await ProfileController.load(storage: storage);
    await controller.completeAllTutorialStages();

    await controller.restartTutorial();

    expect(controller.tutorialCompleted, isTrue);
    expect(
      AppTutorialStage.values.every(controller.shouldShowTutorialStage),
      isTrue,
    );
    expect(storage.value, contains('"tutorialCompleted":true'));

    final reloadedDuringReplay = await ProfileController.load(storage: storage);
    expect(reloadedDuringReplay.tutorialCompleted, isTrue);
    expect(
      AppTutorialStage.values.any(reloadedDuringReplay.shouldShowTutorialStage),
      isFalse,
    );
  });

  test('speichert Profile lokal und erzwingt eindeutige Namen', () async {
    final storage = MemoryProfileStorage();
    final controller = await ProfileController.load(storage: storage);

    await controller.createProfile('Alex');
    await controller.setLanguage(ProfileLanguage.english);
    await controller.setAutoplaySearchResults(true);
    await controller.setVideoSearchSort(YouTubeSearchSort.viewCount);
    await controller.setPlaylistSearchSort(YouTubeSearchSort.uploadDate);
    expect(controller.activeProfile?.name, 'Alex');
    expect(
      controller.validateProfileName('  alex  '),
      'Dieser Profilname ist auf dem Gerät bereits vergeben.',
    );

    await controller.createProfile('Sam');
    await controller.selectProfile(controller.profiles.first.id);

    final reloaded = await ProfileController.load(storage: storage);
    expect(reloaded.profiles.map((profile) => profile.name), ['Alex', 'Sam']);
    expect(reloaded.activeProfile?.name, 'Alex');
    expect(reloaded.activeProfile?.language, ProfileLanguage.english);
    expect(reloaded.activeProfile?.autoplaySearchResults, isTrue);
    expect(
      reloaded.activeProfile?.videoSearchSort,
      YouTubeSearchSort.viewCount,
    );
    expect(
      reloaded.activeProfile?.playlistSearchSort,
      YouTubeSearchSort.uploadDate,
    );

    await reloaded.deleteProfile(reloaded.activeProfile!.id);
    expect(reloaded.activeProfile?.name, 'Sam');
    final afterDelete = await ProfileController.load(storage: storage);
    expect(afterDelete.profiles.map((profile) => profile.name), ['Sam']);

    await afterDelete.deleteProfile(afterDelete.activeProfile!.id);
    expect(afterDelete.profiles, isEmpty);
    expect(afterDelete.activeProfile, isNull);
  });

  test('legt ein Profil direkt mit der gewählten Sprache an', () async {
    final storage = MemoryProfileStorage();
    final controller = await ProfileController.load(storage: storage);

    await controller.createProfile(
      'English',
      language: ProfileLanguage.english,
    );

    expect(controller.activeProfile?.language, ProfileLanguage.english);
    final reloaded = await ProfileController.load(storage: storage);
    expect(reloaded.activeProfile?.language, ProfileLanguage.english);
  });

  test('verwendet für alte Profile Relevanz als Suchstandard', () async {
    final storage = MemoryProfileStorage()
      ..value =
          '{"version":1,"activeProfileId":"profile-1",'
          '"profiles":[{"id":"profile-1","name":"Alt"}]}';

    final controller = await ProfileController.load(storage: storage);

    expect(
      controller.activeProfile?.videoSearchSort,
      YouTubeSearchSort.relevance,
    );
    expect(
      controller.activeProfile?.playlistSearchSort,
      YouTubeSearchSort.relevance,
    );
    expect(controller.activeProfile?.searchHistory, isEmpty);
  });

  test('speichert höchstens zehn Suchbegriffe getrennt pro Profil', () async {
    final storage = MemoryProfileStorage();
    final controller = await ProfileController.load(storage: storage);
    await controller.createProfile('Alex');
    for (var index = 1; index <= 11; index++) {
      await controller.recordSearchQuery('Suche $index');
    }
    await controller.recordSearchQuery('suche 5');

    expect(controller.activeProfile!.searchHistory, hasLength(10));
    expect(controller.activeProfile!.searchHistory.first, 'suche 5');
    expect(controller.activeProfile!.searchHistory, isNot(contains('Suche 1')));

    await controller.createProfile('Sam');
    expect(controller.activeProfile!.searchHistory, isEmpty);
    await controller.recordSearchQuery('Eigene Suche');

    await controller.selectProfile(controller.profiles.first.id);
    await controller.deleteSearchHistoryEntry('SUCHE 5');
    expect(
      controller.activeProfile!.searchHistory.where(
        (entry) => entry.toLowerCase() == 'suche 5',
      ),
      isEmpty,
    );

    final reloaded = await ProfileController.load(storage: storage);
    expect(
      reloaded.profiles.first.searchHistory,
      controller.activeProfile!.searchHistory,
    );
    expect(reloaded.profiles.last.searchHistory, ['Eigene Suche']);
  });

  test('ändert die Reihenfolge einer Playlist dauerhaft', () async {
    final storage = MemoryProfileStorage();
    final controller = await ProfileController.load(storage: storage);
    await controller.createProfile('Alex');
    final playlist = await controller.createPlaylist('Training');
    await controller.addVideoToPlaylist(playlist.id, _video);
    await controller.addVideoToPlaylist(playlist.id, _video2);
    await controller.addVideoToPlaylist(playlist.id, _video3);

    await controller.reorderPlaylistVideo(playlist.id, 0, 3);

    expect(
      controller.activeProfile!.playlists.single.videos.map(
        (video) => video.id,
      ),
      ['video-2', 'video-3', 'video-1'],
    );
    final reloaded = await ProfileController.load(storage: storage);
    expect(
      reloaded.activeProfile!.playlists.single.videos.map((video) => video.id),
      ['video-2', 'video-3', 'video-1'],
    );
  });

  test(
    'benennt Playlists eindeutig um und importiert Inhalte gesammelt',
    () async {
      final storage = MemoryProfileStorage();
      final controller = await ProfileController.load(storage: storage);
      await controller.createProfile('Alex');
      final playlist = await controller.createPlaylist('Training');
      await controller.createPlaylist('Favoritenmix');

      expect(
        controller.validatePlaylistName(
          ' Training ',
          excludingPlaylistId: playlist.id,
        ),
        isNull,
      );
      expect(
        controller.validatePlaylistName(
          'favoritenmix',
          excludingPlaylistId: playlist.id,
        ),
        'In diesem Profil gibt es bereits eine Playlist mit diesem Namen.',
      );

      await controller.renamePlaylist(playlist.id, 'Neue Sammlung');
      final added = await controller.addVideosToPlaylist(playlist.id, [
        _video,
        _video2,
        _video,
        _video3,
      ]);
      expect(added, 3);
      expect(
        await controller.addVideosToPlaylist(playlist.id, [_video, _video2]),
        0,
      );

      final reloaded = await ProfileController.load(storage: storage);
      final imported = reloaded.activeProfile!.playlists.firstWhere(
        (item) => item.id == playlist.id,
      );
      expect(imported.name, 'Neue Sammlung');
      expect(imported.videos.map((video) => video.id), [
        'video-1',
        'video-2',
        'video-3',
      ]);
    },
  );

  test('trennt Favoriten, Reaktionen und Playlists pro Profil', () async {
    final controller = ProfileController.inMemory();
    await controller.createProfile('Alex');

    await controller.toggleFavorite(_video);
    await controller.setReaction(_video, VideoReaction.like);
    final playlist = await controller.createPlaylist('Training');
    expect(await controller.addVideoToPlaylist(playlist.id, _video), isTrue);
    expect(await controller.addVideoToPlaylist(playlist.id, _video), isFalse);

    expect(controller.isFavorite(_video.id), isTrue);
    expect(controller.reactionFor(_video.id), VideoReaction.like);
    expect(controller.activeProfile?.playlists.single.videos, [_video]);

    await controller.setReaction(_video, VideoReaction.dislike);
    expect(controller.reactionFor(_video.id), VideoReaction.dislike);
    expect(controller.activeProfile?.likedVideoIds, isEmpty);

    await controller.createProfile('Sam');
    expect(controller.isFavorite(_video.id), isFalse);
    expect(controller.reactionFor(_video.id), VideoReaction.none);
    expect(controller.activeProfile?.playlists, isEmpty);
  });

  test(
    'speichert Channel- und Künstlerfavoriten getrennt von Medien',
    () async {
      final storage = MemoryProfileStorage();
      final controller = await ProfileController.load(storage: storage);
      await controller.createProfile('Alex');

      await controller.toggleFavoriteChannel(_channel);
      await controller.toggleFavoriteChannel(_artist);

      expect(controller.isChannelFavorite(_channel.id), isTrue);
      expect(controller.isChannelFavorite(_artist.id), isTrue);
      expect(controller.activeProfile!.favorites, isEmpty);
      expect(controller.activeProfile!.favoriteChannels, [_channel, _artist]);

      final reloaded = await ProfileController.load(storage: storage);
      expect(
        reloaded.activeProfile!.favoriteChannels.map((channel) => channel.id),
        ['channel-1', 'artist-1'],
      );
      expect(reloaded.activeProfile!.favoriteChannels.last.isMusic, isTrue);

      await reloaded.toggleFavoriteChannel(_channel);
      expect(reloaded.isChannelFavorite(_channel.id), isFalse);
      expect(reloaded.activeProfile!.favoriteChannels.single.id, 'artist-1');

      await reloaded.createProfile('Sam');
      expect(reloaded.activeProfile!.favoriteChannels, isEmpty);
    },
  );
}

const _channel = YouTubeChannelResult(
  id: 'channel-1',
  name: 'Channel',
  description: 'Beschreibung',
  thumbnailUrl: '',
  videoCount: 12,
);

const _artist = YouTubeChannelResult(
  id: 'artist-1',
  name: 'Künstler',
  description: 'Beschreibung',
  thumbnailUrl: '',
  videoCount: 0,
  isMusic: true,
);

const _video = YouTubeVideo(
  id: 'video-1',
  title: 'Testvideo',
  description: 'Beschreibung',
  thumbnailUrl: '',
  channelTitle: 'Testkanal',
);

const _video2 = YouTubeVideo(
  id: 'video-2',
  title: 'Testvideo 2',
  description: 'Beschreibung',
  thumbnailUrl: '',
);

const _video3 = YouTubeVideo(
  id: 'video-3',
  title: 'Testvideo 3',
  description: 'Beschreibung',
  thumbnailUrl: '',
);
