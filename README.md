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

Version: **1.0.1** (build **109**)
BUILD HASH SHA256: 9A44EB2153759C8D90FDDCBE69EDA8D6AAA1C70F9408591D76F26A130A3C428F
FINGERPRINT: 25:AA:BC:D3:AE:50:3F:52:D4:30:20:4B:B5:D5:E6:35:35:E1:25:83:66:47:63:0A:54:9B:69:96:B1:29:70:0C

Android and iOS are the primary targets. The repository also contains Flutter-generated desktop and web scaffolding, but those platforms are not currently release targets and do not have feature parity.

## Requirements

- A Flutter SDK compatible with Dart `^3.11.0`
- Android Studio/Android SDK for Android builds
- iOS 15 or newer for installation
- macOS with Xcode and CocoaPods for iOS builds
- Network access to YouTube endpoints

## Quick Start Android

1. Download and install .apk on your phone: https://mega.nz/folder/2soBjZYB#ylHbp7duE3qymLXFb7lhZA

OR

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

## Android release signing

Release artifacts must use a private key that is never committed. Create
`android/key.properties` locally with these values:

```properties
storeFile=/absolute/private/path/mytube-release-key.p12
storePassword=YOUR_STORE_PASSWORD
keyAlias=mytube-release
keyPassword=YOUR_KEY_PASSWORD
```

`android/key.properties`, `*.jks`, `*.keystore`, and `*.p12` are ignored by Git.
When the local properties are present, Gradle signs the release APK with that
key. A release build without complete signing data fails instead of silently
producing an unsigned APK:

```bash
flutter build apk --release
```

Keep the keystore and its credentials in multiple secure offline backups. Every
future update of the same Android application ID must be signed by the same key.
The current MyTube release certificate has SHA-256 fingerprint
`25:AA:BC:D3:AE:50:3F:52:D4:30:20:4B:B5:D5:E6:35:35:E1:25:83:66:47:63:0A:54:9B:69:96:B1:29:70:0C`.

## Validate changes

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

GitHub Actions runs formatting, analysis, and tests for pushes and pull requests.

## Distribution checklist

The checked-in Android application ID and Apple bundle identifiers use
`com.dev.mytube`. Before a store release:

1. Confirm that `com.dev.mytube` is registered to the intended Play Console and
   Apple Developer accounts.
2. Keep the Android release key and its recovery credentials outside the repository.
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
