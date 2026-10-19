# Releasing IntraGram

Maintainer notes for cutting a release. Signing material never goes in the
repository: `*.jks`, `*.keystore`, `key.properties`, `*.p12`, `*.p8`, `*.pfx`,
`*.mobileprovision` and `.env*` are git-ignored. Do not paste a password,
token or certificate into a commit, an issue, a log or a release note.

## 1. Gates (run on the exact commit you will build)

```bash
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
python3 tool/check_loc.py
flutter analyze
flutter test --exclude-tags large
node tool/browser_guard_test.js
node tool/web_design_test.js
git diff --check
flutter test --tags large     # 64/256 MiB; add --dart-define=LARGE_SIZES_MIB=1024,4096 for 1/4 GiB
```

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
`PRIVACY.md` (also in the app under Settings, App, Privacy policy). Before
answering "no data collected" in Data safety, confirm on a device with a packet
capture that the app, including a QR scan, opens no connection to a public
address (DEVICE_QA N9; the scanner decodes on the device and bundles no ML Kit
or other Google service). Target SDK 36, min SDK 24.

Before raising the target to SDK 37: Android 17 then enforces local network
protection (the runtime `ACCESS_LOCAL_NETWORK` permission covers mDNS,
NsdManager and inbound TCP). Request it with a short explanation before the
first discovery and give a denied permission the same recovery path as iOS
Local Network (the checklist's Open settings button), or discovery and inbound
chats stop on Android 17.

## 4. iOS and macOS

`flutter build ios --release --no-codesign` and a plain
`flutter build macos --release` produce files that run only on the build
machine or after re-signing. They are not store or distribution evidence.

- **iOS (TestFlight / App Store)** needs an Apple Developer Program team for
  automatic signing. The project does not name one: put
  `DEVELOPMENT_TEAM = <your team ID>` in `ios/Flutter/Signing.xcconfig`, which
  git ignores and the Debug and Release configs include. If Xcode's Signing &
  Capabilities pane writes the team into `project.pbxproj`, move it back to that
  file before committing (`test/apple_signing_test.dart` fails otherwise). Then
  `flutter build ipa --release` and an upload with Xcode Organizer or
  Transporter. The app runs its own standard
  encryption (X25519, ChaCha20-Poly1305 from the Dart `cryptography` package,
  not Apple's OS crypto), and `Info.plist` sets `ITSAppUsesNonExemptEncryption`
  to `false`, so App Store Connect skips the export compliance questions. That
  holds only while France is left out of the availability list: Apple says
  France controls secure communication apps and wants a French encryption
  declaration for apps that use standard algorithms. To ship there, set the key
  to `true`, answer "standard encryption algorithms" and upload the declaration.
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

## 5. Windows and Linux

Both must be built on their own OS. A macOS compile says nothing about them.

- **Windows** (10/11 x64, Visual Studio 2022 "Desktop development with C++"):
  `flutter build windows --release`, then ship the whole
  `build\windows\x64\runner\Release` folder (exe, DLLs, `data`). CI also copies
  the VC++ runtime DLLs next to the exe. Without a code-signing certificate
  SmartScreen warns; to sign: `signtool sign /fd SHA256 /tr <timestamp-url> /td SHA256 /a intragram.exe`.
- **Linux** (x64): build needs `clang cmake ninja-build pkg-config libgtk-3-dev`.
  Users need `pulseaudio-utils` (voice messages: `parecord` records, `pacat`
  plays), `avahi-daemon` (mDNS discovery) and `xdg-desktop-portal` with a
  backend (`-gtk`, `-gnome` or `-kde`) for file dialogs. There is no OS-level signing; publish
  checksums. The bundle carries `install.sh`, which adds the desktop entry and
  icons to the user's app menu.

Known plugin warnings in macOS and iOS builds (an unused `resolveAddress`
result in bonsoir, an objective_c framework name mismatch) are upstream; check
for plugin updates each release. Planned for 1.0.1: file_picker 13.1 (UIScene
support on iOS) and record 7 (honours iOS interruption resume), after the iOS
file picking and call-interruption checks in DEVICE_QA.

## 6. Publishing

Before the repository or a store listing goes public, tick each of these by
hand; nothing in the repository can enforce them:

- [ ] **History.** Publish a fresh snapshot of the release commit as a new
  history (one initial commit), not this working history: early commits carry
  a personal name and a machine hostname as author e-mail, and removed internal
  notes are still in older trees. Check the snapshot's author line and run a
  secret scan over it before the first push.
- [ ] **App Store availability.** France stays unticked in App Store Connect
  while `ITSAppUsesNonExemptEncryption` is `false` (see section 4); the
  setting lives in App Store Connect, so re-check it on every submission.
  France's own declaration rule (décret 2007-663) applies to any distribution
  there, not only Apple's.
- [ ] **Vulnerability reports.** Turn on private vulnerability reporting, send
  one test report to confirm it arrives, and add a second private contact to
  `SECURITY.md`.
- [ ] **Store listing support contact.** App Review and Play want a support
  e-mail or URL; decide it before submitting.

Repository settings: enable Issues and private vulnerability reporting, and
confirm that the bug-report template and the private route in `SECURITY.md`
work. Keep Linux labeled unreviewed until its `DEVICE_QA.md` checks pass; do
not call any platform supported before that QA. `DEVICE_QA.md` section 9 sets
what each publishing stage needs: source only, an `-rc` pre-release with the
platforms whose smoke set passed (leave the others' files out of the release),
and "supported" after the full list including accessibility.

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
