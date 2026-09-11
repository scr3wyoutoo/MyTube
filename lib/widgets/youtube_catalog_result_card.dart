import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/youtube_catalog_item.dart';

class YouTubeChannelResultCard extends StatelessWidget {
  const YouTubeChannelResultCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  final YouTubeChannelResult channel;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return _CatalogCard(
      onTap: onTap,
      leading: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: SizedBox.square(
              dimension: 76,
              child: _NetworkThumbnail(
                url: channel.thumbnailUrl,
                fallbackIcon: Icons.account_circle_outlined,
              ),
            ),
          ),
          if (onToggleFavorite != null)
            IconButton(
              key: ValueKey('catalog-favorite-channel-${channel.id}'),
              tooltip: isFavorite
                  ? context.l10n.removeChannelFavorite
                  : context.l10n.addChannelFavorite,
              onPressed: onToggleFavorite,
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? Colors.red : null,
              ),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      title: channel.name,
      subtitle: [
        if (channel.videoCount > 0) context.l10n.videoCount(channel.videoCount),
        if (channel.description.trim().isNotEmpty) channel.description.trim(),
      ].join('\n'),
    );
  }
}

class YouTubePlaylistResultCard extends StatelessWidget {
  const YouTubePlaylistResultCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onAddToPlaylist,
  });

  final YouTubePlaylistResult playlist;
  final VoidCallback onTap;
  final VoidCallback? onAddToPlaylist;

  @override
  Widget build(BuildContext context) {
    return _CatalogCard(
      onTap: onTap,
      leading: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 120,
              height: 68,
              child: _NetworkThumbnail(
                url: playlist.thumbnailUrl,
                fallbackIcon: Icons.playlist_play,
              ),
            ),
          ),
          if (onAddToPlaylist != null)
            IconButton(
              key: ValueKey('catalog-add-playlist-${playlist.id}'),
              tooltip: context.l10n.addCompletePlaylist,
              onPressed: onAddToPlaylist,
              icon: const Icon(Icons.playlist_add),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      title: playlist.title,
      subtitle: playlist.creatorName.isNotEmpty
          ? playlist.creatorName
          : playlist.videoCount > 0
          ? context.l10n.contentCount(playlist.videoCount)
          : playlist.typeLabel.isEmpty
          ? context.l10n.openPlaylist
          : '',
      badgeLabel: context.l10n.releaseType(playlist.typeLabel),
      badgeKey: playlist.typeLabel.isEmpty
          ? null
          : ValueKey('catalog-type-badge-${playlist.id}'),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.badgeLabel = '',
    this.badgeKey,
  });

  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final String badgeLabel;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (badgeLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        key: badgeKey,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeLabel,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkThumbnail extends StatelessWidget {
  const _NetworkThumbnail({required this.url, required this.fallbackIcon});

  final String url;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(fallbackIcon, size: 34)),
    );
    if (url.isEmpty) {
      return fallback;
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}
