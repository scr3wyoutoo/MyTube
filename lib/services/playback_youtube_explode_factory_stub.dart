import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PlaybackYoutubeExplodeSession {
  const PlaybackYoutubeExplodeSession({required this.client});

  final YoutubeExplode client;
}

Future<PlaybackYoutubeExplodeSession> createPlaybackYoutubeExplode() async {
  return PlaybackYoutubeExplodeSession(client: YoutubeExplode());
}
