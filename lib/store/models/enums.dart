part of '../models.dart';

enum MessageDirection { incoming, outgoing }

enum MessageKind { text, file, system }

// 렌더 시점에 UI가 현재 언어로 번역함 (영어 문자열을 모델에 저장하지 않음)
enum SystemEventKind {
  disconnected,
  encrypted,
  // 이전 세션 코드가 있던 대화에 새 세션(재연결): 코드가 바뀌어 검증을 다시 해야 함
  encryptedAgain,
  // 재연결했는데 전에 확인한 신원 키 그대로라 확인이 이어짐 (코드만 바뀜)
  verifiedAgain,
  becameRoom,
  markedVerified,
  mutuallyVerified,
  joinedRoom, // alias 필요
  memberJoined, // alias 필요
  memberLeft, // alias 필요
  screenshotByPeer, // alias 필요
  screenshotByMe,
  protocolVersionMismatch,
  sasMismatch,
  // 내가 다이얼한 핸드셰이크가 실패한 이유 (연결 끊김 대신 남김)
  peerMismatch,
  handshakeFailed,
  handshakeTimedOut,
  peerBlocked,
}

// inline: RAM에 최대 1 MiB(kMaxInlineMessageBytes), 초과분 거부
// unlimited: 인라인 상한 없음 (kFrameCeilingBytes만 최후 가드)
// spillToFile: kSpillThresholdBytes를 넘으면 .txt 전송으로 보냄
enum LargeMessageMode { inline, unlimited, spillToFile }

enum DeliveryState { sending, sent, delivered, read, failed }

enum TransferDirection { incoming, outgoing }

enum TransferState {
  offered,
  accepted,
  rejected,
  transferring,
  complete,
  failed,
  cancelled,
}

enum PeerTransport { app, web }

// push: 보내는 쪽이 POST로 밈 (1:1 전용). pull: 받는
// 쪽이 원본 서버에서 GET으로 당김 (그룹 방 직접 전송, 음성 메시지)
// FileOfferInner.mode의 wire 표현을 받는 쪽 레코드에 타입 있게 고정한 값
enum FileTransferMode { push, pull }
