# Changelog

Versions follow the app version in `pubspec.yaml`. The wire protocol version
(`kProtocolVersion` in `lib/core/constants.dart`) is listed because apps on
different protocol versions refuse to talk to each other.

## Unreleased (1.0.0 release candidate)

Protocol 7. Not a supported release yet: device QA is pending on every
platform (see `DEVICE_QA.md`).

- 1:1 handshake commits to the dialer's ephemeral key before the listener
  answers, so a relay can no longer steer both screens to the same 6-digit
  code; "codes don't match" ends the link and explains why.
- Rooms close every member link when they end, and the vault keeps no room
  messages.
- Voice messages play from memory with each OS's audio API; no media library
  is bundled and no audio is written to disk.
- Wide windows (iPad landscape, desktop) show the chat next to the list;
  desktop gets the same shortcuts everywhere, context menus at the cursor, a
  text size setting and a macOS menu bar.
- Browser guests stay in after a reload, see who joins and leaves, can send
  several files and like a message from the keyboard, and their burn timers
  start on reading like the app's.
- Linux gets an app menu entry (`install.sh`), notifications and clear errors
  when a portal, `parecord` or `avahi-daemon` is missing.
