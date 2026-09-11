enum YouTubeSearchSort {
  relevance('relevance', 'Relevanz'),
  uploadDate('uploadDate', 'Neueste'),
  viewCount('viewCount', 'Meistgesehen'),
  rating('rating', 'Bestbewertet');

  const YouTubeSearchSort(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static YouTubeSearchSort fromStorage(
    Object? value, {
    YouTubeSearchSort fallback = YouTubeSearchSort.relevance,
  }) {
    return values.firstWhere(
      (sort) => sort.storageValue == value,
      orElse: () => fallback,
    );
  }
}

/// Keeps the complete search-sort implementation available while its
/// key-free YouTube parameters are not honored reliably by YouTube.
const bool youtubeSearchSortControlsEnabled = false;
