const Map<String, String> kStringsEnCommon = {
  // 시스템 메시지 (네트워크 레이어의 SystemEvent를 여기서 렌더)
  'sys.disconnected': 'Disconnected.',
  'sys.protocolVersionMismatch':
      "Peer uses an incompatible app version — can't connect securely. "
      'Update Intragram on both devices.',
  'sys.peerMismatch':
      'A different device answered at this address, so this chat was not '
      'reconnected. Find the person again on the home screen and connect '
      'from there.',
  'sys.handshakeFailed':
      "The other device couldn't prove who it is, so the connection was "
      'closed. Try again, or connect by scanning its device code.',
  'sys.peerBlocked':
      "You blocked this device for this session. Device IDs change when "
      'Intragram restarts, so turn on Settings › Only chats I start to keep '
      'strangers out.',
  'sys.handshakeTimedOut':
      "The other device didn't finish the secure handshake in time. Check "
      'that Intragram is open there and try again.',
  'sys.reconnect': 'Reconnect',
  'sys.reconnecting': 'Reconnecting…',
  'sys.encrypted': 'Encrypted. Tap the shield to check the 6-digit code.',
  'sys.encryptedAgain':
      'Reconnected with a new 6-digit code. Tap the shield to check it again.',
  'sys.verifiedAgain':
      'Reconnected to the device you checked before. The 6-digit code '
      "changed, but you don't need to check it again.",
  'sys.joinedRoom':
      "You joined {alias}'s room. Files you send here transfer directly to "
      'other members.',
  'sys.becameRoom':
      'This conversation is now a room. Files sent here transfer directly '
      'between members.',
  'sys.memberJoined': '{alias} joined.',
  'sys.memberLeft': '{alias} left.',
  'sys.markedVerified': 'You confirmed the code matches. Waiting for peer.',
  'sys.mutuallyVerified': 'Both sides confirmed the code. Verified.',
  'sys.screenshotPeer': '{alias} took a screenshot.',
  'sys.screenshotMine': 'You took a screenshot.',

  // 공통
  'common.file': 'File',
  'common.you': 'You',
  'common.cancel': 'Cancel',
  'common.close': 'Close',
  'common.save': 'Save',
  'common.remove': 'Remove',
  'common.messageDeleted': 'Message deleted',
  'common.retry': 'Retry',
  'common.add': 'Add',
  'common.backToHome': 'Back to chats',
  'homeActions.connecting': 'Connecting…',
  'qr.whiteBackgroundNote': 'White background helps scanners read this.',

  // 빈 상태 / 에러 상태
  'error.showDetail': 'Show details',
  'error.hideDetail': 'Hide details',
  'error.messagesTitle': "Couldn't load messages",
  'error.messagesAction': 'Something went wrong loading this conversation.',
  'empty.messagesTitle': 'No messages yet',
  'empty.messagesBody': 'Say hello — it only stays on these two devices.',
  'empty.searchTitle': 'Search this chat',
  'empty.searchNoResultsTitle': 'No matches',
  'empty.searchNoResultsBody': 'Try a different word or phrase.',
  'empty.addPeopleTitle': 'No one else nearby',
  'empty.addPeopleBody': 'Devices on the same Wi-Fi will show up here.',
  'empty.endedTitle': 'This conversation ended',
  'empty.endedBody': "Nothing was kept — go back and start a new one.",
  'empty.roomMembersTitle': 'No one here yet',

  // 홈 화면
  'home.slogan': 'No cloud. No accounts. Just this Wi-Fi.',
  'home.activeChats': 'Active chats',
  'home.activeChatsCountOne': '{n} active chat',
  'home.activeChatsCountOther': '{n} active chats',
  'home.noChats': 'No conversations. Tap a device below to start one.',
  'home.noChatOpenTitle': 'No chat open',
  'home.noChatOpenBody':
      'Pick a conversation or a device on this network from the list.',
  'home.lookingForDevices':
      'Looking for Intragram on this Wi-Fi…\n'
      'Open the app on another device on the same network.',
  'home.localNetworkWhy':
      'If asked, allow Local Network: Intragram uses it only to find and '
      'reach devices on this Wi-Fi.',
  'home.noDevicesFound':
      "No other Intragram found on this Wi-Fi yet.\n"
      "Connect by IP if you know the other device's address.",
  'home.noWifi': 'No Wi-Fi connection. Join a network to find nearby devices.',
  'home.discoveryError': 'Device search stopped unexpectedly. Try refreshing.',
  'home.discoveryErrorLinux':
      'Device search stopped. On Linux it needs avahi-daemon running '
      '(for example: sudo systemctl enable --now avahi-daemon). Connect by IP '
      'still works.',
  'home.onThisNetworkFoundOne': 'On this network — {n} device found',
  'home.onThisNetworkFoundOther': 'On this network — {n} devices found',
  'home.refreshDevices': 'Refresh',
  'home.refreshingIn': 'Refreshing in {seconds}s',
  'home.searchMessages': 'Search messages',
  'home.connectByIp': 'Connect by IP',
  'home.scanDevice': 'Scan a device code',
  'home.guestPortal': 'Guest portal',
  'home.settings': 'Settings',
  'home.panicWipe': 'Panic wipe',
  'home.serverErrorHint': 'Join Wi-Fi to chat with nearby devices.',

  // OS 알림은 항상 이 문구만. 실제 발신자/내용은 안 실음
  // (잠금 화면/알림창에 그대로 뜨는 데이터라 미리보기 자체가 유출)
  'notifications.newMessage': 'New message',
  'notifications.channel': 'Messages',
  'notifications.channelDesc':
      'A device sent you a message while the app was in the background',
};
