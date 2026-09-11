import 'dart:math';

import 'search_result_limit.dart';
import 'youtube_video.dart';

enum PlaybackQueueSource { none, localPlaylist, searchResults }

class PlaybackQueue {
  const PlaybackQueue._({
    required this.source,
    required this.items,
    required this.originalItems,
    required this.currentIndex,
    required this.loops,
    required this.isShuffled,
  });

  const PlaybackQueue.empty()
    : source = PlaybackQueueSource.none,
      items = const [],
      originalItems = const [],
      currentIndex = null,
      loops = false,
      isShuffled = false;

  factory PlaybackQueue.localPlaylist({
    required List<YouTubeVideo> items,
    required int initialIndex,
    bool loops = false,
  }) {
    if (items.isEmpty) {
      return const PlaybackQueue.empty();
    }
    return PlaybackQueue._(
      source: PlaybackQueueSource.localPlaylist,
      items: List<YouTubeVideo>.unmodifiable(items),
      originalItems: List<YouTubeVideo>.unmodifiable(items),
      currentIndex: initialIndex.clamp(0, items.length - 1),
      loops: loops,
      isShuffled: false,
    );
  }

  factory PlaybackQueue.searchResults({
    required List<YouTubeVideo> items,
    YouTubeVideo? currentVideo,
  }) {
    if (items.isEmpty) {
      return const PlaybackQueue.empty();
    }
    final immutableItems = limitSearchResults(items);
    final selectedIndex = currentVideo == null
        ? -1
        : immutableItems.indexWhere((item) => item.id == currentVideo.id);
    return PlaybackQueue._(
      source: PlaybackQueueSource.searchResults,
      items: immutableItems,
      originalItems: immutableItems,
      currentIndex: selectedIndex < 0 ? null : selectedIndex,
      loops: true,
      isShuffled: false,
    );
  }

  final PlaybackQueueSource source;
  final List<YouTubeVideo> items;
  final List<YouTubeVideo> originalItems;
  final int? currentIndex;
  final bool loops;
  final bool isShuffled;

  bool get isActive => source != PlaybackQueueSource.none && items.isNotEmpty;

  YouTubeVideo? get currentItem {
    final index = currentIndex;
    return index == null || index < 0 || index >= items.length
        ? null
        : items[index];
  }

  bool get isAtCycleEnd =>
      isActive && currentIndex == items.length - 1 && items.length > 1;

  int? get nextIndex {
    if (!isActive) {
      return null;
    }
    final index = currentIndex;
    if (index == null || index < 0 || index >= items.length) {
      return loops ? 0 : null;
    }
    final next = index + 1;
    if (next < items.length) {
      return next;
    }
    return loops ? 0 : null;
  }

  int? get previousIndex {
    if (!isActive) {
      return null;
    }
    final index = currentIndex;
    if (index == null || index < 0 || index >= items.length) {
      return null;
    }
    if (index > 0) {
      return index - 1;
    }
    return loops ? items.length - 1 : null;
  }

  YouTubeVideo? get nextItem {
    final index = nextIndex;
    return index == null ? null : items[index];
  }

  int? automaticNextIndex({required bool autoplayEnabled}) {
    return autoplayEnabled ? nextIndex : null;
  }

  PlaybackQueue selectIndex(int index) {
    if (index < 0 || index >= items.length) {
      return this;
    }
    return PlaybackQueue._(
      source: source,
      items: items,
      originalItems: originalItems,
      currentIndex: index,
      loops: loops,
      isShuffled: isShuffled,
    );
  }

  PlaybackQueue withLooping(bool enabled) {
    if (!isActive || loops == enabled) {
      return this;
    }
    return PlaybackQueue._(
      source: source,
      items: items,
      originalItems: originalItems,
      currentIndex: currentIndex,
      loops: enabled,
      isShuffled: isShuffled,
    );
  }

  PlaybackQueue withShuffle(bool enabled, {required Random random}) {
    if (!isActive || items.length < 2 || enabled == isShuffled) {
      return this;
    }
    final current = currentItem;
    if (!enabled) {
      final restoredIndex = current == null
          ? null
          : originalItems.indexWhere((item) => item.id == current.id);
      return PlaybackQueue._(
        source: source,
        items: originalItems,
        originalItems: originalItems,
        currentIndex: restoredIndex == null || restoredIndex < 0
            ? null
            : restoredIndex,
        loops: loops,
        isShuffled: false,
      );
    }

    return _shuffledAroundCurrent(
      random: random,
      current: current,
      recentlyPlayedIds: const {},
    );
  }

  PlaybackQueue reshuffleForNextCycle({required Random random}) {
    if (!isShuffled || !isAtCycleEnd) {
      return this;
    }
    final recentStart = (items.length - 3).clamp(0, items.length);
    final recentlyPlayedIds = items
        .sublist(recentStart, items.length - 1)
        .map((item) => item.id)
        .toSet();
    return _shuffledAroundCurrent(
      random: random,
      current: currentItem,
      recentlyPlayedIds: recentlyPlayedIds,
    );
  }

  PlaybackQueue _shuffledAroundCurrent({
    required Random random,
    required YouTubeVideo? current,
    required Set<String> recentlyPlayedIds,
  }) {
    final remaining = List<YouTubeVideo>.of(originalItems);
    if (current != null) {
      final currentIndex = remaining.indexWhere(
        (item) => item.id == current.id,
      );
      if (currentIndex >= 0) {
        remaining.removeAt(currentIndex);
      }
    }
    remaining.shuffle(random);

    final delayedIds = <String>{
      ...recentlyPlayedIds,
      if (current != null) current.id,
    };
    final nextItems = remaining
        .where((item) => !delayedIds.contains(item.id))
        .toList();
    final delayedItems = remaining
        .where((item) => delayedIds.contains(item.id))
        .toList();
    final shuffledItems = <YouTubeVideo>[
      ?current,
      ...nextItems,
      ...delayedItems,
    ];
    return PlaybackQueue._(
      source: source,
      items: List<YouTubeVideo>.unmodifiable(shuffledItems),
      originalItems: originalItems,
      currentIndex: current == null ? null : 0,
      loops: loops,
      isShuffled: true,
    );
  }

  PlaybackQueue selectVideo(YouTubeVideo video) {
    final index = items.indexWhere(
      (item) => item.id == video.id && item.isMusic == video.isMusic,
    );
    return index < 0 ? this : selectIndex(index);
  }

  PlaybackQueue extendSearchResults(List<YouTubeVideo> additions) {
    if (source != PlaybackQueueSource.searchResults ||
        additions.isEmpty ||
        originalItems.length >= searchResultLimit) {
      return this;
    }
    final knownIds = originalItems.map((item) => item.id).toSet();
    final uniqueAdditions = additions
        .where((item) => knownIds.add(item.id))
        .take(searchResultLimit - originalItems.length)
        .toList(growable: false);
    if (uniqueAdditions.isEmpty) {
      return this;
    }
    final extendedOriginalItems = List<YouTubeVideo>.unmodifiable([
      ...originalItems,
      ...uniqueAdditions,
    ]);
    return PlaybackQueue._(
      source: source,
      items: isShuffled
          ? List<YouTubeVideo>.unmodifiable([...items, ...uniqueAdditions])
          : extendedOriginalItems,
      originalItems: extendedOriginalItems,
      currentIndex: currentIndex,
      loops: loops,
      isShuffled: isShuffled,
    );
  }
}
