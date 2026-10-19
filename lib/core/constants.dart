// 디스크에 설정 저장소가 없어서 설정이 될 만한 값도 전부 컴파일타임 상수로 고정
library;

// 프레임 포맷이 깨지는 변경이면 올림. hello가 정확히 일치해야 통과하고 다르면 close
// v3 파일 프레임에 attempt(at) 필수 + file_retry / v4 그룹 멤버 목록 + 대상별 offer(to)
// v5 앱 hello에 신원 공개키(idk) 필수, peerId는 그 해시 / v6
// 호스트 전용 file_unavailable / v7 다이얼러 임시키 커밋-후-공개(hello cmt, auth pub)
// 앱과 웹 클라이언트를 같이 올려야 함
const String kProtocolVersion = '7';

const String kServiceType = '_intragram._tcp';

// 이미 물려 있으면 kPortScanRange만큼 앞으로 훑어 빈 포트를 찾음
const int kPreferredPort = 7890;

const int kPortScanRange = 40;

// 2 MiB: 기가비트 Wi-Fi를 채울 만큼 크고, 수 GB 파일이 통째로 RAM에 안 뜰 만큼 작음
const int kFileChunkBytes = 2 * 1024 * 1024;

// 넘으면 자동으로 멈추고 전송
const int kMaxVoiceNoteSeconds = 120;

// 16-bit/16kHz/모노 WAV 120초 = 120 * 16000
// * 2 + 44바이트(약 3.66 MiB)에 여유를 둠 넘는 클립은 버림
const int kMaxVoiceNoteBytes = 4 * 1024 * 1024;

// 모노 16-bit. 음성 대역엔 충분하고 120초 상한과 곱해도 kMaxVoiceNoteBytes 안에 듦
const int kVoiceSampleRate = 16000;

// native reader당 한 번에 pull하는 크기. 사진/문서 provider가 무제한 EventChannel
// 버퍼를 안 만들게 Dart가 이 단위로 끊어 당김
const int kMobileFileReadChunkBytes = 256 * 1024;

// 0은 타이머 없음 (세션 초기화 때까지 유지)
const List<int> kBurnTtlOptions = <int>[0, 5, 30, 60];

// 카운트다운은 상대가 읽어야 시작해서 안 열면 영원히 안 사라짐
// 보낸 지 이 시간이 지나면 읽음 여부와 무관하게 소각
const Duration kUnreadBurnCeiling = Duration(hours: 24);

const List<String> kQuickReactions = <String>[
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
];

// 자유 텍스트 입력 대신 탭 선택으로 제한. IME 조합 중 pop하다 크래시 나던 문제 차단
const List<String> kExtendedReactions = <String>[
  '😀',
  '😃',
  '😄',
  '😆',
  '🥹',
  '😂',
  '🤣',
  '😊',
  '😍',
  '🥰',
  '😘',
  '😋',
  '😜',
  '🤔',
  '🤫',
  '😴',
  '🥳',
  '🥺',
  '😭',
  '😱',
  '😡',
  '🤯',
  '🫠',
  '🤡',
  '👻',
  '💩',
  '👍',
  '👎',
  '👏',
  '🙌',
  '🤝',
  '✌️',
  '🤞',
  '🤟',
  '👊',
  '🙏',
  '🫡',
  '🫶',
  '👀',
  '🔥',
  '💯',
  '✨',
  '🎉',
  '🚀',
  '⚡️',
  '❤️',
  '🧡',
  '💛',
  '💚',
  '💙',
  '💜',
  '🖤',
  '🤍',
  '💔',
  '❤️‍🔥',
  '☕️',
  '🍻',
  '🍕',
  '👑',
  '💡',
  '⚠️',
  '✅',
  '❌',
];

// 1 MiB(한글 약 35만 자). inline 모드에서 이보다 큰 인바운드 msg는 버리고, 아웃바운드는 실패로 기록
// unlimited 모드는 이 검사를 건너뛰고 kFrameCeilingBytes만 최후 가드로 남음
const int kMaxInlineMessageBytes = 1024 * 1024;

// 2 MiB. kMaxInlineMessageBytes가 base64로 ~1.4배 커지는 걸 덮음
// 넘으면 프레임을 버리고 링크를 끊음
const int kMaxFrameBytes = 2 * 1024 * 1024;

// unlimited 모드의 최후 상한. 진짜 무한대는 악성 피어에게 RAM 고갈 구멍을 열어줌
const int kFrameCeilingBytes = 64 * 1024 * 1024;

// spillToFile 모드에서 이 크기를 넘는 텍스트는 인라인 대신 .txt 파일 전송
// (버블엔 미리보기 + 저장 버튼)
const int kSpillThresholdBytes = 64 * 1024;

// file_offer에 실려 받는 쪽이 저장 전에 앞부분을 볼 수 있게 함
const int kSpillPreviewBytes = 2 * 1024;

// 수락 전 썸네일(디코드 후 바이트) 상한. 보내는 쪽은 24 KB PNG까지만 만듦
const int kMaxThumbBytes = 64 * 1024;

// SAS용 HKDF 컨텍스트. 정렬된 transcript에서 뽑아 양쪽이 항상 같은 출력을 얻음
const String kSasInfo = 'intragram/v2/sas';

