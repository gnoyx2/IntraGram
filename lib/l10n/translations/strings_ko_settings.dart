// 설정 화면
const Map<String, String> kStringsKoSettings = {
  'settings.title': '설정',
  'settings.sectionPrivacy': '개인정보',
  'settings.sectionApp': '앱',
  'settings.sectionConnection': '연결',
  'settings.autoLock': '백그라운드 자동 잠금',
  'settings.autoLockMinutes': '{n}분 후',
  'settings.textSize': '글자 크기',
  'settings.licenses': '오픈소스 라이선스',
  'settings.textSizeKeys': '단축키: {keys}',
  'settings.keepChats': '이 기기에 대화 보관',
  'settings.keepChatsSub':
      '기본은 꺼져 있어요. 모든 게 메모리에만 있다가 앱을 닫으면 사라져요. 켜면 '
      '아래 범위를 이 앱 폴더의 파일에 저장해요. 상대가 지운 메시지는 여기서도 '
      '사라지고, 긴급 소거는 그 파일까지 전부 지워요. 켜두면 재시작 후에도 '
      '예전 메시지를 검색할 수 있어요. 대화 하나만 빼려면 그 대화 메뉴에서 '
      '\'이 기기에 보관\'을 꺼 주세요.',
  'settings.messages': '메시지',
  'settings.messagesSub': '텍스트 메시지와 대화 목록',
  'settings.fileHistory': '파일 전송 기록',
  'settings.fileHistorySub': '완료된 전송 기록이에요. 파일 자체는 이미 저장한 위치에 있어요.',
  'settings.pinProtect': '보관소 PIN 보호',
  'settings.pinProtectOnSub': '켜져 있어서 PIN 없이는 파일을 읽을 수 없어요. 실행할 때 물어볼게요.',
  'settings.pinProtectOffSub':
      '꺼져 있어서 이 기기의 파일을 읽을 수 있는 프로그램이면 뭐든 저장된 대화를 '
      '볼 수 있어요.',
  'settings.set': '설정',
  'settings.restoredNote':
      '복원된 대화는 읽기 전용 아카이브예요. 고정된 피어 신원이 없어서 같은 '
      '사람이 다시 연결하면 새 대화가 열려요.',
  'settings.largeMessages': '긴 메시지',
  'settings.largeMessagesSub':
      '길게 입력하거나 붙여넣은 메시지를 어떻게 보낼지예요. 저장이 꺼져 있어도 '
      '동작해요 (재시작하면 초기화돼요).',
  'settings.large.inline': '메모리에',
  'settings.large.unlimited': '무제한',
  'settings.large.file': '파일로',
  'settings.large.inlineDesc':
      '기본이에요. 약 1 MB(책 한 권 분량)까지 다른 메시지처럼 메모리에 실려요. '
      '그보다 크면 차단돼요.',
  'settings.large.unlimitedDesc':
      '크기 제한이 없어요. 피어가 아주 큰 메시지를 이 기기 메모리에 바로 밀어 넣을 '
      '수 있으니 신뢰하는 네트워크에서만 쓰세요.',
  'settings.large.fileDesc':
      '64 KB가 넘는 메시지는 저장·열람하는 "Long message.txt" 파일로 전송돼요. '
      '메모리를 작게 유지해요.',
  'settings.iosForegroundOnly':
      'iPhone·iPad에서는 IntraGram을 열어 둔 동안만 연결돼요. 앱을 나가면 iOS가 '
      '몇 초 뒤 앱을 멈추고, 다시 열면 상대가 다시 연결할 수 있어요.',
  'settings.stayConnected': '백그라운드에서 연결 유지',
  'settings.stayConnectedSub':
      'Android 전용이에요. 앱이 백그라운드에 있는 동안 지속 알림과 함께 피어 '
      '링크를 열어 둬요. 배터리를 더 쓰고, 메모리가 모자라면 OS가 앱을 닫을 수 있어요. '
      '그러면 메모리의 모든 게 평소처럼 지워져요.',
  'settings.language': '언어',
  'settings.langSystem': '시스템',
  'settings.langKorean': '한국어',
  'settings.langEnglish': 'English',
  'settings.eraseSaved': '저장 데이터 삭제',
  'settings.eraseTitle': '저장 데이터를 삭제할까요?',
  'settings.eraseBody':
      '이 기기에서 보관소 파일을 지우고 저장을 꺼요. 지금 메모리에 있는 메시지는 '
      '영향받지 않아요.',
  'settings.erase': '삭제',
  'settings.savedChats': '저장된 대화',
  'settings.savedChatsSub': '보관소에 든 대화를 보고 지우기',
};
