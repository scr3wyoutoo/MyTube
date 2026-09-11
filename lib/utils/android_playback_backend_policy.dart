import '../models/youtube_video.dart';

bool shouldUseAndroidMedia3VideoPlayer({
  required bool isAndroid,
  required YouTubeVideo video,
}) {
  return isAndroid && video.hasVideo && !video.isMusic;
}

bool shouldUseAndroidMedia3AudioPlayer({
  required bool isAndroid,
  required YouTubeVideo video,
}) => isAndroid && video.isAudioOnlyMusic;
