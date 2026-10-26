part of '../link_registry.dart';

// 다이얼이 실패한 이유. 안내 문구와 다음 행동이 이유마다 다름
enum PeerUnreachableReason {
  // 아무 응답 없음: 주소가 틀렸거나, 상대 앱이 꺼졌거나, 망이 기기끼리를 막음(AP isolation)
  noAnswer,
  // 그 주소의 기기가 거절함: 그 포트에 IntraGram이 안 떠 있거나 방화벽
  refused,
  // 이 망에서 그 주소로 갈 길이 없음: 다른 네트워크, 또는 iOS·macOS 로컬 네트워크 권한이 꺼짐
  noRoute,
  // 뭔가 답했지만 IntraGram이 아님 (포트가 다른 서비스)
  notIntraGram,
}

class PeerUnreachableException implements Exception {
  PeerUnreachableException(this.message, {required this.reason});
  final String message;
  final PeerUnreachableReason reason;
  @override
  String toString() => 'PeerUnreachableException(${reason.name}): $message';
}

// errno는 플랫폼마다 다름: Darwin, Linux·Android, Windows(WSA) 순
const Set<int> _refusedCodes = {61, 111, 10061};
const Set<int> _noRouteCodes = {51, 65, 64, 101, 112, 113, 10051, 10064, 10065};

PeerUnreachableReason classifyDialError(Object error) {
  if (error is WebSocketException || error is HttpException) {
    return PeerUnreachableReason.notIntraGram;
  }
  final code = error is SocketException ? error.osError?.errorCode : null;
  if (_refusedCodes.contains(code)) return PeerUnreachableReason.refused;
  if (_noRouteCodes.contains(code)) return PeerUnreachableReason.noRoute;
  return PeerUnreachableReason.noAnswer;
}
