# Contributing

Thanks for helping improve MyTube.

## Before opening a change

- Keep credentials, cookies, signed artifacts, device logs, and local SDK paths out of commits.
- Preserve the separation between media type, playback backend, and background-control surface.
- Add or update tests for queue, lifecycle, native-channel, and playback-policy changes.
- Keep user-facing text available in both English and German.

## Local checks

Run these commands from the repository root:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test
```

For Android changes, also run:

```bash
flutter build apk --debug
```

iOS/native AVPlayer or PiP changes require an Xcode build and a real-device test. Windows cannot validate Swift compilation or iOS lifecycle behavior.

## Pull requests

Describe the user-visible behavior, affected platforms, test evidence, and any known fallback path. Keep refactors separate from behavior changes when practical.

Unless you explicitly state otherwise, every contribution intentionally
submitted for inclusion in MyTube is provided under the Apache License 2.0,
in accordance with section 5 of that license. By contributing, you confirm
that you have the right to submit the work under those terms and that it does
not contain material whose license is incompatible with the project.

See [LICENSE](LICENSE), [NOTICE](NOTICE), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before submitting third-party
code or assets.
