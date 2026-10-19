const Map<String, String> kStringsEnChat = {
  // 대화 종료 / 대화별 보관
  'chat.keepOnDevice': 'Keep on this device',
  'chat.endBody': 'Disconnect and remove this conversation from this device.',
  'chat.endButton': 'End',
  'chat.sendFilesTitle': 'Send files',

  'attach.photoLibrary': 'Photo Library',
  'attach.file': 'File',
  'attach.failed': "Couldn't load the selection. Try fewer or smaller photos.",

  'viewer.close': 'Close',
  'viewer.share': 'Share',

  // 파일 전송 타일
  'transfer.fileGone': 'File no longer available',
  'transfer.voiceLabel': 'Voice message',
  'transfer.batchLine': 'file {label}  ·  {size}',
  'transfer.accept': 'Accept',
  'transfer.decline': 'Decline',
  'transfer.cancel': 'Cancel',
  'transfer.retry': 'Retry',
  'transfer.play': 'Play',
  'transfer.pause': 'Pause',
  'transfer.etaSeconds': '{s}s left',
  'transfer.etaMinutes': '{m}m {s}s left',
  'transfer.etaHours': '{h}h {m}m left',
  'transfer.bytesLeft': '{size} left',
  'transfer.acceptAll': 'Accept all ({n})',
  'transfer.declineAll': 'Decline all',
  'transfer.waitingForPeer': 'Waiting for peer…',
  'transfer.savedTo': 'Saved to {path}',
  'transfer.saveToDevice': 'Save to device',
  'transfer.saveFailed': 'Save failed',
  'transfer.disk': 'disk',
  'transfer.sent': 'Sent',
  'transfer.declined': 'Declined',
  'transfer.cancelled': 'Cancelled',
  'transfer.failed': 'Failed: {error}',
  'transfer.unknownError': 'unknown error',
  'transfer.errorNetwork':
      "the connection dropped. Once you're reconnected, Retry starts over from the beginning.",
  'transfer.errorRejected': 'Peer refused the transfer',
  'transfer.errorTampered':
      "the file that arrived didn't match what was sent, so it was deleted — retry",
  'transfer.errorCancelled': 'Transfer was cancelled',
  'transfer.errorInsecureLink':
      "Link isn't encrypted yet — wait for the shield, then retry",
  'transfer.errorDiskFull':
      'not enough free space for {size} — free some up, then retry',
  'transfer.errorDiskFullDesktop':
      'not enough free space in that folder for {size} — retry to pick '
      'another folder',
  'transfer.couldNotOpen': 'Could not open the file',
  'transfer.shareSave': 'Share or save',
  'transfer.open': 'Open',
  'transfer.showInFolder': 'Show in folder',
  'transfer.execWarnTitle': 'Run this program?',
  'transfer.execWarnBody':
      'This file can run code on your computer. Only open it if you trust the sender.',
  'transfer.openAnyway': 'Open anyway',
  'transfer.netWarnTitle': 'This file can reach the internet',
  'transfer.netWarnBody':
      'Opening it in another app can load pages or connect to addresses '
      'outside this network, which shows your public address and that you '
      'opened it. Open it only if you trust the sender.',
  'transfer.cannotPlay': 'Cannot play this voice message',
  'transfer.voiceSent': 'Voice message sent',
  'transfer.voiceGone': 'Voice message no longer available',
  'transfer.voiceFailed': 'Voice message failed',
  'transfer.voiceCancelled': 'Voice message cancelled',
  'transfer.voiceReceiving': 'Receiving voice message…',

  // 음성 녹음
  'voice.micPermission':
      'Microphone access is off for IntraGram. Turn it on in Settings to '
      'record voice messages.',
  'voice.couldNotStart': 'Could not start recording. Try again.',
  'voice.couldNotStartLinux':
      'Could not start recording. On Linux, voice messages need parecord from '
      'pulseaudio-utils (and pipewire-pulse on PipeWire systems).',
  'picker.unavailable':
      "Couldn't open the file dialog. On Linux, install xdg-desktop-portal "
      'and a backend such as xdg-desktop-portal-gtk.',
  'voice.stopFailed': 'Could not save the recording.',
  'voice.tooLong': 'Voice message is too long',
  'voice.tooShort': 'Hold longer to record a voice message',
  'voice.tapToCancel': 'Tap to cancel',
  'voice.holdToRecord':
      'Tap to record hands-free, or hold to record while pressed',
  'voice.a11yRecording': 'Recording. Double tap to send.',

  // 파일 드롭 오버레이
  'drop.hint': 'Drop files here to send',

  // 사람 추가 시트
  'addPeople.title': 'Add people to a room',
  'addPeople.body':
      'Messages in a room pass through your device — everyone here can be '
      'read from it. Files stay one-to-one.',
  'addPeople.add': 'Add {n}',

  // 보안 코드 다이얼로그
  'sas.title': 'Security code',
  'sas.body':
      'This number is derived from the shared key. Compare it with {peer} — '
      'read it out, or scan their code. If the six digits match, no one is '
      'sitting in the middle.',
  'sas.pendingNote':
      "You've already confirmed your side — verification finishes once your "
      'peer confirms too.',
  'sas.scan': 'Scan their code',
  'sas.notNow': 'Not now',
  'sas.theyMatch': 'They match',

  // 코드 스캔 화면
  'sasScan.title': "Scan their code",
  'sasScan.hint': "Point at the other device's code QR.",
  'sasScan.noCamera':
      'Scanning needs a camera. Read the six digits aloud instead.',

  // 홈 신원 카드
  'identity.visibleOn': 'Visible on {host}:{port}',
  'identity.serverOffline': 'Server offline',
  'identity.renameTitle': 'Device name',
  'identity.renameHint': 'e.g. blue-otter-38',
  'identity.renameConfirm': 'Rename',
  'identity.saveToggle': 'Use this name next time too',

  // 대화 타일
  'convTile.verifiedOnline': 'verified · online',
  'convTile.encryptedOnline': 'encrypted (unverified) · online',
  'convTile.platformOnline': '{platform} · online',
  'convTile.webGuestRoom': 'browser guests · plaintext on the LAN',
  'convTile.roomOnline': 'host relay · {people} · online',
  'convTile.roomVerified': 'Group room, every member code checked',
  'convTile.roomUnverified': 'Group room, some member codes not checked',

  // 피어 타일
  'peerTile.hostingRoom': 'hosting a room',
  'peerTile.inRoom': 'in a room',

  // 홈 액션
  'homeActions.sendClipText': 'Send clipboard text',
  'homeActions.addToRoom': 'Add to my room',
  'homeActions.addToRoomSub':
      'Start or grow a group — messages are readable on your device',
  'homeActions.wipeTitle': 'Wipe everything now?',
  'homeActions.wipeBody':
      'Every message, file record and key is cleared from the app, the '
      'on-disk vault (if you turned saving on) is erased, and all peers are '
      'disconnected. This cannot be undone.',
  'homeActions.wipeReceivedFiles': 'Also delete files received this session',
  'homeActions.wipe': 'Wipe',
  'homeActions.memoryWiped': 'Memory wiped.',
  'homeActions.memoryWipedPartial':
      'Memory wiped, but some background work did not stop in time. '
      'Restart the app to be sure.',
  'homeActions.couldNotConnect':
      "Couldn't connect. Check you're on the same Wi-Fi.",
  // vault PIN 다이얼로그
  'pin.tooShort': 'Use at least 6 letters or digits',
  'pin.mismatch': "PINs don't match",
  'pin.mustDiffer': 'Vault and duress PINs must differ',
  'pin.setTitle': 'Set a vault PIN',
  'pin.changeTitle': 'Change vault PIN',
  'pin.duressTitle': 'Set a duress PIN',
  'pin.body':
      'A short PIN is low-entropy. It slows down someone who copies the '
      'file, it does not make it uncrackable.',
  'pin.duressBody':
      'Opens an empty session. Nothing you do in it is saved. Use if someone '
      'forces you to unlock.',
  'pin.pinLabel': 'PIN',
  'pin.confirmLabel': 'Confirm PIN',
  'pin.removePin': 'Remove PIN',

  // PIN 시작 게이트
  'pinGate.title': 'Locked vault',
  'pinGate.body':
      'Enter the PIN to restore your saved history. It never leaves this '
      'device.',
  'pinGate.wrong': 'Wrong PIN',
  'pinGate.readError':
      'Vault file could not be read. The archive is unchanged.',
  'pinGate.unlock': 'Unlock',
  'pinGate.startFresh': 'Start fresh (keeps the locked file)',

  // 게스트 포털 시트
  'portal.body':
      'No app? Scan this with any camera to chat from the browser. It uses '
      'only the local Wi-Fi — no mobile data, no internet. Browser chats are '
      'not encrypted on the Wi-Fi; only app-to-app 1:1 chats are end-to-end '
      'encrypted.',
  'portal.copyUrl': 'Copy portal URL',
  'portal.urlCopied': 'Portal URL copied',
  'portal.serverOff': 'The local server is off.',
  'portal.localServer': 'Local web server',
  'portal.servingOn': 'Serving on {host}:{port}',
  'portal.offNoGuests': 'Off — guests cannot join',
  'portal.webGuests': 'Allow browser guests',
  'portal.webGuestsSub':
      'Off by default. Guests join from a browser, and what they send is not '
      'encrypted on the Wi-Fi.',
  'portal.scanAnother': "Scan another device's code",

  // 기기 코드 스캔
  'scanScreen.hint':
      "Point at another device's Guest portal QR.\n"
      'Local Wi-Fi addresses only — a non-local code is ignored.',
  'scanScreen.noCamera':
      'Scanning needs a camera. Use "Connect by IP" instead.',

  // IP 직접 연결
  'manualConnect.body': "Use this when a device doesn't show up automatically.",
  'manualConnect.notIpv4': 'Enter a literal IPv4 address (e.g. 192.168.0.12)',
  'manualConnect.notPrivate':
      "{host} isn't on your local network — IntraGram only connects to "
      'devices on the same Wi-Fi.',
  'manualConnect.badPort': 'Enter a port between 1 and 65535',
  'manualConnect.peerIpLabel': 'Peer IP',
  'manualConnect.portLabel': 'Port',
  'manualConnect.connect': 'Connect',

  // 메시지 검색
  'search.conversation': 'Conversation',
  'search.emptyVaultOn':
      'Searches messages from this session and your saved history.',
  'search.emptyVaultOff':
      "Searches this session's messages only. Turn on saving in Settings to "
      'keep older ones searchable after a restart.',
  'link.openTitle': 'Open this link in your browser?',
  'link.lookalike':
      'The address uses letters from another alphabet, so it may imitate a '
      'site you know. Your browser shows it as above.',
  'link.open': 'Open',
};
