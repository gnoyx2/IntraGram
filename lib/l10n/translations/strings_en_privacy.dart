// 개인정보 처리 방침 (설정 › 앱 › 개인정보 처리 방침, PRIVACY.md와 같은 문구)
const Map<String, String> kStringsEnPrivacy = {
  'privacy.title': "Privacy policy",
  'privacy.noServerTitle': "No server, no account",
  'privacy.noServerBody':
      "IntraGram automatically sends no data to the developer or to a cloud "
      "service, and needs no sign-up, phone number or email address.",
  'privacy.onDeviceTitle': "What stays on this device",
  'privacy.onDeviceBody':
      "Messages, transfer records and session keys live in memory. Burning a "
      "message drops its body; up to 512 body-free signed receipts with salted "
      "commitments, 64 signed Merkle batches and 64 witness-root observations "
      "can remain in RAM. Receipt metadata includes event/subject/attempt IDs, "
      "peer IDs and public keys, commitments, policy/outcome, nonce and time. "
      "File receipts contain a SHA-256 content digest, which permits known-file "
      "comparisons. Evidence, organization credentials and room integrity state "
      "are excluded from the vault. Panic wipe blocks new evidence and clears "
      "these states synchronously before waiting for shutdown, then clears them "
      "again; quitting also clears them. The app writes accepted files and, if "
      "enabled in Settings, the optional PIN-sealed vault to disk. On desktop "
      "it also records picked download folders to clean up interrupted "
      "downloads. Panic erases the vault and folder list; removing the app "
      "removes its own folder.",
  'privacy.networkTitle': "What leaves this device",
  'privacy.networkBody':
      "Messages go to devices you connect to on this local network. App-to-app "
      "1:1 chats are end-to-end encrypted; the host reads an app group room and "
      "room files cross the LAN unencrypted. Browser portal rooms are separate "
      "and their traffic is plaintext on Wi-Fi. Optional offline organization "
      "credentials contain organization, department, role, issuer, policy, "
      "trust snapshot, expiry and the session identity public key. They are "
      "held in RAM and presented only after an encrypted app link is "
      "established, with proof of key possession; they do not verify the "
      "security code. The bundled demo issuer is public and proves no real "
      "affiliation; offline revocation checks cover only the selected snapshot. "
      "Signed author events and checkpoints accompany app room messages. When "
      "you explicitly copy an audit bundle, it contains selected signed "
      "receipts, IDs, public keys, commitments, times, salts/proof paths, a "
      "signed batch header and any attached witness receipt, without message "
      "bodies. Manual witness exchange lets another device inspect that "
      "exported metadata and sign its root; no gateway is contacted "
      "automatically. Audit copying uses the sensitive clipboard route with a "
      "60-second expiry; Linux clipboard managers may keep copies. You control "
      "who receives an exported copy.",
  'privacy.desktopWebTitle': "Desktop and browser privacy",
  'privacy.desktopWebBody':
      "macOS does not donate conversations or aliases to Siri, Spotlight or "
      "NSUserActivity. Its legacy window sharing restriction cannot guarantee "
      "protection against ScreenCaptureKit or Visual Intelligence. Windows uses "
      "capture exclusion for supported OS capture APIs and payload-free taskbar "
      "flashing instead of Toast history; neither is a security boundary. Linux "
      "marks copied text with the KDE secret hint and clears only clipboard "
      "contents it owns; clipboard managers may ignore the hint. Browser guests "
      "use the host-served inline page with SHA-256 CSP, no external requests or "
      "persistent message storage. Cancelled or incomplete downloads are not "
      "acknowledged, and burning a voice message or hiding the page releases its "
      "audio URL; a voice message released this way says it is no longer "
      "available when the page comes back and is not downloaded again. "
      "Releasing browser resources cannot guarantee physical memory erasure or "
      "prevent OS swap.",
  'privacy.discoveryTitle': "Being found",
  'privacy.discoveryBody':
      "So that nearby devices can find it, the app announces your display name, "
      "platform and port on the local network (mDNS). Anyone on the same "
      "network can see them.",
  'privacy.permissionsTitle': "Permissions",
  'privacy.permissionsBody':
      "Local network: to find and talk to nearby devices. Microphone: only "
      "while you record a voice message. Camera: only to scan connection and "
      "security codes; no photos are kept. Notifications: new messages while "
      "the app is in the background. Photos: only the ones you pick.",
  'privacy.thirdPartyTitle': "Third parties",
  'privacy.thirdPartyBody':
      "IntraGram sends no telemetry or automatic reports to third parties. Your "
      "connected peers and the recipients you choose for exported audit bundles "
      "receive the data described above. QR codes are read on the device by "
      "open-source code that has no network component.",
  'privacy.contactTitle': "Questions",
  'privacy.contactBody':
      "Open an issue on the project's GitHub page. Report security problems "
      "privately as described in SECURITY.md.",
};
