# MyTube

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

MyTube is an experimental Flutter video and music browser for Android and iOS. It combines YouTube and YouTube Music discovery with a custom player UI, local profiles, queues, playlists, background controls, and picture-in-picture for video.

> [!IMPORTANT]
> MyTube is an independent project and is not affiliated with, sponsored by, or endorsed by YouTube or Google. It uses unofficial YouTube endpoints through third-party libraries. Those endpoints can change or rate-limit clients without notice. Review the applicable terms and local law before distributing or operating the app.

## Highlights

- Video, channel, playlist, song, artist, and music-playlist search
- YouTube Music discovery, charts, moods, and genres
- Infinite result loading with a bounded in-memory queue
- Local profiles with language, favorites, playlists, channels, and search history
- Queue history, autoplay, shuffle, playlist import, and six-second song crossfade
- Live-stream detection and HLS playback
- Android video PiP plus Android/iOS lock-screen and Bluetooth media controls
- Native Media3 playback on Android and native AVPlayer playback on iOS where supported by the media type
- English and German UI, including an optional guided tutorial
- Local rolling diagnostic log with URL and credential redaction

The detailed platform/player split is documented in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Status

Version: **1.0.1** (build **105**)

Android and iOS are the primary targets. The repository also contains Flutter-generated desktop and web scaffolding, but those platforms are not currently release targets and do not have feature parity.

## Requirements

- A Flutter SDK compatible with Dart `^3.11.0`
- Android Studio/Android SDK for Android builds
- macOS with Xcode and CocoaPods for iOS builds
- Network access to YouTube endpoints

## Quick Start Android

- Download project to a folder
- Open it as flutter-project in Android-Studio
- Build to your phone

## Quick Start iOS

- Download project to a folder
- Open it as flutter-project in Android-Studio (for iOS)
- Use the terminal to go to the 'ios directory' of the project
- Run flutter clean; flutter pub get; flutter pub upgrade; pod install;
- Open 'Runner.xcworkspace' in XCode
- Build to your phone

## Run locally

```bash
flutter pub get
flutter run
```

The default search path does not require an API key. It uses `youtube_explode_dart` and `ytmusicapi_dart`.

## Optional YouTube Data API fallback

An official YouTube Data API v3 search implementation is kept as an opt-in fallback. Pass credentials at build/run time; never commit them:

```bash
flutter run \
  --dart-define=YOUTUBE_SEARCH_BACKEND=youtube_api \
  --dart-define=YOUTUBE_API_KEY=YOUR_RESTRICTED_KEY
```

The same defines can be supplied to `flutter build apk` or `flutter build ios`. A value embedded with `--dart-define` can still be extracted from a distributed app. Restrict mobile API keys by app and API, or place requests behind a backend when a secret must remain confidential.

## Validate changes

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

GitHub Actions runs formatting, analysis, and tests for pushes and pull requests.

## Distribution checklist

The checked-in application identifiers still use Flutter's `com.example` development namespace to preserve upgrade compatibility with existing test installs. Before a store release:

1. Replace the Android application ID and Apple bundle identifiers with identifiers you own.
2. Configure Android release signing outside the repository.
3. Configure the Apple development team, signing, capabilities, and App Store metadata in Xcode.
4. Review platform privacy disclosures, third-party licenses, YouTube terms, and branding requirements.
5. Run real-device regression tests for background audio, lock-screen controls, Bluetooth routing, PiP, live streams, autoplay, and crossfade.

## Data and privacy

Profiles, favorites, playlists, settings, search history, and diagnostic logs are stored locally. Search and playback necessarily contact YouTube/Google delivery endpoints. The optional official API fallback contacts the YouTube Data API. The app does not include analytics or advertising SDKs.

Diagnostic logs are bounded and redact URL query strings plus common authorization/cookie fields. Users can inspect, copy, and clear the log from the profile menu. Treat exported logs as potentially sensitive nevertheless.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please keep platform-specific playback behavior covered by tests and do not commit credentials, generated build products, local SDK paths, or device logs.

## License

MyTube's original source code and original project assets are licensed under
the [Apache License 2.0](LICENSE). Copyright and attribution information is in
[NOTICE](NOTICE). Third-party components remain under their respective
licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The license covers this project's own work only. It does not grant permission
to use YouTube services, YouTube content, or Google/YouTube trademarks outside
the rights separately provided by their owners and applicable law.
