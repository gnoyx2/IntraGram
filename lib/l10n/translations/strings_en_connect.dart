// 연결·신원 확인 흐름(기기 코드, SAS 불일치, 권한·네트워크 안내) 문구
const Map<String, String> kStringsEnConnect = {
  'deviceCode.tooltip': 'Show my device code',
  'deviceCode.title': 'My device code',
  'deviceCode.body':
      'On another device on the same Wi-Fi, open IntraGram and tap Scan. '
      'The code also carries this device\'s identity, so the connection '
      'only completes with this device.',
  'deviceCode.unavailable':
      'The code needs a private Wi-Fi address (192.168.x.x, 10.x.x.x or '
      '172.16–31.x.x). Join a Wi-Fi network or turn on a hotspot.',
  'connect.noAnswer':
      'No answer from that address. Check the address and port, that '
      'IntraGram is open on the other device, and that this Wi-Fi lets '
      "devices reach each other (guest, office and school networks often "
      "don't — a phone hotspot works).",
  'connect.refused':
      'The device at that address refused the connection. Open IntraGram '
      'there, check the port on its identity card, and let IntraGram '
      'through its firewall on private networks.',
  'connect.noRoute':
      "This device can't reach that address. Both devices need to be on "
      'the same Wi-Fi.',
  'connect.notIntraGram':
      "Something answered at that address, but it isn't IntraGram. Check "
      "the port on the other device's identity card.",
  'connect.notPrivate':
      'Only private Wi-Fi addresses can be dialled (192.168.x.x, 10.x.x.x '
      'or 172.16–31.x.x).',
  'connect.localNetworkCheck':
      'Also check that Local Network access is on for IntraGram.',
  'settings.open': 'Open Settings',
  'home.notPrivate': "Nearby devices can't be found on this network.",
  'server.noNetwork': 'No local network. Join a Wi-Fi or hotspot, then retry.',
  'server.notPrivateTitle': "This Wi-Fi can't be used for IntraGram",
  'server.notPrivate':
      'The network gave this device a public address ({address}), and '
      'IntraGram only talks over private Wi-Fi addresses. Turn on a phone '
      'hotspot and join it with both devices.',
  'server.failedTitle': 'The local server could not start',
  'server.failed': 'Retry, and restart the app if it keeps failing.',
  'discoveryHelp.title': "Can't find the other device?",
  'discoveryHelp.sameWifi':
      "Both devices are on the same Wi-Fi, and it isn't a guest network.",
  'discoveryHelp.appOpen': 'IntraGram is open on the other device.',
  'discoveryHelp.localNetwork':
      'Local Network access is on for IntraGram (iPhone, iPad and Mac ask '
      'for it once; it is in Settings).',
  'discoveryHelp.firewall':
      'This Wi-Fi is a Private network in Windows settings (a new network '
      'starts as Public), and Windows Firewall lets IntraGram in on private '
      'networks.',
  'discoveryHelp.hotspot':
      'Office, school and café Wi-Fi often keep devices apart. Turn on a '
      'phone hotspot and join it with both devices.',
  'discoveryHelp.byIp':
      'Still nothing? Use Connect by IP with the address shown on the other '
      "device's home screen, or scan its device code.",
  'scan.cameraDenied': 'Camera access is off for IntraGram.',
  'sas.mismatch': 'Codes differ',
  'sas.dontSendHere':
      "Don't send the code through this chat — say it out loud or show "
      'the screen.',
  'sas.mismatchTitle': "The codes don't match",
  'sys.sasMismatch':
      'The security codes did not match, so this connection was closed. '
      'Someone may have been relaying it — do not resend anything '
      'sensitive. Reconnect, ideally by scanning the other device\'s code.',
};
