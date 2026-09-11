import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/youtube_video.dart';

class VideoResultCard extends StatelessWidget {
  const VideoResultCard({
    super.key,
    required this.video,
    required this.onTap,
    this.compact = false,
    this.trailing,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onAddToPlaylist,
    this.showInfo = false,
    this.loadFullDescription,
    this.favoriteActionTargetKey,
    this.playlistActionTargetKey,
    this.infoActionTargetKey,
  });

  final YouTubeVideo video;
  final VoidCallback onTap;
  final bool compact;
  final Widget? trailing;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onAddToPlaylist;
  final bool showInfo;
  final Future<String> Function()? loadFullDescription;
  final Key? favoriteActionTargetKey;
  final Key? playlistActionTargetKey;
  final Key? infoActionTargetKey;

  bool get _showsThumbnailActions =>
      onToggleFavorite != null || onAddToPlaylist != null || showInfo;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: compact ? 112 : 144,
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: video.thumbnailUrl.isEmpty
                                ? const _ThumbnailFallback()
                                : Image.network(
                                    video.thumbnailUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const _ThumbnailFallback(),
                                  ),
                          ),
                          if (video.isLive)
                            Positioned(
                              left: 6,
                              bottom: 6,
                              child: DecoratedBox(
                                key: ValueKey('video-live-tag-${video.id}'),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade700,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_showsThumbnailActions) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (onToggleFavorite != null)
                            KeyedSubtree(
                              key: favoriteActionTargetKey,
                              child: IconButton(
                                key: ValueKey('search-favorite-${video.id}'),
                                tooltip: isFavorite
                                    ? context.l10n.removeFavorite
                                    : context.l10n.addFavorite,
                                onPressed: onToggleFavorite,
                                icon: Icon(
                                  isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFavorite ? Colors.red : null,
                                ),
                              ),
                            ),
                          if (onAddToPlaylist != null)
                            KeyedSubtree(
                              key: playlistActionTargetKey,
                              child: IconButton(
                                key: ValueKey(
                                  'search-add-playlist-${video.id}',
                                ),
                                tooltip: context.l10n.addToPlaylist,
                                onPressed: onAddToPlaylist,
                                icon: const Icon(Icons.playlist_add),
                              ),
                            ),
                          if (showInfo)
                            KeyedSubtree(
                              key: infoActionTargetKey,
                              child: VideoInfoButton(
                                key: ValueKey('search-info-${video.id}'),
                                video: video,
                                loadFullDescription: loadFullDescription,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _VideoCardDescription(
                      video: video,
                      loadFullDescription: loadFullDescription,
                      maxLines: compact ? 2 : 3,
                    ),
                  ],
                ),
              ),
              if (trailing case final trailing?) ...[
                const SizedBox(width: 4),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoCardDescription extends StatefulWidget {
  const _VideoCardDescription({
    required this.video,
    required this.loadFullDescription,
    required this.maxLines,
  });

  final YouTubeVideo video;
  final Future<String> Function()? loadFullDescription;
  final int maxLines;

  @override
  State<_VideoCardDescription> createState() => _VideoCardDescriptionState();
}

class _VideoCardDescriptionState extends State<_VideoCardDescription> {
  late String _description;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _description = widget.video.description;
    _loadMissingDescription();
  }

  @override
  void didUpdateWidget(covariant _VideoCardDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _description = widget.video.description;
      _isLoading = false;
      _loadMissingDescription();
    } else if (_description.isEmpty && widget.video.description.isNotEmpty) {
      _description = widget.video.description;
    }
  }

  void _loadMissingDescription() {
    final loader = widget.loadFullDescription;
    if (_description.isNotEmpty || loader == null || _isLoading) {
      return;
    }
    _isLoading = true;
    unawaited(() async {
      try {
        final description = await loader();
        if (!mounted) {
          return;
        }
        setState(() {
          _description = description.trim();
          _isLoading = false;
        });
      } on Object {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final text = _description.isNotEmpty
        ? _description
        : _isLoading
        ? context.l10n.descriptionLoading
        : context.l10n.noDescription;
    return Text(
      text,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class VideoInfoButton extends StatelessWidget {
  const VideoInfoButton({
    super.key,
    required this.video,
    this.loadFullDescription,
    this.compactHorizontally = false,
  });

  final YouTubeVideo video;
  final Future<String> Function()? loadFullDescription;
  final bool compactHorizontally;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.information,
      icon: const Icon(Icons.info_outline),
      visualDensity: compactHorizontally
          ? const VisualDensity(horizontal: -2)
          : null,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => _VideoInfoSheet(
          video: video,
          loadFullDescription: loadFullDescription,
          sheetContext: sheetContext,
        ),
      ),
    );
  }
}

class _VideoInfoSheet extends StatefulWidget {
  const _VideoInfoSheet({
    required this.video,
    required this.loadFullDescription,
    required this.sheetContext,
  });

  final YouTubeVideo video;
  final Future<String> Function()? loadFullDescription;
  final BuildContext sheetContext;

  @override
  State<_VideoInfoSheet> createState() => _VideoInfoSheetState();
}

class _VideoInfoSheetState extends State<_VideoInfoSheet> {
  late String _description;

  @override
  void initState() {
    super.initState();
    _description = widget.video.description;
    if (widget.loadFullDescription != null) {
      unawaited(_loadFullDescription());
    }
  }

  Future<void> _loadFullDescription() async {
    try {
      final description = await widget.loadFullDescription!();
      if (!mounted ||
          description.trim().isEmpty ||
          description == _description) {
        return;
      }
      setState(() => _description = description);
    } on Object {
      // The search excerpt remains visible when full metadata cannot be loaded.
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: ListView(
            key: ValueKey('video-info-scroll-${video.id}'),
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.information,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    onPressed: () => Navigator.of(widget.sheetContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoEntry(label: context.l10n.title, value: video.title),
              const SizedBox(height: 12),
              _InfoEntry(
                label: context.l10n.channel,
                value: video.channelTitle.isEmpty
                    ? context.l10n.unavailable
                    : video.channelTitle,
              ),
              const SizedBox(height: 12),
              _InfoEntry(
                label: context.l10n.publicationDate,
                value: _formatPublishedAt(video.publishedAt),
              ),
              const SizedBox(height: 12),
              _InfoEntry(
                label: context.l10n.description,
                value: _description.isEmpty
                    ? context.l10n.noDescription
                    : _description,
              ),
              const SizedBox(height: 12),
              _InfoEntry(
                label: context.l10n.source,
                value: 'https://www.youtube.com/watch?v=${video.id}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPublishedAt(DateTime? value) {
    if (value == null) {
      return context.l10n.unavailable;
    }
    final localDate = value.toLocal();
    return context.l10n.formatDate(localDate);
  }
}

class _InfoEntry extends StatelessWidget {
  const _InfoEntry({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
        ),
      ],
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.image_not_supported_outlined)),
    );
  }
}
