const Map<String, String> kStringsKoChat = {
  'chat.keepOnDevice': '이 기기에 보관',
  'voice.couldNotStartLinux':
      '녹음을 시작하지 못했어요. Linux에서는 마이크를 켜고 PipeWire 도구(pw-record/pw-cat) '
      '또는 PulseAudio 도구(parecord)를 설치하세요.',
  'picker.unavailable':
      '파일 대화상자를 열지 못했어요. Linux는 xdg-desktop-portal과 백엔드'
      '(xdg-desktop-portal-gtk 등)를 설치하세요.',
  'chat.endBody': '연결을 끊고 이 대화를 이 기기에서 삭제해요.',
  'chat.endButton': '종료',
  'chat.sendFilesTitle': '파일 보내기',

  'attach.photoLibrary': '사진첩',
  'attach.file': '파일',
  'attach.failed': '선택한 항목을 불러오지 못했어요. 사진을 더 적게 또는 작은 걸로 골라 주세요',

  'viewer.close': '닫기',
  'viewer.share': '공유',

  'transfer.fileGone': '파일을 더 이상 쓸 수 없음',
  'transfer.voiceLabel': '음성 메시지',
  'transfer.batchLine': '파일 {label}  ·  {size}',
  'transfer.accept': '수락',
  'transfer.decline': '거절',
  'transfer.cancel': '취소',
  'transfer.retry': '재시도',
  'transfer.play': '재생',
  'transfer.pause': '일시정지',
  'transfer.etaSeconds': '{s}초 남음',
  'transfer.etaMinutes': '{m}분 {s}초 남음',
  'transfer.etaHours': '{h}시간 {m}분 남음',
  'transfer.bytesLeft': '{size} 남음',
  'transfer.acceptAll': '전부 수락 ({n})',
  'transfer.declineAll': '전부 거절',
  'transfer.waitingForPeer': '상대 기다리는 중…',
  'transfer.savedTo': '{path}에 저장됨',
  'transfer.saveToDevice': '기기에 저장',
  'transfer.saveFailed': '저장 실패',
  'transfer.disk': '디스크',
  'transfer.sent': '보냄',
  'transfer.declined': '거절됨',
  'transfer.cancelled': '취소됨',
  'transfer.failed': '실패: {error}',
  'transfer.unknownError': '알 수 없는 오류',
  'transfer.errorNetwork': '연결이 끊겼어요. 다시 연결된 뒤 재시도하면 처음부터 다시 시작해요.',
  'transfer.errorRejected': '상대가 전송을 거절함',
  'transfer.errorTampered': '받은 파일이 보낸 것과 달라서 지웠어요. 다시 시도하세요',
  'transfer.errorCancelled': '전송이 취소됨',
  'transfer.errorDiskFull': '{size}를 받을 공간이 부족해요. 공간을 비운 뒤 다시 시도하세요',
  'transfer.errorDiskFullDesktop':
      '그 폴더에 {size}를 받을 공간이 부족해요. 다시 시도하면 다른 폴더를 고를 수 있어요',
  'transfer.couldNotOpen': '파일을 열 수 없어요',
  'transfer.shareSave': '공유·저장',
  'transfer.open': '열기',
  'transfer.showInFolder': '폴더에서 보기',
  'transfer.execWarnTitle': '이 프로그램을 실행할까요?',
  'transfer.execWarnBody': '이 파일은 컴퓨터에서 코드를 실행할 수 있어요. 보낸 사람을 믿을 때만 여세요.',
  'transfer.openAnyway': '그래도 열기',
  'transfer.netWarnTitle': '이 파일은 인터넷에 접속할 수 있어요',
  'transfer.netWarnBody':
      '다른 앱으로 열면 이 네트워크 밖의 페이지를 불러오거나 주소에 접속해서, 내 공인 주소와 '
      '파일을 열었다는 사실이 드러날 수 있어요. 보낸 사람을 믿을 때만 여세요.',
  'transfer.cannotPlay': '이 음성 메시지를 재생할 수 없어요',
  'transfer.voiceSent': '음성 메시지 보냄',
  'transfer.voiceGone': '음성 메시지를 더 이상 쓸 수 없음',
  'transfer.voiceFailed': '음성 메시지 실패',
  'transfer.voiceCancelled': '음성 메시지 취소됨',
  'transfer.voiceReceiving': '음성 메시지 받는 중…',

  'voice.micPermission': 'IntraGram의 마이크 접근이 꺼져 있어요. 음성 메시지를 녹음하려면 설정에서 켜 주세요.',
  'voice.couldNotStart': '녹음을 시작하지 못했어요. 다시 시도해 주세요.',
  'voice.stopFailed': '녹음을 저장하지 못했어요.',
  'voice.tooLong': '음성 메시지가 너무 길어요',
  'voice.tooShort': '더 길게 눌러야 음성 메시지가 녹음돼요',
  'voice.tapToCancel': '탭해서 취소',
  'voice.holdToRecord': '탭하면 녹음 시작, 길게 누르면 누르는 동안 녹음',
  'voice.a11yRecording': '녹음 중. 두 번 탭하면 전송돼요.',

  'drop.hint': '여기에 파일을 놓으면 전송',

  'addPeople.title': '방에 사람 추가',
  'addPeople.body':
      '방의 메시지는 내 기기를 거쳐서 여기 오가는 메시지는 모두 내 기기에서 '
      '읽을 수 있어요. 파일은 1:1로만 가요.',
  'addPeople.add': '{n}명 추가',

  'sas.title': '보안 코드',
  'sas.body':
      '이 숫자는 공유 키에서 나와요. {peer}님과 소리 내어 읽어 맞춰 보거나 '
      '상대 코드를 스캔하세요. 여섯 자리가 같으면 중간에 낀 사람이 없다는 뜻이에요.',
  'sas.pendingNote': '내 쪽은 이미 확인했어요. 상대도 확인해야 검증이 끝나요.',
  'sas.scan': '상대 코드 스캔',
  'sas.notNow': '나중에',
  'sas.theyMatch': '일치함',

  'sasScan.title': '상대 코드 스캔',
  'sasScan.hint': '상대 기기의 코드 QR을 비추세요.',
  'sasScan.noCamera': '스캔하려면 카메라가 필요해요. 대신 여섯 자리를 소리 내어 읽으세요.',

  'identity.visibleOn': '{host}:{port}에서 보임',
  'identity.serverOffline': '서버 오프라인',
  'identity.renameTitle': '기기 이름',
  'identity.renameHint': '예: blue-otter-38',
  'identity.renameConfirm': '이름 바꾸기',
  'identity.saveToggle': '다음에 앱 실행할 때도 이 이름 사용',

  'convTile.verifiedOnline': '검증됨 · 온라인',
  'convTile.encryptedOnline': '암호화됨 (미검증) · 온라인',
  'convTile.platformOnline': '{platform} · 온라인',
  'convTile.webGuestRoom': '브라우저 게스트 · LAN에서 평문',
  'convTile.roomOnline': '호스트 중계 · {people} · 온라인',
  'convTile.roomVerified': '그룹 방, 모든 멤버 코드 확인함',
  'convTile.roomUnverified': '그룹 방, 확인 안 한 멤버 코드 있음',

  'peerTile.hostingRoom': '방 호스팅 중',
  'peerTile.inRoom': '방 참여 중',

  'homeActions.sendClipText': '클립보드 텍스트 보내기',
  'homeActions.addToRoom': '내 방에 추가',
  'homeActions.addToRoomSub': '그룹을 시작하거나 키워요. 메시지는 내 기기에서 읽혀요',
  'homeActions.wipeTitle': '지금 전부 지울까요?',
  'homeActions.wipeBody':
      '앱에서 모든 메시지·파일 기록·키를 지우고, (저장을 켰다면) 보관소 파일이 '
      '지워지고, 모든 피어와 연결이 끊겨요. 되돌릴 수 없어요.',
  'homeActions.wipeReceivedFiles': '이번에 받은 파일도 함께 삭제',
  'homeActions.wipe': '지우기',
  'homeActions.memoryWiped': '메모리를 지웠어요.',
  'homeActions.memoryWipedPartial':
      '메모리는 지웠지만 일부 백그라운드 작업이 제때 멈추지 않았어요. '
      '확실히 하려면 앱을 다시 시작하세요.',
  'homeActions.couldNotConnect': '연결할 수 없어요. 같은 Wi-Fi에 있는지 확인해 주세요.',
  'pin.tooShort': '영문 또는 숫자 6자 이상 쓰세요',
  'pin.mismatch': 'PIN이 일치하지 않아요',
  'pin.mustDiffer': '보관소 PIN과 협박 대비 PIN은 달라야 해요',
  'pin.setTitle': '보관소 PIN 설정',
  'pin.changeTitle': '보관소 PIN 변경',
  'pin.duressTitle': '협박 대비 PIN 설정',
  'pin.body':
      '짧은 PIN은 엔트로피가 낮아요. 파일을 복사한 사람을 늦출 뿐, 해독 '
      '불가능하게 만들지는 않아요.',
  'pin.duressBody':
      '빈 세션을 열어요. 그 안에서 한 일은 저장되지 않아요. 누군가 잠금 해제를 '
      '강요할 때 쓰세요.',
  'pin.pinLabel': 'PIN',
  'pin.confirmLabel': 'PIN 확인',
  'pin.removePin': 'PIN 제거',

  'pinGate.title': '잠긴 보관소',
  'pinGate.body': 'PIN을 입력하면 저장된 이력을 복원해요. 이 기기를 벗어나지 않아요.',
  'pinGate.wrong': '틀린 PIN',
  'pinGate.readError': '보관소 파일을 읽지 못했어요. 원본은 그대로 유지돼요.',
  'pinGate.unlock': '잠금 해제',
  'pinGate.startFresh': '새로 시작 (잠긴 파일은 유지)',

  'portal.body':
      '앱이 없나요? 아무 카메라로 이걸 스캔하면 브라우저에서 대화할 수 있어요. '
      '로컬 Wi-Fi만 쓰고 모바일 데이터나 인터넷은 안 써요. 브라우저 대화는 '
      'Wi-Fi에서 암호화되지 않아요. 종단 간 암호화는 앱끼리 1:1 대화뿐이에요.',
  'portal.copyUrl': '포털 URL 복사',
  'portal.urlCopied': '포털 URL 복사됨',
  'portal.serverOff': '로컬 서버가 꺼져 있어요.',
  'portal.localServer': '로컬 웹 서버',
  'portal.servingOn': '{host}:{port}에서 제공 중',
  'portal.offNoGuests': '꺼져 있어서 게스트가 들어올 수 없어요',
  'portal.webGuests': '브라우저 게스트 허용',
  'portal.webGuestsSub': '기본은 꺼짐. 게스트는 브라우저로 들어오고, 보내는 내용은 Wi-Fi에서 암호화되지 않아요.',
  'portal.scanAnother': '다른 기기 코드 스캔',

  'scanScreen.hint':
      '다른 기기의 게스트 포털 QR을 비추세요.\n'
      '로컬 Wi-Fi 주소만 읽고, 로컬이 아닌 코드는 무시해요.',
  'scanScreen.noCamera': '스캔하려면 카메라가 필요해요. 대신 \'IP로 연결\'을 쓰세요.',

  'manualConnect.body': '기기가 자동으로 안 보일 때 쓰세요.',
  'manualConnect.notIpv4': '리터럴 IPv4 주소를 입력하세요 (예: 192.168.0.12)',
  'manualConnect.notPrivate':
      '입력한 주소({host})는 로컬 네트워크 주소가 아니에요. 같은 Wi-Fi에 있는 기기하고만 연결할 수 있어요.',
  'manualConnect.badPort': '1에서 65535 사이 포트를 입력하세요',
  'manualConnect.peerIpLabel': '피어 IP',
  'manualConnect.portLabel': '포트',
  'manualConnect.connect': '연결',

  'search.conversation': '대화',
  'search.emptyVaultOn': '이번 세션과 저장된 이력의 메시지를 검색해요.',
  'search.emptyVaultOff':
      '이번 세션 메시지만 검색해요. 재시작 후에도 예전 메시지를 검색하려면 '
      '설정에서 저장을 켜세요.',
  'link.openTitle': '브라우저에서 이 링크를 열까요?',
  'link.lookalike':
      '주소에 다른 문자 체계의 글자가 섞여 있어 아는 사이트를 흉내 낸 것일 수 있어요. '
      '브라우저에는 위처럼 보여요.',
  'link.open': '열기',
};
