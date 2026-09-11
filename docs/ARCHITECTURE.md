# Architecture

This document is a public, implementation-level overview. It intentionally excludes local recovery paths, device logs, and historical debugging notes.

## Layers

- `lib/screens/` contains the search, Hot Music, profile, and player flows.
- `lib/widgets/` contains reusable cards, controls, navigation, and tutorial overlays.
- `lib/models/` contains immutable search, profile, queue, history, catalog, and playback data.
- `lib/services/` owns YouTube access, manifest resolution, local persistence, diagnostics, platform channels, and native playback coordination.
- `lib/utils/` contains pure policies for lifecycle, queues, gestures, backends, timing, and filtering.
- `android/app/src/main/kotlin/` contains Android Media3/ExoPlayer integrations.
- `ios/Runner/` contains native AVPlayer, PiP, background audio, and audio-route integrations.

## Search and discovery

Normal YouTube search uses `youtube_explode_dart`; YouTube Music search/discovery uses `ytmusicapi_dart`. An official YouTube Data API implementation remains available through compile-time defines as a fallback. Search results are appended in bounded pages, deduplicated by media ID, and converted to a common `YouTubeVideo` model.

Profiles persist language, favorites, playlists, channels, search history, autoplay, and related UI preferences locally. Search language and UI language follow the active profile.

## Playback resolution

`VideoPlaybackService` resolves a media ID into playable quality options. The standard path prefers a usable HLS timeline and the desired audio language, then tries lazy fallbacks only after a real failure. A loopback proxy supports segmented/range transport and local HLS master playlists where platform players require them. Live streams bypass finite-duration seek assumptions.

Manifests are not broadly prefetched from result lists. Playback resolution starts for the selected media, reducing background requests and avoiding unnecessary YouTube rate-limit pressure.

## Platform backends

Backend selection is explicit and separate from whether an item belongs to YouTube Music:

| Platform | Media | Primary backend | Background surface |
| --- | --- | --- | --- |
| Android | regular video/live | Media3 ExoPlayer | video PiP |
| Android | audio-only song | two reusable Media3 ExoPlayers | system media controls |
| Android | music video | MediaKit compatibility path | system media controls |
| iOS | regular video/live | AVPlayer main player | native video PiP |
| iOS | music video | AVPlayer main player | system media controls, no PiP |
| iOS | audio-only song | two reusable AVPlayers | system media controls |

The dual audio players prepare alternating song slots and overlap them only for automatic song-to-song crossfades. Manual navigation and mixed-media transitions do not crossfade. Backend transitions are validated before a player instance is reused.

## Queue and lifecycle

Search results and saved playlists feed a common playback queue. Separate music/video histories make Previous deterministic; Next first follows forward history, then advances through the active queue. Autoplay and shuffle are profile settings.

The lifecycle policy distinguishes active remote playback from idle background state. An active video can use PiP and music can use system media controls. An idle background session enters soft sleep and later deep sleep, while resumable position and media metadata remain persisted as appropriate.

## Diagnostics and privacy

`AppLog` writes a rolling local log capped at 2 MiB. Queries are represented by opaque IDs, URL query strings are redacted, common authorization/cookie fields are removed, and stack traces are bounded. Logging is best-effort and must never interrupt playback or navigation.

## Native-channel contracts

Flutter/native method-channel calls are covered by contract-style Dart tests where possible. Native iOS behavior still requires Xcode and real-device validation; Android Media3 behavior requires an Android device for PiP, audio focus, Bluetooth, and lifecycle scenarios.
