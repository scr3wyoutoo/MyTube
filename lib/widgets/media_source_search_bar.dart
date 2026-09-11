import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/search_history.dart';
import '../models/video_search_source.dart';
import '../models/youtube_search_category.dart';
import 'search_tutorial_targets.dart';

class MediaSourceSearchBar extends StatefulWidget {
  const MediaSourceSearchBar({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.sourceSelectionEnabled,
    required this.source,
    required this.category,
    required this.onSourceChanged,
    required this.onSearch,
    this.searchHistory = const [],
    this.onSearchHistoryDeleted,
    this.errorText,
    this.compact = false,
    this.keyPrefix = 'search',
    this.tutorialTargets,
    this.onSourceMenuOpened,
    this.onSourceMenuClosed,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool isLoading;
  final bool sourceSelectionEnabled;
  final VideoSearchSource source;
  final YouTubeSearchCategory category;
  final ValueChanged<VideoSearchSource> onSourceChanged;
  final VoidCallback onSearch;
  final List<String> searchHistory;
  final ValueChanged<String>? onSearchHistoryDeleted;
  final bool compact;
  final String keyPrefix;
  final SearchTutorialTargets? tutorialTargets;
  final VoidCallback? onSourceMenuOpened;
  final VoidCallback? onSourceMenuClosed;

  bool get _musicMode => source == VideoSearchSource.youtubeMusic;

  @override
  State<MediaSourceSearchBar> createState() => _MediaSourceSearchBarState();
}

class _MediaSourceSearchBarState extends State<MediaSourceSearchBar> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearAndActivateTextField() {
    widget.controller.value = const TextEditingValue(
      selection: TextSelection.collapsed(offset: 0),
    );
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.hasFocus) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  void _selectSearchHistoryEntry(String entry) {
    widget.controller.value = TextEditingValue(
      text: entry,
      selection: TextSelection.collapsed(offset: entry.length),
    );
    widget.onSearch();
  }

  @override
  Widget build(BuildContext context) {
    final controlSize = widget.compact ? 48.0 : 56.0;
    final controlGap = widget.compact ? 8.0 : 12.0;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final matches = _focusNode.hasFocus
            ? matchingSearchHistory(widget.searchHistory, value.text)
            : const <String>[];
        final textField = TextField(
          key: Key('${widget.keyPrefix}-field'),
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            if (!widget.isLoading) {
              widget.onSearch();
            }
          },
          decoration: InputDecoration(
            hintText: context.l10n.searchHint(widget.source, widget.category),
            labelText: widget.compact
                ? null
                : context.l10n.searchLabel(widget.source, widget.category),
            errorText: widget.errorText,
            isDense: widget.compact,
            contentPadding: widget.compact
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
                : null,
            prefixIcon: KeyedSubtree(
              key: widget.tutorialTargets?.sourceSelector,
              child: PopupMenuButton<VideoSearchSource>(
                key: Key('${widget.keyPrefix}-source-selector'),
                enabled: widget.sourceSelectionEnabled && !widget.isLoading,
                initialValue: widget.source,
                tooltip: context.l10n.searchSourceTooltip,
                onOpened: widget.onSourceMenuOpened,
                onCanceled: widget.onSourceMenuClosed,
                onSelected: (source) {
                  widget.onSourceChanged(source);
                  widget.onSourceMenuClosed?.call();
                },
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget._musicMode
                          ? Icons.music_note
                          : Icons.ondemand_video_outlined,
                      key: Key('${widget.keyPrefix}-source-icon'),
                      size: widget.compact ? 20 : null,
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      key: Key('${widget.keyPrefix}-source-dropdown-indicator'),
                      size: widget.compact ? 16 : 18,
                    ),
                  ],
                ),
                itemBuilder: (context) => [
                  PopupMenuItem<VideoSearchSource>(
                    key: Key('${widget.keyPrefix}-source-youtube'),
                    value: VideoSearchSource.youtube,
                    child: const Center(
                      child: Tooltip(
                        message: 'YouTube',
                        child: Icon(Icons.ondemand_video_outlined),
                      ),
                    ),
                  ),
                  PopupMenuItem<VideoSearchSource>(
                    key: Key('${widget.keyPrefix}-source-music'),
                    value: VideoSearchSource.youtubeMusic,
                    child: const Center(
                      child: Tooltip(
                        message: 'YouTube Music',
                        child: Icon(Icons.music_note),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    key: Key('${widget.keyPrefix}-clear-button'),
                    tooltip: context.l10n.clearSearchField,
                    onPressed: _clearAndActivateTextField,
                    icon: const Icon(Icons.close),
                  ),
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: widget.compact
                      ? SizedBox(height: controlSize, child: textField)
                      : textField,
                ),
                SizedBox(width: controlGap),
                SizedBox.square(
                  dimension: controlSize,
                  child: KeyedSubtree(
                    key: widget.tutorialTargets?.searchButton,
                    child: Tooltip(
                      message: context.l10n.searchAction,
                      child: FilledButton(
                        key: Key('${widget.keyPrefix}-button'),
                        style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: widget.isLoading ? null : widget.onSearch,
                        child: Icon(
                          Icons.search,
                          size: widget.compact ? 20 : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (matches.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildSearchHistoryDropdown(matches)),
                  SizedBox(width: controlGap + controlSize),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildSearchHistoryDropdown(List<String> matches) {
    return Card(
      key: Key('${widget.keyPrefix}-history-dropdown'),
      margin: const EdgeInsets.only(top: 4),
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.compact ? 176 : 240),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: matches.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = matches[index];
            final normalized = entry.toLowerCase();
            return ListTile(
              key: ValueKey('${widget.keyPrefix}-history-entry-$normalized'),
              dense: true,
              visualDensity: widget.compact
                  ? const VisualDensity(vertical: -3)
                  : const VisualDensity(vertical: -1),
              leading: const Icon(Icons.history, size: 20),
              title: Text(entry, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _selectSearchHistoryEntry(entry),
              trailing: IconButton(
                key: ValueKey('${widget.keyPrefix}-history-delete-$normalized'),
                tooltip: context.l10n.deleteSearchHistoryEntry(entry),
                onPressed: widget.onSearchHistoryDeleted == null
                    ? null
                    : () => widget.onSearchHistoryDeleted!(entry),
                icon: const Icon(Icons.close, size: 18),
              ),
            );
          },
        ),
      ),
    );
  }
}
