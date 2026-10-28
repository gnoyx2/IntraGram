# Security policy

## Reporting a vulnerability

Use this repository's **Security › Report a vulnerability** form when it is
available. The publication repository is
[gnoyx2/Intragram](https://github.com/gnoyx2/Intragram/security/policy).
GitHub private vulnerability reporting must be enabled on the public
repository; this policy alone does not enable it.

Planned backup contact: **jung@yonghun.pro — not yet available**. The receiving
mail service is not activated, so do not rely on this address until its status
is updated after a successful receipt check. If no private reporting form is
available either, wait for a working private route; do not post details in an
issue or pull request. Reports in English or Korean are welcome.

Include the app version or commit, OS, steps to reproduce and expected impact.
Use synthetic data instead of real conversations, private keys, tokens or PINs.
Please do not open a public issue or pull request for a vulnerability, and do
not include a working exploit against a third party.

## Supported versions

This is a release candidate; no platform has completed real-device QA yet.
Platform support requires the checks in `DEVICE_QA.md`. The wire protocol is
versioned (`v7` today), and a device speaking any other version is refused at
the handshake. Peers must use the same wire protocol. Use the current build
for available security fixes.

## Independent review

Intragram has not had an independent security audit or a third-party
penetration test. Every fix has a regression test, but tests are not an audit.
Do not rely on it where a failure would put someone in danger.

## What it is built to defend against

- **Anyone else on the same LAN.** App-to-app links use an ephemeral X25519 key
  agreement with ChaCha20-Poly1305. A peer's ID is proven: it is the hash of a
  per-launch Ed25519 key that never leaves RAM, and each side signs the
  handshake with it. A 6-digit code lets two people compare out loud to catch a
  man in the middle. This covers a 1:1 chat end to end, but a group room only
  hop by hop (see below).
- **Any path to the public internet.** Every outbound socket goes through
  `NetworkGuard` and is limited to RFC 1918, link-local, loopback and IPv6
  unique local (`fc00::/7`) addresses. Dialing a peer accepts only canonical
  dotted-decimal RFC 1918 IPv4. This checks destinations, not the route: a VPN
  or overlay that assigns private addresses carries the traffic over the
  internet inside its own tunnel.
- **Data left behind.** By default no chat is written to disk. Accepted files
  are saved. On desktop the folders you picked for downloads are listed in
  `download_directories.json` so half-received files can be cleaned up after a
  crash (on macOS with a sandbox bookmark, because the sandbox forgets a picked
  folder when the app quits). The optional local vault is off until you turn it
  on and can be sealed with a PIN. A display name you choose to remember is
  stored in that vault, or in plaintext `identity.json` when the vault is off.
  Panic wipe attempts to erase the vault, saved name and folder list and
  replaces the identity key. Android's OS backup of app
  data is disabled. Flutter and the OS keep their own caches (shader cache,
  window position, the app switcher snapshot, which iOS covers and Android
  blocks). File selection/sharing plugins and the OS can leave temporary
  copies or caches; startup and Panic wipe attempt to sweep app-private temp
  folders. No physical erasure of those copies is guaranteed.
- **Malicious peers.** Filenames are sanitized and checked against path
  traversal, frames are strictly parsed, a room's host routes file offers per
  recipient, and unauthenticated sockets are capped (4 per host, 16 overall, 24
  connects per 10 seconds per host, 96 overall). The guest portal takes at
  most 32 browser guests, and an HTTP connection that never finishes its
  request is closed after 10 to 20 seconds.

## Signed evidence, organization credentials and app room integrity

- **Receipts.** Ed25519 delivery receipts bind the recipient, sender key,
  current transfer attempt and measured content digest after receive commit.
  Burn and cleanup receipts state policy triggers and app-managed cleanup
  outcomes. Peers without receipts can still use the legacy ACK path; a missing
  receipt is not a verified receipt. Rejected receipts never enter a batch.
- **Salted Merkle evidence.** Each receipt has a random 16-byte leaf salt;
  signed batch headers and inclusion paths support whole or selected JSON
  disclosure. Message burn commitments use a separate secret salt that is
  discarded. File digests remain comparable to known files. Evidence is RAM
  only (512 receipts, 64 batches, 64 witness observations), excluded from vault
  snapshots and decoy mode. Panic freezes new evidence and clears evidence,
  organization credentials and room ledgers synchronously before the first
  shutdown await, then clears them again after resource drain. In-flight work
  is generation-checked. Quitting and relocking also clear the state.
- **Witnesses.** Manual export/verify/sign/import on another device anchors
  one batch root to a separately confirmed witness peer ID; self-witnesses are
  refused. A repeated requester/batch number with a different observed root
  reports a conflict. This is no consensus protocol, global append-only ledger,
  trusted timestamp or proof of physical deletion. A signer can lie about a
  cleanup; an unobserved or forgotten fork is not detected.
- **Organization credentials.** Issuer signatures, subject key, allowed policy,
  validity dates, trust snapshot and that snapshot's revocation list are checked.
  Holder proof binds both peer IDs, session and roles; credential frames follow
  encrypted link establishment and never enter discovery. Credential status
  does not alter SAS verification. The bundled demo issuer has a public seed:
  anyone can issue its credentials, so its badge proves no actual affiliation.
  Offline checks cannot learn revocations newer than the chosen snapshot.
- **App rooms.** Author signatures bind counters, previous-event hashes and
  payload commitments with a fresh 32-byte salt. Observed ledgers keep opaque
  hashes and previous hashes, not payload commitments, salts or signatures;
  burning/deleting also retires the author's retry envelope. Signed duplicate
  counters never reinsert a body or restart TTL, even after detailed observations
  leave the 256-item window. Compressed replay ranges live until room removal;
  at 256 disjoint ranges new disjoint intervals are rejected; adjacent counters
  and fills within existing gaps remain accepted. Checkpoint comparisons use
  the latest 256 observations and detect disagreements only when both views
  are observed. The host can still read, withhold and reorder traffic; no
  distributed consensus or group E2EE is added. Legacy unsigned peers can chat
  until signed capability is observed. Author payload/signature domains are v2
  with a required 32-byte payload salt; prior prerelease signed-v1 envelopes
  without it are rejected. Browser portal rooms are separate and
  have none of these author/checkpoint guarantees.
- **Audit clipboard.** Whole bundles, individual proofs and witness receipts
  all use `OsPrivacy.copySensitive`: Android sensitive marking, Apple local-only
  copying and Windows history/cloud exclusion. The app attempts to clear its
  own copy after 60 seconds; on Android this can wait until the app returns
  to the foreground.
  On Windows the expiry compares the clipboard owner window and the sequence
  number read after `CloseClipboard`, which bumps the number when Windows
  synthesizes text formats; a copy made by another app, even of the same text,
  is never cleared. Linux clipboard managers and deliberate exports may retain
  copies. Export
  reveals the selected signed receipt metadata, IDs/keys, commitments, times,
  leaf salts/paths, batch header and optional witness receipt; it includes no
  message body. Export and witness exchange are user-initiated, with no automatic
  gateway upload. Treat the resulting metadata as sensitive.

## What it does not defend against

- **A compromised device, or the host of a group room.** A group room is
  encrypted hop by hop, not end to end: each member's link to the host is
  encrypted, but the host decrypts every message to relay it, so it can read
  everything in that room. Members verify the host's code, not each other's.
- **Files in a group room.** Room files are never encrypted: they go directly
  between devices, and two members share no key. Anyone who can capture traffic
  on the LAN can read them. Changing them is caught for app members: the offer
  travels over the encrypted links and carries the file's SHA-256, and a
  receiving app deletes a file whose bytes do not match. Browser guests cannot
  check this, and the host can still offer whatever it likes. Send sensitive
  files in a 1:1 chat.
- **Browser guests.** A browser cannot run the handshake, so guest traffic is
  plain text on the local link. That includes the portal entry code (`#t=…`):
  it stays valid, for any number of guests, until the host turns the guest
  portal or the server off, and turning the portal on again issues a new one.
  Anyone who sees the QR code or the full address, or captures the Wi-Fi
  traffic, can join until then, so turn the portal off once everyone is in.
- **First contact.** The shown name, platform and port are self-declared. A
  first contact is only as trustworthy as the 6-digit code you actually compare.
- **Keyboards.** On Android the app asks keyboards not to learn from what you
  type, which well-behaved keyboards honour. iOS has no such switch: the system
  keyboard may add words to its on-device dictionary, and a third-party
  keyboard with Full Access can send what you type over the network. Use the
  system keyboard for sensitive chats.
- **Memory remnants.** Message text passes through Dart strings, which cannot be
  scrubbed, and the crypto library keeps its own copies of the X25519 private
  key and HKDF intermediates, which the app can only release. Panic wipe drops
  every reference and overwrites the buffers the app owns (session and vault
  keys, frame plaintext, file chunks, voice audio); the rest stays in freed
  memory until it is reused. Swap files, crash dumps and OS caches may hold
  copies.
- **Copied text on Linux.** Copying a message, the security code, the portal
  link or an audit bundle/proof/witness receipt marks the copy as sensitive on Android, keeps it on this device on iOS
  and macOS (no Universal Clipboard) and keeps it out of clipboard history and
  cloud sync on Windows, then attempts to clear it after 60 seconds if it is
  still ours. Android can defer that check until the app is in the foreground.
  On Linux the app keeps ownership of the copy, offers the KDE
  `x-kde-passwordManagerHint` secret hint and clears it after 60 seconds only
  while it still owns the clipboard; a clipboard manager may ignore the hint
  and keep a copy.
- **Where the vault lives on Apple platforms.** `vault.json` and `identity.json`
  live in the app's Application Support/IntraGram directory, separate from
  received files in `Documents/IntraGram`. On iOS the app requests complete file
  protection and backup exclusion for the private directory and files; these
  properties still need device verification. Received files may be backed up.
  On macOS, system backups may include the vault.
- **Weak PINs and offline guessing.** Vault sealing uses PBKDF2-HMAC-SHA256
  with 200,000 iterations and a random 16-byte salt, then ChaCha20-Poly1305.
  Version 1.0 does not use Argon2id, although the crypto dependency supports
  it. PBKDF2 is not memory-hard, and 200,000 iterations are below
  [OWASP's current PBKDF2-HMAC-SHA256 guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
  They only slow offline guesses against a copied vault, especially with a
  short PIN. The app's retry delay cannot protect a copied file. Choose a
  long, unpredictable PIN.
- **Availability.** A device on the LAN can still use up handshake capacity or
  flood a link. The caps above limit, not prevent, that.
- **Screenshots.** Android enables `FLAG_SECURE` to block ordinary OS screenshots
  and screen recordings. Windows requests capture exclusion
  (`WDA_EXCLUDEFROMCAPTURE`), which can fail or be ignored. macOS marks the
  window as not shareable, which
  recent capture tools may ignore, and reports the screenshots it notices. iOS
  detects screenshots after capture and obscures app switcher snapshots; it
  cannot prevent a screenshot. Linux has no such control, and nothing stops an
  external camera.
- **Distribution signing.** CI signs Android with a release key only when
  configured. Its iOS builds are unsigned, macOS builds are ad-hoc signed and
  not notarized, and Windows builds are unsigned; Linux has no OS-level signing.
  Check the release's measured `SIGNING-<platform>.txt`, `SHA256SUMS.txt` and
  available build provenance.