// 재브로드캐스트/재스캔 주기. 절전 후 mDNS 콜백이 불안정한 플랫폼용 안전망
const Duration kDiscoveryRefresh = Duration(seconds: 20);

// 죽은 피어 감지용 keep-alive. 다이얼한 쪽 소켓에도 걸어서 OS TCP 타임아웃을 안 기다림
const Duration kSocketPingInterval = Duration(seconds: 15);

// 이 시간 안에 핸드셰이크가 안 끝나면 링크를 끊음
// 응답 없거나 프로토콜이 안 맞는 상대를 매달아두지 않음
const Duration kHandshakeTimeout = Duration(seconds: 12);

// 핸드셰이크 전 아웃바운드 큐 상한(개수/바이트). 넘으면 전송 실패로 기록해서
// 느리거나 응답 없는 상대 때문에 큐가 무한정 쌓여 메모리가 고갈되는 걸 막음
const int kMaxPendingOutboundFrames = 64;
const int kMaxPendingOutboundBytes = 1024 * 1024;

// 마지막 typing 갱신 뒤 이 시간이 지나면 "입력 중" 표시를 끔
// 입력하다 앱을 덮어도 "typing…"이 영원히 안 남게 함
const Duration kTypingIdleTimeout = Duration(seconds: 6);

const String kAppName = 'IntraGram';

// 방향별 HKDF 컨텍스트. 공개키 정렬에서 low/high 여부로 송수신 키를 고름 (completeHandshake 참고)
// 네 채널(메시지·파일 × 양방향)이 전부 다른 키라 다른 방향/채널로 재생해도 안 열림 (반사 공격 방지)
const String kMessageKdfInfoLowToHigh = 'intragram/v2/message/low-to-high';
const String kMessageKdfInfoHighToLow = 'intragram/v2/message/high-to-low';
const String kFileKdfInfoLowToHigh = 'intragram/v2/file/low-to-high';
const String kFileKdfInfoHighToLow = 'intragram/v2/file/high-to-low';

// 동시 전송 상한. 넘는 건 큐잉했다가 앞선 게 끝나면 시작함. 배치 하나가 대역폭을 독식하지 않게 함
const int kMaxConcurrentTransfers = 3;

// 이 시간 동안 바이트가 안 움직이면 멈춘 걸로 보고 실패 처리 (동시성 게이트 대기, 소스 읽기, 소켓 쓰기 전부 해당)
// 없으면 accept 후 원본이 push를 시작 못 할 때(스테이징 소실 등) 받는 쪽이 0%에서 영원히 멈추고 재시도도 못 함
const Duration kTransferStallTimeout = Duration(seconds: 25);

// EOF 뒤 file_received ACK를 기다리는 시간. 안 오면 failed 처리
// wire의 EOF 자체를 완료로 오인하지 않으려는 것
const Duration kFileReceivedAckTimeout = Duration(seconds: 25);

// 패닉 소각의 사전 정지 단계 하나가 이 시간을 넘으면 포기하고 다음으로 진행함
// (되돌릴 수 없는 액션이 붙들려 있으면 안 됨). 포기해도 그 Future는 취소 안 되고
// 백그라운드에서 계속 정리됨. 기다리기만 그만둠
const Duration kPanicStepTimeout = Duration(seconds: 5);

// AEAD 카운터(seq) 상한 2^53-1. 웹 클라이언트가 JSON 숫자를 float64로 파싱해서 넘으면 정수 왕복이 깨짐
// 이 값에 닿기 전에 링크를 닫고 새 핸드셰이크를 강제함. seal/open 양쪽에서 항상 검사
const int kMaxCryptoSequence = 9007199254740991;

// 동시 미인증(핸드셰이크 중) 인바운드 상한. 넘으면 새 소켓을 즉시 닫음
// hello를 안 보내는 연결로 링크/타이머/타일이 무한정 쌓이는 걸 막음. 이미 식별된 피어의 재연결엔 안 걸림
const int kMaxPendingHandshakes = 16;

// 한 host가 hello 없는 소켓만 열어도 전체 상한을 독식하지 못하게 host별로도 제한
// 웹 클라이언트는 걸려도 다시 붙음
const int kMaxPendingHandshakesPerHost = 4;

// kInboundWindow 동안 host별/전체 인바운드 연결 수 상한. 핸드셰이크 하나가 UI 스레드를
// 수 ms 쓰는데 공격자가 싸게 반복시킬 수 있어서 동시 상한과 별개로 빈도도 제한함
// 합계 상한은 주소를 여러 개 쓰는 기기가 host별 상한을 곱해 우회하지 못하게 함
const int kMaxInboundPerWindow = 24;
const int kMaxInboundPerWindowAllHosts = 96;
const Duration kInboundWindow = Duration(seconds: 10);

// 요청 사이·첫 요청 전 HTTP 연결이 놀 수 있는 시간 (dart:io 기본 120초)
const Duration kHttpIdleTimeout = Duration(seconds: 10);

// 웹 포털 방 하나에 들어올 수 있는 브라우저 게스트 수. 입장 코드만 있으면 탭을 끝없이 열 수 있어서 둠
const int kMaxWebGuests = 32;
