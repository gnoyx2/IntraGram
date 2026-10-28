const Map<String, String> kStringsEnSettings = {
  'settings.title': 'Settings',
  'settings.textSize': 'Text size',
  'settings.licenses': 'Open-source licenses',
  'settings.textSizeKeys': 'Shortcuts: {keys}',
  'settings.sectionPrivacy': 'Privacy',
  'settings.sectionApp': 'App',
  'settings.sectionConnection': 'Connection',
  'settings.autoLock': 'Background auto-lock',
  'settings.autoLockMinutes': 'After {n} min',
  'settings.keepChats': 'Keep chats on this device',
  'settings.keepChatsSub':
      'Off by default — everything lives in RAM and is gone when the app '
      'closes. Turn on to save the scopes below to a plain file in this '
      "app's folder. A message the other side deletes still disappears "
      'here, and Panic wipe still erases everything, including that file. '
      'Turning this on also keeps older messages searchable after you '
      'restart. To leave one chat out, turn off Keep on this device in its '
      'menu.',
  'settings.messages': 'Messages',
  'settings.messagesSub': 'Text messages and the conversation list',
  'settings.fileHistory': 'File transfer history',
  'settings.fileHistorySub':
      'A record of completed transfers. The files themselves are already on '
      'disk wherever you saved them.',
  'settings.pinProtect': 'PIN-protect the saved file',
  'settings.pinProtectOnSub':
      'On — the file is unreadable without the PIN. Asked for at launch.',
  'settings.pinProtectOffSub':
      'Off — the file is plain JSON, readable by anything that can open your '
      'app folder.',
  'settings.set': 'Set',
  'settings.restoredNote':
      'A restored chat is a read-only archive. There is no fixed peer '
      'identity, so when the same person connects again it opens a new '
      'conversation.',
  'settings.largeMessages': 'Large messages',
  'settings.largeMessagesSub':
      'How a long typed or pasted message is sent. This one works even with '
      'saving off (it just resets on restart).',
  'settings.large.inline': 'In memory',
  'settings.large.unlimited': 'Unlimited',
  'settings.large.file': 'As a file',
  'settings.large.inlineDesc':
      'Default. Up to about 1 MB — a whole book — rides in RAM like any '
      'other message. Larger is blocked.',
  'settings.large.unlimitedDesc':
      'No size cap. A peer could push a very large message straight into '
      "this device's memory — only use on a network you trust.",
  'settings.large.fileDesc':
      'A message over 64 KB is sent as a "Long message.txt" file you save '
      'and open. Keeps memory small.',
  'settings.iosForegroundOnly':
      'On iPhone and iPad, chats stay connected only while Intragram is open. '
      'iOS pauses the app a few seconds after you leave it; open it again and '
      'the other side can reconnect.',
  'settings.stayConnected': 'Stay connected in the background',
  'settings.stayConnectedSub':
      'Android only. Keeps your peer links open with a persistent '
      'notification while the app is in the background. Costs battery, and '
      'the OS can still close the app under memory pressure — then '
      'everything in memory is wiped as usual.',
  'settings.language': 'Language',
  'settings.langSystem': 'System',
  'settings.langKorean': '한국어',
  'settings.langEnglish': 'English',
  'settings.eraseSaved': 'Erase saved data',
  'settings.eraseTitle': 'Erase saved data?',
  'settings.eraseBody':
      'Deletes the vault file from this device and turns saving off. '
      'Messages currently in RAM are not affected.',
  'settings.erase': 'Erase',
  'settings.savedChats': 'Saved chats',
  'settings.savedChatsSub': 'Browse and delete what\'s in the saved file',
  'savedChats.title': 'Saved Chats',
  'savedChats.emptyTitle': 'Nothing saved yet',
  'savedChats.emptyBody':
      "Chats you choose to keep when leaving them show up here.",
  'savedChats.delete': 'Delete',
  'savedChats.deleteTitle': 'Delete this saved chat?',
  'savedChats.deleteBody':
      "Removes {name} and its messages from the saved file. This can't be "
      'undone.',
  'wifiInfo.title': 'Wi-Fi Network',
  'wifiInfo.ssid': 'Network',
  'wifiInfo.ssidHidden': 'Hidden by macOS (needs Location access)',
  'wifiInfo.channel': 'Channel',
  'wifiInfo.phyMode': 'Mode',
  'wifiInfo.linkRate': 'Link rate',
  'wifiInfo.signal': 'Signal',
  'wifiInfo.security': 'Security',
  'wifiInfo.unavailable': "Couldn't read network details on this device.",
  'wifiInfo.unavailableMobile':
      'Reading Wi-Fi details on iOS/Android needs a location permission, '
      "which this app doesn't request by design (it never uses your "
      'location for anything). Your own IP is shown above instead — '
      'compare its first few numbers with a nearby device to check '
      "you're on the same network.",

  'settings.stayConnectedStopped':
      'Android stopped or did not allow the background connection, so this '
      'was turned off. Turn it on again to retry.',
  'settings.onlyChatsIStart': 'Only chats I start',
  'settings.onlyChatsIStartSub':
      "Devices you haven't chatted with since Intragram started can't open "
      'a chat with you or invite you to a room. You can still connect to '
      'them, and browser guests still join your portal.',
};
