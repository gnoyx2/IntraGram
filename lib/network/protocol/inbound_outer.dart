part of '../protocol.dart';

sealed class InboundOuter {
  const InboundOuter();

  // raw 텍스트 프레임 파싱. 나쁜 프레임 하나가 링크를 못 죽이게 던지지 않고 MalformedOuter를 리턴
  factory InboundOuter.parse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) {
        return const MalformedOuter('not an object');
      }
      switch (j['t']) {
        case 'hello':
          final version = (j['v'] ?? '').toString();
          if (version != kProtocolVersion) {
            return VersionMismatchOuter(peerVersion: version);
          }
          // peerId는 방 명단(peers)에 그대로 실려 다른 멤버의 엄격
          // 파서를 통과해야 해서, 형식이 틀린 신원은 핸드셰이크 전에 버림 (링크는
          // 워치독이 닫음)
          final peerId = wireId(j['peerId']);
          if (peerId == null) return const MalformedOuter('hello peerId');
          // 신원 공개키는 필수. 서명은 리스너의 hello에만 있고, 있는데 형식이 틀리면 거부
          final identityKey = wireBytes(j['idk'], length: 32);
          if (identityKey == null) return const MalformedOuter('hello idk');
          final signature = wireBytes(j['sig'], length: 64);
          if (j['sig'] != null && signature == null) {
            return const MalformedOuter('hello sig');
          }
          // 임시키(리스너)와 커밋(다이얼러)은 역할마다 하나만 옴. 어느 쪽이 와야 하는지는 링크가 검사함
          final ephemeral = wireBytes(j['pub'], length: 32);
          if (j['pub'] != null && ephemeral == null) {
            return const MalformedOuter('hello pub');
          }
          final commitment = wireBytes(j['cmt'], length: 32);
          if (j['cmt'] != null && commitment == null) {
            return const MalformedOuter('hello cmt');
          }
          return HelloOuter(
            peerId: peerId,
            alias: boundedAlias((j['alias'] ?? 'peer').toString()),
            platform: (j['platform'] ?? 'Unknown').toString(),
            ephemeralKey: ephemeral,
            commitment: commitment,
            identityKey: identityKey,
            signature: signature,
            port: j['port'] is int ? j['port'] as int : null,
          );
        case 'auth':
          final signature = wireBytes(j['sig'], length: 64);
          if (signature == null) return const MalformedOuter('auth sig');
          final ephemeral = wireBytes(j['pub'], length: 32);
          if (ephemeral == null) return const MalformedOuter('auth pub');
          return AuthOuter(ephemeralKey: ephemeral, signature: signature);
        case 'web_hello':
          final version = (j['v'] ?? '').toString();
          if (version != kProtocolVersion) {
            return VersionMismatchOuter(peerVersion: version);
          }
          return WebHelloOuter(
            alias: boundedAlias((j['alias'] ?? 'guest').toString()),
            token: j['tok']?.toString(),
          );
        case 'enc':
          return EncOuter(
            nonceB64: (j['n'] ?? '').toString(),
            cipherB64: (j['c'] ?? '').toString(),
            macB64: (j['m'] ?? '').toString(),
            // 리플레이 방어의 유일한 근거라 애매하면 항상 거부되는 닫힌
            // 쪽 값(-1)으로 폴백. 상한도 kMaxCryptoSequence로
            // 못박음
            // (wire 정수 왕복 범위 밖은 유효한 seq가 아님)
            seq: wireInt(j['seq'], min: 0, max: kMaxCryptoSequence) ?? -1,
          );
        case 'plain':
          final d = j['d'];
          if (d is Map<String, dynamic>) return PlainOuter(inner: d);
          return const MalformedOuter('plain frame missing object payload');
        default:
          return MalformedOuter('unknown outer type ${j['t']}');
      }
    } on FormatException catch (e) {
      return MalformedOuter('bad json: ${e.message}');
    }
  }
}

class HelloOuter extends InboundOuter {
  const HelloOuter({
    required this.peerId,
    required this.alias,
    required this.platform,
    required this.identityKey,
    this.ephemeralKey,
    this.commitment,
    this.signature,
    this.port,
  });
  final String peerId;
  final String alias;
  final String platform;

  // 상대가 밝힌 신원 공개키(32바이트). peerId가 그 해시여야 통과
  final Uint8List identityKey;

  // 리스너의 X25519 임시키(32바이트). 다이얼러는 대신 commitment를 보내고 임시키는 AuthOuter로 공개
  final Uint8List? ephemeralKey;
  final Uint8List? commitment;

  // 리스너의 신원 증명(64바이트). 다이얼러의 hello엔 없고 이어지는 AuthOuter로 옴
  final Uint8List? signature;
  final int? port;
}

// 다이얼러가 리스너의 hello를 받은 뒤 보내는 임시키 공개 + 신원 증명 (서명 대상은 peer_auth.dart 참고)
class AuthOuter extends InboundOuter {
  const AuthOuter({required this.ephemeralKey, required this.signature});
  final Uint8List ephemeralKey;
  final Uint8List signature;
}

class WebHelloOuter extends InboundOuter {
  const WebHelloOuter({required this.alias, this.token});
  final String alias;

  // QR/URL fragment로 전달된 256-bit 포털 토큰(base64url). 누락되거나
  // 현재 토큰과 다르면 링크가 방에 못 들어감 (PeerLink.requiredWebToken 참고)
  final String? token;
}

// hello/web_hello의 프로토콜 버전이 kProtocolVersion과 정확히 일치하지 않음 (누락/구버전 전부 여기)
// 평문으로 진행하는 척하지 않고 번역된 오류를 보여준 뒤 링크를 닫음
class VersionMismatchOuter extends InboundOuter {
  const VersionMismatchOuter({required this.peerVersion});
  final String peerVersion;
}

class EncOuter extends InboundOuter {
  const EncOuter({
    required this.nonceB64,
    required this.cipherB64,
    required this.macB64,
    required this.seq,
  });
  final String nonceB64;
  final String cipherB64;
  final String macB64;

  // 보내는 쪽의 링크당 단방향 프레임 카운터. AEAD associated data로도 인증됨 (CryptoSession.open 참고)
  final int seq;
}

class PlainOuter extends InboundOuter {
  const PlainOuter({required this.inner});
  final Map<String, dynamic> inner;
}

class MalformedOuter extends InboundOuter {
  const MalformedOuter(this.reason);
  final String reason;
}
