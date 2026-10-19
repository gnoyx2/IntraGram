import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/protocol.dart';

void main() {
  test('file_offer keeps mime only when present', () {
    final withMime = InnerFrame.fileOffer(
      id: 'f1',
      attempt: 'a1',
      mode: 'push',
      name: 'a.png',
      size: 10,
      mime: 'image/png',
    );
    expect(withMime['mime'], 'image/png');

    final withoutMime = InnerFrame.fileOffer(
      id: 'f2',
      attempt: 'a2',
      mode: 'push',
      name: 'blob',
      size: 1,
    );
    expect(withoutMime.containsKey('mime'), isFalse);
  });

  test(
    'file_offer round-trips the group-room source address and pull token',
    () {
      final room = InnerFrame.fileOffer(
        id: 'f3',
        attempt: 'a3',
        mode: 'pull',
        name: 'deck.pdf',
        size: 4096,
        srcHost: '192.168.1.9',
        srcPort: 7890,
        token: 'tok-3',
      );
      expect((room['sh'], room['sp']), ('192.168.1.9', 7890));
      expect(room['at'], 'a3');
      expect(room['md'], 'pull');
      expect(room['tok'], 'tok-3');

      final inner = InboundInner.fromJson(room) as FileOfferInner;
      expect(inner.srcHost, '192.168.1.9');
      expect(inner.srcPort, 7890);
      expect(inner.attempt, 'a3');
      expect(inner.mode, 'pull');
      expect(inner.token, 'tok-3');

      // 1:1 제안엔 주소/토큰 안 붙고, 파싱하면 null
      final direct = InnerFrame.fileOffer(
        id: 'f4',
        attempt: 'a4',
        mode: 'push',
        name: 'blob',
        size: 1,
      );
      expect(direct.containsKey('sh'), isFalse);
      expect(direct.containsKey('sp'), isFalse);
      expect(direct.containsKey('tok'), isFalse);
      final parsedDirect = InboundInner.fromJson(direct) as FileOfferInner;
      expect(parsedDirect.srcHost, isNull);
      expect(parsedDirect.srcPort, isNull);
      expect(parsedDirect.mode, 'push');
      expect(parsedDirect.token, isNull);
    },
  );

  test('file_offer round-trips a thumbnail and the voice flag', () {
    final rich = InnerFrame.fileOffer(
      id: 'f5',
      attempt: 'a5',
      mode: 'push',
      name: 'voice-note.m4a',
      size: 4096,
      mime: 'audio/mp4',
      thumb: 'QUJD',
      voice: true,
    );
    expect(rich['th'], 'QUJD');
    expect(rich['vc'], true);

    final inner = InboundInner.fromJson(rich) as FileOfferInner;
    expect(inner.thumb, 'QUJD');
    expect(inner.voice, isTrue);

    // 평범한 제안: 두 키 다 생략, 파싱하면 기본값
    final plain = InnerFrame.fileOffer(
      id: 'f6',
      attempt: 'a6',
      mode: 'push',
      name: 'blob',
      size: 1,
    );
    expect(plain.containsKey('th'), isFalse);
    expect(plain.containsKey('vc'), isFalse);
    final parsedPlain = InboundInner.fromJson(plain) as FileOfferInner;
    expect(parsedPlain.thumb, isNull);
    expect(parsedPlain.voice, isFalse);
  });

  test('file_offer round-trips the encrypted flag', () {
    final encrypted = InnerFrame.fileOffer(
      id: 'f7',
      attempt: 'a7',
      mode: 'push',
      name: 'photo.jpg',
      size: 2048,
      enc: true,
    );
    expect(encrypted['ec'], true);
    final inner = InboundInner.fromJson(encrypted) as FileOfferInner;
    expect(inner.enc, isTrue);

    // 평범한 제안: 키 생략, 파싱하면 기본값 false
    final plain = InnerFrame.fileOffer(
      id: 'f8',
      attempt: 'a8',
      mode: 'push',
      name: 'blob',
      size: 1,
    );
    expect(plain.containsKey('ec'), isFalse);
    final parsedPlain = InboundInner.fromJson(plain) as FileOfferInner;
    expect(parsedPlain.enc, isFalse);
  });

  test('file_offer round-trips a text preview snippet', () {
    final spilled = InnerFrame.fileOffer(
      id: 'f10',
      attempt: 'a10',
      mode: 'push',
      name: 'Long message.txt',
      size: 90000,
      preview: 'first couple KB of the message…',
    );
    expect(spilled['pv'], 'first couple KB of the message…');
    final inner = InboundInner.fromJson(spilled) as FileOfferInner;
    expect(inner.preview, 'first couple KB of the message…');
    // 이미지 썸네일과 배타적이지만 프로토콜 레벨에서 강제하진 않음: 둘 다
    // 실려도 파싱은 그대로 통과함(호출부가 절대 같이 안 보냄)
    expect(inner.thumb, isNull);

    // 평범한 제안: 키 생략, 파싱하면 기본값 null
    final plain = InnerFrame.fileOffer(
      id: 'f11',
      attempt: 'a11',
      mode: 'push',
      name: 'blob',
      size: 1,
    );
    expect(plain.containsKey('pv'), isFalse);
    final parsedPlain = InboundInner.fromJson(plain) as FileOfferInner;
    expect(parsedPlain.preview, isNull);
  });

  test('file_accept carries the push authorization token', () {
    final accept = InnerFrame.fileAccept(
      'f12',
      attempt: 'a12',
      token: 'tok-12',
    );
    expect(accept['tok'], 'tok-12');
    expect(accept['at'], 'a12');
    final inner = InboundInner.fromJson(accept) as FileAcceptInner;
    expect(inner.id, 'f12');
    expect(inner.attempt, 'a12');
    expect(inner.token, 'tok-12');
  });

  // 필수 필드가 없는 offer는 명시적으로 거부함: 예전엔 at/md 누락을 빈 attempt/push로 채워 "정상 프레임"을 만들었음
  test('a missing attempt/mode on the wire is rejected, not defaulted', () {
    final legacy = InboundInner.fromJson(<String, dynamic>{
      'k': 'file_offer',
      'id': 'f13',
      'name': 'blob',
      'size': 1,
    });
    expect(legacy, isA<MalformedInner>());
  });
}
