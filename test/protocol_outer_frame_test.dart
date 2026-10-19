import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/protocol.dart';

void main() {
  final key = base64.encode(Uint8List.fromList(List<int>.filled(32, 7)));
  final sig = base64.encode(Uint8List.fromList(List<int>.filled(64, 9)));

  final cmt = base64.encode(Uint8List.fromList(List<int>.filled(32, 4)));
  final eph = base64.encode(Uint8List.fromList(List<int>.filled(32, 5)));

  test('a dialer hello round-trips with a commitment and no key', () {
    final raw = OuterFrame.hello(
      peerId: 'p1',
      alias: 'blue-fox-12',
      platform: 'Linux',
      commitmentB64: cmt,
      identityKeyB64: key,
    );
    expect(jsonDecode(raw), isNot(contains('pub')));
    final parsed = InboundOuter.parse(raw);
    expect(parsed, isA<HelloOuter>());
    parsed as HelloOuter;
    expect(parsed.alias, 'blue-fox-12');
    expect(parsed.platform, 'Linux');
    expect(parsed.commitment, List<int>.filled(32, 4));
    expect(parsed.ephemeralKey, isNull);
    expect(parsed.identityKey, List<int>.filled(32, 7));
    expect(parsed.signature, isNull, reason: 'a dialer hello has no proof yet');
  });

  test('a listener hello carries its key and signature', () {
    final parsed =
        InboundOuter.parse(
              OuterFrame.hello(
                peerId: 'p1',
                alias: 'a',
                platform: 'Linux',
                publicKeyB64: eph,
                identityKeyB64: key,
                signatureB64: sig,
              ),
            )
            as HelloOuter;
    expect(parsed.ephemeralKey, List<int>.filled(32, 5));
    expect(parsed.commitment, isNull);
    expect(parsed.signature, List<int>.filled(64, 9));
  });

  test('auth frame round-trips with the revealed key', () {
    final parsed = InboundOuter.parse(
      OuterFrame.auth(publicKeyB64: eph, signatureB64: sig),
    );
    expect(parsed, isA<AuthOuter>());
    parsed as AuthOuter;
    expect(parsed.ephemeralKey, List<int>.filled(32, 5));
    expect(parsed.signature, List<int>.filled(64, 9));
  });

  test('an identity key or signature of the wrong shape is malformed', () {
    String hello(Map<String, Object?> extra) => jsonEncode(<String, Object?>{
      't': 'hello',
      'v': kProtocolVersion,
      'peerId': 'p1',
      'pub': eph,
      ...extra,
    });
    final short = base64.encode(Uint8List(31));
    for (final bad in <Map<String, Object?>>[
      <String, Object?>{}, // idk 누락
      <String, Object?>{'idk': short},
      <String, Object?>{'idk': 'not base64!'},
      <String, Object?>{'idk': 5},
      <String, Object?>{'idk': key, 'sig': short},
      <String, Object?>{'idk': key, 'sig': 5},
      <String, Object?>{'idk': key, 'pub': short},
      <String, Object?>{'idk': key, 'pub': 'QUJD'},
      <String, Object?>{'idk': key, 'cmt': short},
      <String, Object?>{'idk': key, 'cmt': 5},
    ]) {
      expect(
        InboundOuter.parse(hello(bad)),
        isA<MalformedOuter>(),
        reason: '$bad',
      );
    }
    expect(InboundOuter.parse('{"t":"auth"}'), isA<MalformedOuter>());
    expect(
      InboundOuter.parse(
        '{"t":"auth","pub":"$eph","sig":"${base64.encode(Uint8List(63))}"}',
      ),
      isA<MalformedOuter>(),
    );
    expect(
      InboundOuter.parse('{"t":"auth","sig":"$sig"}'),
      isA<MalformedOuter>(),
      reason: 'an auth must reveal the committed key',
    );
    expect(
      InboundOuter.parse('{"t":"auth","pub":"$short","sig":"$sig"}'),
      isA<MalformedOuter>(),
    );
  });

  test('enc frame round-trips', () {
    final parsed = InboundOuter.parse(
      OuterFrame.enc(nonceB64: 'n', cipherB64: 'c', macB64: 'm', seq: 7),
    );
    expect(parsed, isA<EncOuter>());
    parsed as EncOuter;
    expect((parsed.nonceB64, parsed.cipherB64, parsed.macB64), ('n', 'c', 'm'));
    expect(parsed.seq, 7);
  });

  test('enc frame with a missing or malformed seq parses to -1', () {
    final parsed =
        InboundOuter.parse('{"t":"enc","n":"n","c":"c","m":"m"}') as EncOuter;
    expect(parsed.seq, -1);
  });

  test('plain frame carries the inner object', () {
    final parsed = InboundOuter.parse(OuterFrame.plain(InnerFrame.read('x1')));
    expect(parsed, isA<PlainOuter>());
    parsed as PlainOuter;
    expect(parsed.inner['k'], 'read');
  });

  test('malformed input never throws', () {
    expect(InboundOuter.parse('{not json'), isA<MalformedOuter>());
    expect(InboundOuter.parse('[]'), isA<MalformedOuter>());
    expect(InboundOuter.parse('{"t":"mystery"}'), isA<MalformedOuter>());
  });
}
