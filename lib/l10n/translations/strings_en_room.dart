const Map<String, String> kStringsEnRoom = {
  // 메시지 버블 / 액션
  'msg.retry': 'Retry send',
  'msg.reply': 'Reply',
  'msg.copy': 'Copy text',
  'msg.deleteForMe': 'Delete for me',
  'msg.deleteForEveryone': 'Delete for everyone',
  'msg.deleteForEveryoneSub': 'Removes it from both devices',
  'msg.pickEmojiHint': 'Pick an emoji',

  // 검색 (대화 내)
  'search.inChat': 'Search in chat',
  'search.previousHit': 'Previous match',
  'search.nextHit': 'Next match',
  'search.close': 'Close search',

  // 메시지 목록
  'msglist.newMessages': 'New messages',
  'date.today': 'Today',
  'date.yesterday': 'Yesterday',
  'date.monthDay': '{month} {day}',
  'date.monthDayYear': '{month} {day}, {year}',

  // 채팅 앱바: 상태 줄
  'chat.status.youHost': 'you host · {people} · readable here',
  'chat.status.viaHost': 'via {who} · plaintext on their device',
  'chat.status.offline': 'offline',
  'chat.status.typing': 'typing…',
  'chat.status.webGuestRoom':
      'you host · {people} · browser guests are plaintext on the LAN',
  'chat.status.verified': 'verified · end-to-end encrypted',
  'chat.status.encrypted': 'encrypted · code not checked',
  'chat.status.pending': 'waiting for peer to confirm the code',
  'chat.status.connecting': 'connecting…',
  'chat.withCount': '{who} · {people}',
  'chat.person': '{n} person',
  'chat.people': '{n} people',
  // 채팅 앱바: 버튼 / 메뉴
  'chat.roomMembersTitle': 'Room members',
  'chat.sasVerified': 'Security code verified',
  'chat.sasCheck': 'Check security code',
  'chat.sasPending': 'Waiting for peer to confirm',
  'chat.unverifiedBanner':
      'Code not verified — tap to compare the 6-digit code with your peer.',
  'chat.unverifiedBannerPending':
      "Waiting for your peer to confirm — you've already confirmed your side.",
  'chat.relayBanner':
      'Host relay (hop-by-hop), not end-to-end: the host can read this room. '
      'Files and browser guests are not encrypted on the LAN.',
  'chat.roomEmptyBanner':
      'Everyone has left. Members can rejoin from their own devices.',
  'chat.burnTimer': 'Self-destruct timer',
  'chat.timerOff': 'Timer off',
  'chat.burnAfter': 'Burn after {n}s',
  'chat.burn24h': 'Timer on: unread messages burn after 24 h.',
  'chat.more': 'More',
  'chat.addPeople': 'Add people',
  'chat.autoAcceptFiles': 'Auto-accept files',
  'chat.endConversation': 'End conversation',

  // 입력창
  'input.hint': 'Message',
  'input.hintOffline': 'Peer offline',
  'input.send': 'Send',
  'input.sendFile': 'Send a file',
  'input.sendClipText': 'Send clipboard text',
  'input.sendClipImage': 'Send clipboard image',
  'input.sendClipFiles': 'Send clipboard files',
  'input.clipboardEmpty': 'Clipboard is empty',
  'input.noClipboardImage': 'No image on the clipboard',

  // 답장 미리보기 폴백
  'common.message': 'Message',

  'chat.room': 'Room',
  'chat.roomPeople': 'Room · {n} people',

  // 기기 차단 (이번 실행 동안)
  'chat.block': 'Block this device',
  'chat.unblock': 'Unblock',
  'chat.blockTitle': 'Block {alias}?',
  'chat.blockBody':
      "This chat closes, and the device can't open a chat with you or "
      'invite you to a room until one of you restarts Intragram, because '
      'device IDs change at each launch. You can still read this chat.',
  'chat.blockedBanner': 'You blocked this device',
};
