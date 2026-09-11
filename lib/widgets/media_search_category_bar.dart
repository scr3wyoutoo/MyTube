import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/youtube_search_category.dart';
import '../models/youtube_search_sort.dart';
import 'search_tutorial_targets.dart';

class MediaSearchCategoryBar extends StatelessWidget {
  const MediaSearchCategoryBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.keyPrefix = 'search',
    this.enabled = true,
    this.musicMode = false,
    this.videoSortingEnabled = false,
    this.playlistSortingEnabled = false,
    this.videoSort = YouTubeSearchSort.relevance,
    this.playlistSort = YouTubeSearchSort.relevance,
    this.onSortSelected,
    this.tutorialTargets,
  });

  final YouTubeSearchCategory selected;
  final ValueChanged<YouTubeSearchCategory> onSelected;
  final String keyPrefix;
  final bool enabled;
  final bool musicMode;
  final bool videoSortingEnabled;
  final bool playlistSortingEnabled;
  final YouTubeSearchSort videoSort;
  final YouTubeSearchSort playlistSort;
  final void Function(YouTubeSearchCategory category, YouTubeSearchSort sort)?
  onSortSelected;
  final SearchTutorialTargets? tutorialTargets;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('$keyPrefix-category-bar'),
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final category in YouTubeSearchCategory.values)
            Expanded(child: _buildCategory(context, category, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildCategory(
    BuildContext context,
    YouTubeSearchCategory category,
    ColorScheme colorScheme,
  ) {
    final isSelected = category == selected;
    final supportsSorting =
        !musicMode &&
        isSelected &&
        onSortSelected != null &&
        switch (category) {
          YouTubeSearchCategory.videos => videoSortingEnabled,
          YouTubeSearchCategory.channels => false,
          YouTubeSearchCategory.playlists => playlistSortingEnabled,
        };
    final child = _CategoryLabel(
      category: category,
      musicMode: musicMode,
      selected: isSelected,
      showDropdown: supportsSorting,
      colorScheme: colorScheme,
    );

    Widget interactiveCategory;
    if (supportsSorting) {
      final selectedSort = category == YouTubeSearchCategory.videos
          ? videoSort
          : playlistSort;
      interactiveCategory = PopupMenuButton<YouTubeSearchSort>(
        key: ValueKey('$keyPrefix-category-${category.name}'),
        tooltip: context.l10n.sortTooltip(selectedSort),
        initialValue: selectedSort,
        enabled: enabled,
        position: PopupMenuPosition.under,
        onSelected: (sort) => onSortSelected!(category, sort),
        itemBuilder: (context) => [
          for (final sort in YouTubeSearchSort.values)
            PopupMenuItem<YouTubeSearchSort>(
              key: ValueKey('$keyPrefix-sort-${category.name}-${sort.name}'),
              value: sort,
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: sort == selectedSort
                        ? const Icon(Icons.check, size: 20)
                        : null,
                  ),
                  Text(context.l10n.sortLabel(sort)),
                ],
              ),
            ),
        ],
        child: child,
      );
    } else {
      interactiveCategory = InkWell(
        key: ValueKey('$keyPrefix-category-${category.name}'),
        onTap: enabled && !isSelected ? () => onSelected(category) : null,
        child: child,
      );
    }
    return KeyedSubtree(
      key: tutorialTargets?.category(category),
      child: interactiveCategory,
    );
  }
}

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({
    required this.category,
    required this.musicMode,
    required this.selected,
    required this.showDropdown,
    required this.colorScheme,
  });

  final YouTubeSearchCategory category;
  final bool musicMode;
  final bool selected;
  final bool showDropdown;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.categoryLabel(category, music: musicMode);
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: selected
          ? colorScheme.onPrimaryContainer
          : colorScheme.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
      decoration: BoxDecoration(
        color: selected ? colorScheme.primaryContainer : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (showDropdown) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: style?.color),
          ],
        ],
      ),
    );
  }
}
