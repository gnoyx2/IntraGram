# Releasing IntraGram

Maintainer notes for cutting a release. Signing material never goes in the
repository: `*.jks`, `*.keystore`, `key.properties`, `*.p12`, `*.p8`, `*.pfx`,
`*.mobileprovision` and `.env*` are git-ignored. Do not paste a password,
token or certificate into a commit, an issue, a log or a release note.

Public source baseline: app `1.0.0+7`, wire protocol `7`, from development
HEAD `c5b247b` plus the current desktop/web work and Apple CI toolchain update.
Only selected project files are exported into the separate public history;
development Git history, local build state and signing material are excluded.

## 1. Gates (run on the exact commit you will build)

```bash
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
python3 tool/check_loc.py
flutter analyze
flutter test --exclude-tags large
node tool/browser_guard_test.js
node tool/web_design_test.js
sh -n linux/install.sh
flutter build macos --debug
git diff --check
# Optional, outside the ten required gates; not run in the verification below.
flutter test --tags large     # 64/256 MiB; add --dart-define=LARGE_SIZES_MIB=1024,4096 for 1/4 GiB
```

Historical local verification (2026-10-26, development snapshot): all ten
required commands exit 0;
**1,411 Flutter tests** (`large` excluded, 0 failed, 0 skipped), **21 browser
guard groups** (374 assertion calls), **88 web design assertion calls** and 0
analyzer issues. The macOS debug app builds, but not warning-free. Which warning
appears depends on the build:

- Clean build (fresh copy, every plugin compiled): `bonsoir_darwin` 7.1.1 warns
  `result of call to 'resolveAddress(for:hostname:)' is unused`
  (BonsoirServiceDiscovery.swift:227); Xcode 27.1 also prints those lines as
  `error: ... failed with exit code 0` while the build succeeds. An incremental
  build of an already compiled plugin does not repeat it.
- Every build: Flutter lists `flutter_local_notifications` and `pasteboard` as
  plugins without Swift Package Manager support for macOS.
- This Mac only: CoreSimulator 1171.7.0 is older than Xcode 27.1's 1174.9.2, so
  xcodebuild disables simulator support; the macOS build is unaffected.

