# Third-party notices

MyTube's original source code and original project assets are licensed under
the Apache License 2.0. Third-party components are not relicensed by MyTube;
they remain subject to their respective licenses and notices.

The exact dependency versions used by this build are recorded in
[`pubspec.lock`](pubspec.lock). The following table is a convenience overview
of the direct dependencies declared in [`pubspec.yaml`](pubspec.yaml), not a
replacement for their complete license texts or the notices of their
transitive and native dependencies.

| Component | Declared license | Project/package page |
| --- | --- | --- |
| Flutter SDK and Flutter localization libraries | BSD-3-Clause | <https://github.com/flutter/flutter> |
| `cupertino_icons` | MIT | <https://pub.dev/packages/cupertino_icons> |
| `http` | BSD-3-Clause | <https://pub.dev/packages/http> |
| `youtube_explode_dart` | BSD-3-Clause | <https://pub.dev/packages/youtube_explode_dart> |
| `media_kit` | MIT | <https://pub.dev/packages/media_kit> |
| `media_kit_video` | MIT | <https://pub.dev/packages/media_kit_video> |
| `media_kit_libs_video` | MIT wrapper; bundled native libraries have their own terms | <https://pub.dev/packages/media_kit_libs_video> |
| `ytmusicapi_dart` | MIT | <https://pub.dev/packages/ytmusicapi_dart> |
| `dio` | MIT | <https://pub.dev/packages/dio> |
| `audio_service` | MIT | <https://pub.dev/packages/audio_service> |
| `audio_session` | MIT | <https://pub.dev/packages/audio_session> |
| `package_info_plus` | BSD-3-Clause | <https://pub.dev/packages/package_info_plus> |
| `path_provider` | BSD-3-Clause | <https://pub.dev/packages/path_provider> |
| `shared_preferences` | BSD-3-Clause | <https://pub.dev/packages/shared_preferences> |
| AndroidX Media3 | Apache-2.0 | <https://github.com/androidx/media> |

When distributing a compiled application, review and ship all license and
NOTICE material required by the resolved transitive Dart, Android, Apple, and
native media dependencies. In particular, the native libraries brought in by
`media_kit_libs_video` may carry obligations beyond the MIT license of the Dart
wrapper.

The open-source licenses above govern software only. They do not grant rights
to YouTube, YouTube Music, their services, trademarks, or third-party media
retrieved while the application is running.
