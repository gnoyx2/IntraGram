# Contributing to IntraGram

Thanks for helping. The short version of the rules is in the README's
*Contributing* section; this file adds how to get set up and what a pull
request needs.

## Setup

- Flutter 3.44.9 (the version CI pins) and its platform toolchains for what you
  build: Xcode 27.1 with the iOS 27.1 SDK for iOS, Xcode for macOS,
  Android SDK 36 with JDK 17, Visual Studio
  2022 for Windows, `clang cmake ninja-build pkg-config libgtk-3-dev` for Linux.
- `flutter pub get --enforce-lockfile`

## Before you open a pull request

Run the same gates as CI from the repository root:

```bash
dart format --output=none --set-exit-if-changed .
python3 tool/check_loc.py
flutter analyze
flutter test --exclude-tags large
node tool/browser_guard_test.js
node tool/web_design_test.js
git diff --check
```

If you touched native code (`ios/`, `macos/`, `android/`, `windows/`,
`linux/`), build that platform too; CI builds them only when those paths
change.

## What a pull request needs

- A focused change with a test that fails without it (or a note on why it
  cannot be tested, for example native UI that needs a device).
- User-facing text in both `lib/l10n/translations` English and Korean.
- No new storage on disk beyond what the README allows, no socket that skips
  `NetworkGuard`, and a protocol version bump for any wire change.
- An entry under *Unreleased* in `CHANGELOG.md` when users would notice.

Security problems go through the private route in `SECURITY.md`, not an
issue or a pull request. By contributing you agree to license your work under
the MIT License, and to follow `CODE_OF_CONDUCT.md`.
