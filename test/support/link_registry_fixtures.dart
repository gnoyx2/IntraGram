import 'package:intragram/core/app_identity.dart';
import 'package:intragram/store/models.dart';

import 'test_identities.dart';

AppIdentity identity() =>
    testIdentity('0', alias: 'test-host-10', platform: 'Linux');

Conversation conv(String id) => Conversation(
  id: id,
  peerAlias: 'peer',
  peerPlatform: 'test',
  transport: PeerTransport.app,
  startedAt: DateTime(2026, 1, 1),
  online: true,
);
