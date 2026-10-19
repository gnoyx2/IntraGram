# Security policy

## Reporting a vulnerability

Use GitHub's private vulnerability reporting (the repository's Security tab,
"Report a vulnerability"). Please do not open a public issue for a
vulnerability, and do not include a working exploit against a third party.

## Supported versions

Only the latest release is supported. The wire protocol is versioned (`v7`
today) and a device speaking any other version is refused at the handshake, so
all devices in a conversation must run the same release.

## Independent review

IntraGram has not had an independent security audit or a third-party
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
- **Data left behind.** By default no chat is written to disk; only a file you
  accept is saved. On desktop the folders you picked for downloads are listed in
  `download_directories.json` so half-received files can be cleaned up after a
  crash (on macOS with a sandbox bookmark, because the sandbox forgets a picked
  folder when the app quits). The optional local vault is off until you turn it
  on, can be sealed with a PIN, and is erased by Panic wipe, which also removes
  that folder list and replaces the identity key. Android's OS backup of app
  data is disabled. Flutter and the OS keep their own caches (shader cache,
  window position, the app switcher snapshot, which iOS covers and Android
  blocks); they hold no chat content.
- **Malicious peers.** Filenames are sanitized and checked against path
  traversal, frames are strictly parsed, a room's host routes file offers per
  recipient, and unauthenticated sockets are capped (4 per host, 16 overall, 24
  connects per 10 seconds per host, 96 overall). The guest portal takes at
  most 32 browser guests, and an HTTP connection that never finishes its
  request is closed after 10 to 20 seconds.

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
- **Copied text on Linux.** Copying a message, the security code or the portal
  link marks the copy as sensitive on Android, keeps it on this device on iOS
  and macOS (no Universal Clipboard) and keeps it out of clipboard history and
  cloud sync on Windows, then clears it after 60 seconds if it is still ours.
  On Linux it is a plain copy, so a clipboard manager may keep it.
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
  and screen recordings. iOS detects screenshots after capture and obscures app
  switcher snapshots; it cannot prevent a screenshot or an external camera.
- **Unsigned binaries.** Release binaries other than a release-key-signed
  Android build are not code-signed or notarized; verify `SHA256SUMS.txt`.