No app (Runner) warning appeared. These warnings are not suppressed and no
dependency or signing team setting changed. The application code and tests
match private CI snapshot `95a1db6` (branch `desktop-web-20261026`,
tree `508b1c4`); documentation and Apple CI configuration changed afterward.
Check this commit's own Actions runs before release. In the private snapshot:
`native` run 40309070215 passed windows (windows-2022 debug, no compiler
warnings), linux (ubuntu-24.04: Linux desktop logic test, CMake debug build and
link, bundle `install.sh` syntax) and the macOS debug step, and `ci` run
40309070292 passed verify (1,411 tests on Linux) and the Android debug APK. The
`apple` job's iOS debug step failed: the macos-15 runner's Xcode has no
`UIHinge` (iOS 27.1 SDK) used by `ios/Runner/DisplayRegions.swift` from c5b247b.
The current `native` and `release` Apple jobs use `xcode-27` with
`DEVELOPER_DIR=/Applications/Xcode_27.1.app/Contents/Developer` and log the
selected Xcode version and iOS SDK. Run both workflows on the release commit
before relying on their results. The [runner image lists Xcode 27.1](https://github.com/actions/runner-images/releases/tag/xcode-27-arm64%2F20261023.0307);
[Apple requires macOS 26.6 or later](https://developer.apple.com/xcode/system-requirements),
so `macos-15` cannot supply this toolchain. Headless Firefox 158 checks are
browser automation, not device QA. Large-transfer and physical target-OS QA
were not run.

Desktop/Web scope: live accessibility and native menus on macOS 27 (requested
Golden Gate profile), Windows 11 25H2/26H2 taskbar attention without Toast,
GNOME 50/KDE Plasma 6 CSD/SSD, asynchronous XDG portals, sensitive clipboard
hints and PulseAudio/PipeWire pipes. The guest remains assets/web + inline
SHA-256 CSP, with streaming cancellation, voice resource disposal, BFCache
reconnection, 840 px chat width and forced colors. No root web/ target.
Capture exclusion cannot certify Visual Intelligence/ScreenCaptureKit blocking
or absolute Windows capture protection; verify actual capture tools in QA.

Re-run the gates on the release commit after any further changes.

Build release artifacts from a clean export of that commit, not from a
working tree with local leftovers: `git archive <commit> | tar -x -C <dir>`.

## 2. Version

`pubspec.yaml` `version: X.Y.Z+N`. `N` is the Android `versionCode` and the
iOS/macOS build number: it must go up with every upload. The wire protocol
version (`kProtocolVersion`, `PROTOCOL_VERSION` in `assets/web/js/socket.js`)
is separate and only changes when the wire format changes.

## 3. Android

The release build is signed with `android/key.properties`. Without that file
`flutter build apk --release` and `appbundle --release` stop with "No release
key", so a debug-signed file never comes out under a release name by
accident. For a test build on your own devices, set
`ORG_GRADLE_PROJECT_allowDebugSigning=true`; that APK is signed with the public
debug key and is not a release, since anyone can produce an APK with the same
signature.

Create the upload key once and back it up somewhere off the build machine:

```bash
keytool -genkeypair -v -storetype PKCS12 -keystore /absolute/path/intragram-upload.jks \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

`android/key.properties` (Java properties: avoid backslashes in values):

```
storeFile=/absolute/path/intragram-upload.jks
storePassword=<password>
keyAlias=upload
keyPassword=<password>
```

Build, then verify the signer before shipping:

```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release
APKSIGNER=$(ls "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
"$APKSIGNER" verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
keytool -J-Duser.language=en -J-Duser.country=US -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

(`keytool` fails with a formatting error under some non-English locales, hence
the `-J` flags.) The certificate must not be `CN=Android Debug`.

`flutter build appbundle` also needs the Android SDK "Command-line Tools
(latest)" component (Android Studio, SDK Manager, SDK Tools). Without it the
tool prints "Release app bundle failed to strip debug symbols from native
libraries" and exits non-zero, although Gradle did build the `.aab`.

For CI, store the keystore as base64 in the `ANDROID_KEYSTORE_BASE64` secret,
plus `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and
`ANDROID_KEY_PASSWORD`; `release.yml` restores it and checks the result.

Play Console notes: `applicationId` (see `android/app/build.gradle.kts`) cannot
change after the first upload. Use Play App Signing with the key above as the
upload key. Expect declaration forms for the `remoteMessaging` foreground
service (describe it as keeping the opt-in LAN chat open to receive messages
from the user's nearby devices while the app is in the background, and that
turning it off only means messages arrive when the app is open again) and
the camera (QR scan only) and microphone (voice messages) permissions. The app
has no server and the developer collects nothing; the privacy policy is
`PRIVACY.md` (also in the app under Settings, App, Privacy policy). Both stores
want it at a public URL, so link the file on the public repository (or a
GitHub Pages copy) in the listing. Before
answering "no data collected" in Data safety, confirm on a device with a packet
capture that the app, including a QR scan, opens no connection to a public
address (DEVICE_QA N9; the scanner decodes on the device and bundles no ML Kit
or other Google service). Target SDK 36, min SDK 24.

Android 17 local-network support is implemented: the manifest declares
`ACCESS_LOCAL_NETWORK`; native code uses the permission string and integer
`SDK_INT >= 37`, so compile SDK 36 remains valid. The runtime gate also checks
target SDK 37+, matching Android's enforcement boundary; older targets return
granted without a prompt. Before shipping a target-37 build, run DEVICE_QA F7:
request before binding/discovery, deny, open app settings, enable, refresh.
`NEARBY_WIFI_DEVICES` remains absent. The activity is resizable, handles fold
and freeform size changes without recreation, and keeps edge-to-edge system
bars transparent. Verify a 320×360 floating bubble with the keyboard (F4).

## 4. iOS and macOS

`flutter build ios --release --no-codesign` produces an unsigned iOS app.
A plain `flutter build macos --release` produces an ad-hoc-signed macOS app
that is not notarized; Gatekeeper may require manual approval on another Mac.
Neither command proves App Store signing or notarized distribution.

- **iOS (TestFlight / App Store)** needs an Apple Developer Program team for
  automatic signing. The project does not name one: put
  `DEVELOPMENT_TEAM = <your team ID>` in `ios/Flutter/Signing.xcconfig`, which
  git ignores and the Debug and Release configs include. If Xcode's Signing &
  Capabilities pane writes the team into `project.pbxproj`, move it back to that
  file before committing (`test/apple_signing_test.dart` fails otherwise). Then
  `flutter build ipa --release` and an upload with Xcode Organizer or
  Transporter. The app runs its own standard
  encryption (X25519, ChaCha20-Poly1305 from the Dart `cryptography` package,
  not Apple's OS crypto). `Info.plist` currently sets
  `ITSAppUsesNonExemptEncryption` to `false`; this is not a completed export
  determination. Before uploading, answer Apple's encryption questions for
  the actual build and countries, then align this key and any declaration/code
  with that result. Apple's documentation table calls for a French declaration
  when distributing in France with standard encryption implemented outside the
  OS; do not infer the app's complete compliance from a country checkbox.
  See the export-compliance gate in section 6.
  For App Review notes: there is no operator server, account or public feed;
  people on the same LAN talk directly. A device can be blocked from a chat's
  menu, and Settings, Only chats I start refuses devices the user has not
  talked to. Review also wants a support contact (an e-mail or URL besides the
  private vulnerability report); add it to the store listing before upload.
- **macOS outside the Mac App Store** needs a "Developer ID Application"
  certificate, hardened-runtime signing with `macos/Runner/Release.entitlements`,
  then notarization and stapling:

  ```bash
  xcrun notarytool submit IntraGram.zip --keychain-profile <profile> --wait
  xcrun stapler staple IntraGram.app
  spctl --assess --type execute --verbose IntraGram.app   # expect: accepted, source=Notarized Developer ID
  ```

Without those, users must approve the app by hand: on macOS 15 and later
through System Settings, Privacy & Security, Open Anyway, and on 12 to 14 by
right-clicking the app and choosing Open.

The Mac App Store is a different path: the app would need a sandboxed App
Store build and its own `PrivacyInfo.xcprivacy` (the macOS runner reads
`UserDefaults` to restore the window frame, a required-reason API, `CA92.1`).
iOS already ships one in `ios/Runner/PrivacyInfo.xcprivacy`.

iOS 27 Liquid Glass accessibility follows live Reduce Transparency and high
contrast with opaque surfaces and defined borders; Safari guests use CSS
fallbacks. Privacy covers resize with every scene/window and do not enable
Spotlight/NSUserActivity chat indexing. Device idiom keeps unfolded iPhones
identified as iOS. On iOS 27.1+ `ios/Runner/DisplayRegions.swift` reports the
system's fold (division regions and hinge state) into the same display-feature
layout Android uses; older iOS keeps the center-split guess. Before release, run
DEVICE_QA F1–F6 and F9 for the requested iPhone Duo profiles, book/clamshell
continuity, hinge avoidance and tabletop QR placement, and F10 for back
gestures over dialogs. Browser viewport segment checks are F8. Automated layout tests do
not certify a device or replace camera/snapshot verification.

## 5. Windows and Linux

Both must be built on their own OS. A macOS compile says nothing about them.

- **Windows** (10/11 x64, Visual Studio 2022 "Desktop development with C++"):
  `flutter build windows --release`, then ship the whole
  `build\windows\x64\runner\Release` folder (exe, DLLs, `data`). CI also copies
  the VC++ runtime DLLs next to the exe. Without a code-signing certificate
  SmartScreen warns; to sign: `signtool sign /fd SHA256 /tr <timestamp-url> /td SHA256 /a intragram.exe`.
- **Linux** (x64): build needs `clang cmake ninja-build pkg-config libgtk-3-dev`.
  Users need PulseAudio tools (`parecord`/`pacat`) or PipeWire tools
  (`pw-record`/`pw-play`, then `pw-cat` fallback) for voice messages; with
  PulseAudio tools but no reachable server the app switches to PipeWire once
  (recording before its first audio, playback from where it stopped), `avahi-daemon` (mDNS discovery) and `xdg-desktop-portal` with a
  backend (`-gtk`, `-gnome` or `-kde`) for file dialogs. There is no OS-level signing; publish
  checksums. The bundle carries `install.sh`, which adds the desktop entry and
  icons to the user's app menu.

Known plugin warnings in macOS and iOS builds (an unused `resolveAddress`
result in bonsoir, an objective_c framework name mismatch) are upstream; check
for plugin updates each release. Planned for 1.0.1: file_picker 13.1 (UIScene
support on iOS) and record 7 (honours iOS interruption resume), after the iOS
file picking and call-interruption checks in DEVICE_QA.

## 6. Publishing

### Source publication

- [x] **Separate public history.** This repository contains the selected public
  snapshot and its subsequent reviewed changes, not the development repository's
  history. Keep that separation: do not merge private development branches or
  copy its raw `.git` directory into a publication. Re-check all refs, commit
  identities and secrets on the final publication commit; a single root commit
  is not required for an already sanitized public history.
- [x] **License notices.** The LocalSend modifications retain attribution and
  the Apache-2.0 text. The resolved package license inventory and exact MPL-2.0
  `dbus` source are recorded in `THIRD_PARTY_NOTICES.md` and bundled in the app.
- [ ] **Security email before publication.** Confirm that the monitored
  `jung@yonghun.pro` address in `SECURITY.md` and the issue chooser is correct,
  and verify receipt of a harmless test email. Configuring a mailto link or
  checking DNS does not prove delivery.
- [ ] **GitHub reports when publishing.** Private vulnerability reporting is
  available only for public repositories. After creating the actual public
  repository, enable it in Settings, Security and quality, Advanced Security;
  confirm the Report a vulnerability button and maintainer notifications,
  and verify receipt of a harmless test report. Do not use the private CI
  mirror as the public reporting destination.

Repository settings: enable Issues and confirm that the issue chooser shows
`jung@yonghun.pro`. GitHub does not support mailto contact-link URLs; keep a
valid HTTPS link. Once the actual public repository is known, replace the
chooser's general GitHub guide URL with
`https://github.com/OWNER/REPO/security/policy` and verify the rendered chooser.
After publication, enable private vulnerability reporting and verify that
`GET /repos/OWNER/REPO/private-vulnerability-reporting` returns `enabled: true`
([GitHub setup](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository)).
Keep Linux labeled unreviewed until its `DEVICE_QA.md` checks pass; do
not call any platform supported before that QA. `DEVICE_QA.md` section 9 sets
what each publishing stage needs: source only, an `-rc` pre-release with the
platforms whose smoke set passed (leave the others' files out of the release),
and "supported" after the full list including accessibility.

### Binary and store distribution

- [ ] **Device QA.** Pass the required `DEVICE_QA.md` stage for each platform
  whose binary will be attached. Debug compilation is not a device PASS.
- [ ] **Release build and signing.** Run the release workflow on the exact
  candidate commit and inspect `SIGNING-<platform>.txt` and checksums. Keep
  debug-signed test APKs out of public distribution.
- [ ] **App Store export compliance.** Before a TestFlight or App Store upload,
  complete Apple's encryption determination for the actual build and intended
  countries. Reconcile `ITSAppUsesNonExemptEncryption` and any required
  declaration/code with that result; the current `false` value is not proof of
  exemption. See [Apple's process](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
  and [France-specific documentation](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/).
- [ ] **Store listing support contact.** Set the monitored support address or
  URL in the actual App Review/Play listing before submission.

1. Before the first tag, run the `release` workflow by hand (Actions, Run
   workflow) and read the `SIGNING-<platform>.txt` files it attaches. The
   `native` workflow (debug builds of iOS, macOS, Windows and Linux) runs on
   its own when those folders change; run it by hand too if it has not run on
   this commit. If a platform's job cannot pass, leave that platform out of
   the release and say so in the README status table.
2. Tag the verified commit, for now as a release candidate:
   `git tag vX.Y.Z-rc.N`. Every release, with or without a hyphen, is marked
   a GitHub pre-release until the repository variable `DEVICE_QA_PASSED` is
   set to `true` (Settings, Secrets and variables, Variables), which you do
   only after `DEVICE_QA.md` passes. Pushing the tag creates a **draft**
   release with `SHA256SUMS.txt`.
3. Check the draft against the README status table, then publish it.
