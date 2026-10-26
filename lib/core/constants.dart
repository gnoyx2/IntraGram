// 별도 설정 저장소가 없어 관련 설정값도 전부 상수로 정의해 둠
library;

// 와이어 형식이 바뀌면 올림. hello 버전이 정확히 같아야 붙어서 웹 클라이언트(socket.js)도 같이 올려야 함.
// 버전별 차이는 README의 Wire protocol 참고
const String kProtocolVersion = '7';

const String kServiceType = '_intragram._tcp';

// 쓰고 있으면 kPortScanRange만큼 다음 포트를 훑음
const int kPreferredPort = 7890;

const int kPortScanRange = 40;

// 2 MiB: 기가비트 Wi-Fi는 채우고 수 GB 파일이 RAM에 통째로 안 뜨는 크기
const int kFileChunkBytes = 2 * 1024 * 1024;

// 넘으면 알아서 멈추고 보냄
const int kMaxVoiceNoteSeconds = 120;

// 16kHz 16비트 모노 120초 WAV(약 3.66 MiB)에 여유를 둠. 넘으면 버림
const int kMaxVoiceNoteBytes = 4 * 1024 * 1024;

const int kVoiceSampleRate = 16000;

// 네이티브 파일 읽기 단위. Dart가 이만큼씩 당겨서 버퍼가 무한정 쌓이지 않음
const int kMobileFileReadChunkBytes = 256 * 1024;

// 0은 타이머 없음
const List<int> kBurnTtlOptions = <int>[0, 5, 30, 60];

// 카운트다운은 상대가 읽어야 시작해서, 안 읽으면 보낸 지 이만큼 뒤에 그냥 태움
const Duration kUnreadBurnCeiling = Duration(hours: 24);

const List<String> kQuickReactions = <String>[
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
];

// 자유 입력 대신 고르기만 함 (IME 조합 중에 시트를 닫을 때 비정상 종료되던 문제를 방지함)
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

// 1 MiB(한글 약 35만 자). inline 모드는 넘는 msg를 받으면 버리고 보내면 실패 처리함. unlimited는 kFrameCeilingBytes만 봄
const int kMaxInlineMessageBytes = 1024 * 1024;

// base64로 1.4배쯤 커진 kMaxInlineMessageBytes를 덮는 크기. 넘으면 링크를 끊음
const int kMaxFrameBytes = 2 * 1024 * 1024;

// unlimited 모드의 마지막 상한 (진짜 무제한이면 악성 피어가 RAM을 고갈시킬 수 있음)
const int kFrameCeilingBytes = 64 * 1024 * 1024;

// spillToFile 모드에서 이보다 긴 글은 .txt 파일로 보냄
const int kSpillThresholdBytes = 64 * 1024;

// 긴 글 파일의 미리보기 길이 (file_offer에 실림)
const int kSpillPreviewBytes = 2 * 1024;

// 수락 전 썸네일 상한(base64 디코드 뒤 바이트). 보내는 쪽은 24 KB PNG까지만 만듦
const int kMaxThumbBytes = 64 * 1024;

const String kSasInfo = 'intragram/v2/sas';

// mDNS 재광고·재검색 주기. 절전 뒤 콜백이 끊기는 플랫폼용 안전망
const Duration kDiscoveryRefresh = Duration(seconds: 20);

// 죽은 피어 감지용 ping. 다이얼한 쪽에도 걸어서 OS TCP 타임아웃을 안 기다림
const Duration kSocketPingInterval = Duration(seconds: 15);

const Duration kHandshakeTimeout = Duration(seconds: 12);

// 송신 프레임 대기열 상한(개수 및 바이트). 지연 피어로 메모리가 과도하게 쌓이는 걸 막으려 초과 시 실패 처리함
const int kMaxPendingOutboundFrames = 64;
const int kMaxPendingOutboundBytes = 1024 * 1024;

// 입력 중 갱신이 없으면 상태를 해제함 (상대가 앱을 닫았을 때 입력 표시가 남지 않게 함)
const Duration kTypingIdleTimeout = Duration(seconds: 6);

const String kAppName = 'IntraGram';

// 방향별 HKDF info. 메시지·파일 × 양방향 네 키가 다 달라서 다른 방향·채널로 되돌려 보내도 안 열림
const String kMessageKdfInfoLowToHigh = 'intragram/v2/message/low-to-high';
const String kMessageKdfInfoHighToLow = 'intragram/v2/message/high-to-low';
const String kFileKdfInfoLowToHigh = 'intragram/v2/file/low-to-high';
const String kFileKdfInfoHighToLow = 'intragram/v2/file/high-to-low';

// 동시 전송 상한. 나머지는 줄 섬
const int kMaxConcurrentTransfers = 3;

// 바이트가 이만큼 안 움직이면 멈춘 것으로 보고 실패 처리함 (대기·읽기·쓰기 전부). 없으면 받는 쪽이 0%에서 영영 멈춤
const Duration kTransferStallTimeout = Duration(seconds: 25);

// EOF 뒤 file_received ACK 대기 시간. EOF만으론 완료로 안 봄
const Duration kFileReceivedAckTimeout = Duration(seconds: 25);

// 패닉 소각의 정지 단계 하나가 이만큼 넘게 걸리면 안 기다리고 넘어감 (그 작업은 뒤에서 계속 정리됨)
const Duration kPanicStepTimeout = Duration(seconds: 5);

// AEAD 카운터 상한 2^53-1: 웹 클라이언트가 JSON 숫자를 float64로 읽어서 넘으면 정수가 깨짐. 닿기 전에 링크를 닫음
const int kMaxCryptoSequence = 9007199254740991;

// 핸드셰이크 중인 인바운드 동시 상한. hello 안 보내는 소켓이 무한정 쌓이는 걸 막음
const int kMaxPendingHandshakes = 16;

// host 하나가 전체 상한을 독식 못 하게 host별로도 막음
const int kMaxPendingHandshakesPerHost = 4;

// kInboundWindow 동안 인바운드 연결 수 상한 (host별·전체). 핸드셰이크 한 번이 UI 스레드를 몇 ms 먹어서 빈도도 막음.
// 전체 상한은 주소 여러 개로 host별 상한을 곱하는 걸 막음
const int kMaxInboundPerWindow = 24;
const int kMaxInboundPerWindowAllHosts = 96;
const Duration kInboundWindow = Duration(seconds: 10);

// 요청 전·사이 HTTP 연결이 놀 수 있는 시간 (dart:io 기본 120초)
const Duration kHttpIdleTimeout = Duration(seconds: 10);

// 포털 방 브라우저 게스트 수 상한 (입장 코드만 있으면 탭을 끝없이 열 수 있어 제한함)
const int kMaxWebGuests = 32;
