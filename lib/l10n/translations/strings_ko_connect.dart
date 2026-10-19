// 연결·신원 확인 흐름(기기 코드, SAS 불일치, 권한·네트워크 안내) 문구
const Map<String, String> kStringsKoConnect = {
  'deviceCode.tooltip': '내 기기 코드 보기',
  'deviceCode.title': '내 기기 코드',
  'deviceCode.body':
      '같은 Wi-Fi의 다른 기기에서 IntraGram을 열고 스캔을 누르세요. 이 코드에는 '
      '이 기기의 신원도 들어 있어서 이 기기하고만 연결돼요.',
  'deviceCode.unavailable':
      '코드를 만들려면 사설 Wi-Fi 주소(192.168.x.x, 10.x.x.x, 172.16–31.x.x)가 '
      '필요해요. Wi-Fi에 연결하거나 핫스팟을 켜 주세요.',
  'connect.noAnswer':
      '그 주소에서 응답이 없어요. 주소와 포트, 상대 기기에 IntraGram이 켜져 '
      '있는지, 이 Wi-Fi가 기기끼리 연결을 허용하는지 확인하세요(게스트·회사·'
      '학교 Wi-Fi는 막는 경우가 많아요. 폰 핫스팟은 돼요).',
  'connect.refused':
      '그 주소의 기기가 연결을 거절했어요. 그 기기에서 IntraGram을 열고, 신원 '
      '카드의 포트를 확인하고, 방화벽에서 개인 네트워크 허용을 켜 주세요.',
  'connect.noRoute': '이 기기에서 그 주소로 갈 수 없어요. 두 기기가 같은 Wi-Fi에 있어야 해요.',
  'connect.notIntraGram':
      '그 주소에서 응답은 왔지만 IntraGram이 아니에요. 상대 기기 신원 카드의 '
      '포트를 확인하세요.',
  'connect.notPrivate':
      '같은 Wi-Fi의 사설 주소(192.168.x.x, 10.x.x.x, 172.16–31.x.x)만 연결할 수 있어요.',
  'connect.localNetworkCheck': 'IntraGram의 로컬 네트워크 접근이 켜져 있는지도 확인하세요.',
  'settings.open': '설정 열기',
  'home.notPrivate': '이 네트워크에서는 근처 기기를 찾을 수 없어요.',
  'server.noNetwork': '로컬 네트워크가 없어요. Wi-Fi나 핫스팟에 연결한 뒤 다시 시도하세요.',
  'server.notPrivateTitle': '이 Wi-Fi에서는 IntraGram을 쓸 수 없어요',
  'server.notPrivate':
      '이 네트워크가 기기에 공인 주소({address})를 줬어요. IntraGram은 사설 Wi-Fi '
      '주소로만 통신해요. 폰 핫스팟을 켜고 두 기기를 거기에 연결하세요.',
  'server.failedTitle': '로컬 서버를 시작하지 못했어요',
  'server.failed': '다시 시도해 보고, 계속 안 되면 앱을 다시 시작하세요.',
  'discoveryHelp.title': '상대 기기가 안 보이나요?',
  'discoveryHelp.sameWifi': '두 기기가 같은 Wi-Fi에 있고, 게스트 네트워크가 아니에요.',
  'discoveryHelp.appOpen': '상대 기기에서 IntraGram이 열려 있어요.',
  'discoveryHelp.localNetwork':
      'IntraGram의 로컬 네트워크 접근이 켜져 있어요(iPhone·iPad·Mac은 처음에 한 번 '
      '묻고, 설정에서 바꿀 수 있어요).',
  'discoveryHelp.firewall':
      'Windows 설정에서 이 Wi-Fi가 개인 네트워크이고(새 네트워크는 공용으로 시작), '
      'Windows 방화벽이 개인 네트워크에서 IntraGram을 허용해요.',
  'discoveryHelp.hotspot':
      '회사·학교·카페 Wi-Fi는 기기끼리 연결을 막는 경우가 많아요. 폰 핫스팟을 켜고 '
      '두 기기를 거기에 연결하세요.',
  'discoveryHelp.byIp':
      '그래도 안 되면 상대 기기 홈 화면에 보이는 주소로 "IP로 연결"을 쓰거나 기기 '
      '코드를 스캔하세요.',
  'scan.cameraDenied': 'IntraGram의 카메라 접근이 꺼져 있어요.',
  'sas.mismatch': '숫자가 달라요',
  'sas.dontSendHere': '이 채팅으로 코드를 보내지 마세요. 소리 내어 읽거나 화면을 보여 주세요.',
  'sas.mismatchTitle': '코드가 달라요',
  'sys.sasMismatch':
      '보안 코드가 달라서 연결을 끊었어요. 누군가 중간에서 가로챘을 수 있으니 '
      '민감한 내용은 다시 보내지 마세요. 다시 연결할 때는 상대 기기 코드를 '
      '스캔하는 게 가장 안전해요.',

  'a11y.newFile': '파일을 보냄',
  'home.localNetworkWhy':
      "'로컬 네트워크' 허용을 물으면 허용해 주세요. 이 Wi-Fi의 기기를 찾고 연결하는 데만 써요.",
  'a11y.burnMinute': '{n}분 후 사라짐',
  'a11y.burnMinutes': '{n}분 후 사라짐',
  'a11y.burnHour': '{n}시간 후 사라짐',
  'a11y.burnHours': '{n}시간 후 사라짐',
  'chat.room': '방',
  'chat.roomPeople': '방 · {n}명',
  // 기기 차단·모르는 기기 거절 (strings_ko_core.dart는 줄 상한이라 여기 둠)
  'sys.peerBlocked':
      '이번 실행 동안 이 기기를 차단했어요. 기기 ID는 IntraGram을 다시 켤 때마다 바뀌니 '
      '모르는 기기를 계속 막으려면 설정 › 내가 연 대화만 받기를 켜세요.',
  'chat.block': '이 기기 차단',
  'chat.unblock': '차단 해제',
  'chat.blockTitle': '{alias} 기기를 차단할까요?',
  'chat.blockBody':
      '이 대화가 닫히고, 둘 중 한쪽이 IntraGram을 다시 켜기 전까지 이 기기는 대화를 열거나 '
      '방에 초대할 수 없어요. 기기 ID가 실행마다 바뀌기 때문이에요. 지금까지의 대화는 계속 볼 수 있어요.',
  'chat.blockedBanner': '차단한 기기예요',
  'settings.stayConnectedStopped':
      'Android가 백그라운드 연결을 멈추거나 허용하지 않아서 꺼졌어요. 다시 켜면 다시 시도해요.',
  'settings.onlyChatsIStart': '내가 연 대화만 받기',
  'settings.onlyChatsIStartSub':
      'IntraGram을 켠 뒤 대화한 적 없는 기기는 대화를 열거나 방에 초대할 수 없어요. '
      '내가 먼저 연결하는 건 그대로 되고, 브라우저 게스트도 포털로 들어올 수 있어요.',
};
