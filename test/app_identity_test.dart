import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';

void main() {
  test('rename changes alias in place, peerId and platform untouched', () {
    final identity = AppIdentity(
      peerId: 'p' * 32,
      alias: 'blue-otter-38',
      platform: 'Linux',
    );

    identity.rename('wise-elk-19');

    expect(identity.alias, 'wise-elk-19');
    expect(identity.peerId, 'p' * 32);
    expect(identity.platform, 'Linux');
  });

  test('a reference held before rename sees the new alias', () {
    final identity = AppIdentity(
      peerId: 'p' * 32,
      alias: 'blue-otter-38',
      platform: 'Linux',
    );
    final heldReference = identity;

    identity.rename('wise-elk-19');

    expect(
      heldReference.alias,
      'wise-elk-19',
      reason:
          'consumers holding the object (LinkRegistry, '
          'DiscoveryController) must see renames without a rebuild',
    );
  });

  test('randomAlias produces the adjective-animal-number shape', () {
    final alias = AppIdentity.randomAlias();
    expect(alias, matches(RegExp(r'^[a-z]+-[a-z]+-\d{2}$')));
  });

  test("generate() seeds AppIdentity.alias with randomAlias's shape", () {
    final identity = AppIdentity.generate();
    expect(identity.alias, matches(RegExp(r'^[a-z]+-[a-z]+-\d{2}$')));
    expect(identity.peerId, hasLength(32));
  });
}
