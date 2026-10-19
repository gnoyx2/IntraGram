import 'dart:async';

import 'package:collection/collection.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/secure_bytes.dart';

import 'models.dart';
import 'vault.dart';

part 'internal/state.dart';
part 'internal/core.dart';
part 'internal/mutations.dart';
part 'internal/messages.dart';
part 'internal/lifecycle.dart';
part 'internal/persistence.dart';

// 대화 상태가 사는 유일한 곳 (프로세스 힙). DB/파일/SharedPreferences 없음
// 메시지 본문은 Dart String이라 제자리 스크럽이 불가능함 (바이트 mutable view가 없고 GC가 복사하며 옛 주소에
// 사본이 남음). 그래서 텍스트는 영속 계층에 안 쓰고 참조를 하나만 유지하다가 소각/초기화 즉시 해제해 바로 수집되게 함
// 앱이 소유한 바이트 버퍼(프레임 평문, 파일 청크, 음성)는 다 쓰면 SecureBytes.wipe로 0 -> 랜덤 -> 0으로 덮고,
// 세션 키·vault 키는 앱 소유 SecretKeyData라 destroy 때 0으로 덮임. 암호 라이브러리 내부 사본과 String은 못 덮음
// 상태 필드는 _InMemoryStoreState, 동작은 store/internal/의 믹스인
class InMemoryStore extends _InMemoryStoreState
    with
        _StoreCore,
        _StoreMutations,
        _StoreMessages,
        _StoreLifecycle,
        _StorePersistence {}
