import 'dart:async';

import 'package:collection/collection.dart';

import 'package:intragram/audit/content_commitment.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/secure_bytes.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/room_integrity.dart';

import 'models.dart';
import 'vault.dart';

part 'internal/state.dart';
part 'internal/core.dart';
part 'internal/mutations.dart';
part 'internal/messages.dart';
part 'internal/lifecycle.dart';
part 'internal/persistence.dart';
part 'internal/evidence.dart';

// 런타임 대화 상태를 보관하는 유일한 곳(프로세스 힙)임. 자체 DB·파일·SharedPreferences는 쓰지 않음(선택적 보관은 Vault가 담당함).
// 메시지 본문은 Dart String이라 제자리에서 못 지움(GC가 옮기며 사본을 남김): 참조를 하나만 두고 소각·초기화 때 바로 놓음.
// 앱이 가진 바이트 버퍼(프레임 평문, 파일 청크, 음성)는 SecureBytes.wipe로 0 → 랜덤 → 0으로 덮고, 세션·보관소 키는 destroy 때 0으로 덮음
// (암호 라이브러리 내부 사본과 String은 못 덮음)
class InMemoryStore extends _InMemoryStoreState
    with
        _StoreCore,
        _StoreMutations,
        _StoreMessages,
        _StoreLifecycle,
        _StorePersistence {}
