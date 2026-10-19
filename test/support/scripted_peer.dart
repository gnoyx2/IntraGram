import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_auth.dart';
import 'package:intragram/network/protocol.dart';

// 진짜 링크의 반대편에서 와이어를 손으로 말하는 피어: hello/auth를 직접 만들어 넣고 링크가 보낸
// 프레임을 모아 둠. 신원 증명의 정상 경로와 위조 경로(남의 peerId 사칭·다른 세션 서명 재생·역할/상대
// 바꿔치기·커밋과 다른 키 공개)를 프레임 단위로 시험하는 데 씀. 진짜 X25519 임시 세션을 갖고 있어
// 키 합의도 진짜로 끝낼 수 있음
class ScriptedPeer {
  ScriptedPeer._(this.identity, this.session, this.channel) {
    channel.stream.listen((raw) {
      frames.add(jsonDecode(raw as String) as Map<String, dynamic>);
    });
  }

  static Future<ScriptedPeer> create(
    AppIdentity identity,
    StreamChannel<dynamic> channel,
  ) async =>
      ScriptedPeer._(identity, await CryptoEngine().createSession(), channel);

  final AppIdentity identity;
  final CryptoSession session;
  final StreamChannel<dynamic> channel;

  final List<Map<String, dynamic>> frames = <Map<String, dynamic>>[];

  Uint8List get key => identity.publicKey!;

  // 이 세션 임시키의 정직한 커밋 (스크립트가 다이얼러일 때 hello에 실음)
  Uint8List get commitment =>
      ephemeralCommitment(ephemeral: session.publicKey, identityKey: key);

  Map<String, dynamic> get linkHello =>
      frames.firstWhere((f) => f['t'] == 'hello');
  Map<String, dynamic> get linkAuth =>
      frames.singleWhere((f) => f['t'] == 'auth');

  Uint8List get linkKey => base64.decode(linkHello['idk'] as String);

  // 링크가 리스너면 hello에 임시키를, 다이얼러면 커밋을 싣고 임시키는 auth로 공개함
  Uint8List get linkEphemeral => base64.decode(linkHello['pub'] as String);
  Uint8List get linkCommitment => base64.decode(linkHello['cmt'] as String);
  Uint8List get linkRevealed => base64.decode(linkAuth['pub'] as String);

  // 스크립트가 리스너: 임시키 + (있으면) 서명. 위조 경로는 키를 빼거나 커밋을 섞어 봄
  void sendHello({
    String? peerId,
    List<int>? claimedKey,
    List<int>? signature,
    String alias = 'scripted',
    bool withEphemeral = true,
    List<int>? commitment,
  }) => channel.sink.add(
    OuterFrame.hello(
      peerId: peerId ?? identity.peerId,
      alias: alias,
      platform: 'test',
      identityKeyB64: base64.encode(claimedKey ?? key),
      publicKeyB64: withEphemeral ? session.publicKeyBase64 : null,
      commitmentB64: commitment == null ? null : base64.encode(commitment),
      signatureB64: signature == null ? null : base64.encode(signature),
    ),
  );

  // 스크립트가 다이얼러: 커밋만 (기본은 이 세션의 정직한 커밋). 위조 경로는 키를 같이 싣거나 커밋을 뺌
  void sendDialerHello({
    String? peerId,
    List<int>? claimedKey,
    List<int>? commitment,
    bool withCommitment = true,
    bool withEphemeral = false,
  }) => channel.sink.add(
    OuterFrame.hello(
      peerId: peerId ?? identity.peerId,
      alias: 'scripted',
      platform: 'test',
      identityKeyB64: base64.encode(claimedKey ?? key),
      publicKeyB64: withEphemeral ? session.publicKeyBase64 : null,
      commitmentB64: withCommitment
          ? base64.encode(
              commitment ??
                  ephemeralCommitment(
                    ephemeral: session.publicKey,
                    identityKey: claimedKey ?? key,
                  ),
            )
          : null,
    ),
  );

  // 임시키 공개 + 서명. reveal 기본값은 이 세션의 임시키(커밋과 맞음)
  void sendAuth(List<int> signature, {List<int>? reveal}) => channel.sink.add(
    OuterFrame.auth(
      publicKeyB64: base64.encode(reveal ?? session.publicKey),
      signatureB64: base64.encode(signature),
    ),
  );

  // 스크립트가 다이얼러면 리스너 hello의 임시키로, 리스너면 링크가 auth로 공개한 임시키로 끝냄
  Future<void> completeHandshake({bool asDialer = true}) =>
      session.completeHandshake(
        base64.encode(asDialer ? linkEphemeral : linkRevealed),
      );

  // 이 세션의 정직한 서명. [asDialer]면 이 스크립트가 다이얼러(공개한 임시키로 서명), 아니면
  // 리스너(링크의 커밋으로 서명). 인자를 바꾸면 위조 서명(다른 상대·다른 키·다른 역할·다른 서명 키)이 됨
  Future<Uint8List> proof({
    required bool asDialer,
    List<int>? ownEphemeral,
    List<int>? peerEphemeral,
    List<int>? dialerCommitment,
    List<int>? ownKey,
    List<int>? peerKey,
    bool? dialerRole,
    AppIdentity? signer,
  }) {
    final own = ownEphemeral ?? session.publicKey;
    final ownId = ownKey ?? key;
    final peerId = peerKey ?? linkKey;
    // 다이얼러 자리 필드: 다이얼러가 서명하면 공개한 임시키, 리스너가 서명하면 커밋
    final dialerPart = asDialer ? own : (dialerCommitment ?? linkCommitment);
    final listenerPart = asDialer ? (peerEphemeral ?? linkEphemeral) : own;
    final dialerKey = asDialer ? ownId : peerId;
    final listenerKey = asDialer ? peerId : ownId;
    final transcript = (dialerRole ?? asDialer)
        ? dialerTranscript(
            dialerEphemeral: dialerPart,
            listenerEphemeral: listenerPart,
            dialerKey: dialerKey,
            listenerKey: listenerKey,
          )
        : listenerTranscript(
            dialerCommitment: dialerPart,
            listenerEphemeral: listenerPart,
            dialerKey: dialerKey,
            listenerKey: listenerKey,
          );
    return (signer ?? identity).sign(transcript);
  }
}
