import 'youtube_explode_search_repository.dart';
import 'youtube_search_repository.dart';

const String _configuredSearchBackend = String.fromEnvironment(
  'YOUTUBE_SEARCH_BACKEND',
  defaultValue: 'youtube_explode',
);
const String _configuredApiKey = String.fromEnvironment('YOUTUBE_API_KEY');

YouTubeSearchRepository createYouTubeSearchRepository({
  String backend = _configuredSearchBackend,
  String apiKey = _configuredApiKey,
}) {
  if (backend.trim().toLowerCase() == 'youtube_api') {
    return YouTubeApiSearchRepository(apiKey: apiKey);
  }

  return YouTubeExplodeSearchRepository();
}
