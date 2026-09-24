# Changelog

All notable user-facing and repository changes are documented here.

## Unreleased

- Prevented Android from applying the system screen timeout while an ordinary
  Media3 video is playing or buffering with active playback intent.
- Restored the normal screen timeout immediately when that video is paused,
  stopped, completed, fails, or its native view is detached.
- Added local, repository-safe Android release signing and produced the first
  cryptographically signed `com.dev.mytube` release APK.
- Raised the minimum supported iOS version from iOS 13 to iOS 15 across the
  Xcode project, CocoaPods platform, and embedded Flutter framework metadata.
- Changed the Android application ID, Android/Kotlin namespace, Apple bundle
  identifiers, and desktop application identifiers to `com.dev.mytube`.
- Kept playlist reordering compatible with older Flutter SDKs while suppressing
  the Flutter 3.47-only deprecation diagnostic at the single affected callback.
- Ensured asynchronous subtitle-loading failures remain inside their intended
  fallback `try`/`catch` path.
- Licensed MyTube's original source code and original project assets under
  Apache License 2.0.
- Added project NOTICE, contribution licensing terms, and a direct-dependency
  license overview without relicensing third-party components.

## 1.0.1+105 - 2026-09-10

- Established the first public-repository baseline.
- Added repository hygiene rules, contribution guidance, architecture documentation, and automated Flutter checks.
- Removed the implicit Android debug-key signing configuration from the release variant.
- Removed the stale hard-coded build number from iOS PiP diagnostics.
- Resolved all existing `use_build_context_synchronously` analyzer findings without changing playback decisions.

## 1.0.0

Initial private development series for Android and iOS. The detailed experimental build history is intentionally not included in the public repository because it contains local recovery paths and device-specific diagnostics.
