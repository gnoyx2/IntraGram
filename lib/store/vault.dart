import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;

import 'package:intragram/core/private_dir.dart';
import 'package:intragram/core/secure_bytes.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'models.dart';

part 'vault/settings.dart';
part 'vault/snapshot.dart';
part 'vault/crypto.dart';
part 'vault/io.dart';
part 'vault/session.dart';

// copyWith에서 "인자 안 줌"과 명시적 null을 구분하는 센티널
// (VaultSettings.langOverride를 null로 되돌릴 수 있게)
const Object _unset = Object();

// 보호 모드인데 세션 PIN이 없어서 save가 거부됐을 때 던짐. 평문으로 자동 전환하지 않음
// (호출부가 잠금 해제를 시키거나 실패를 보여줘야 함)
class VaultLockedException implements Exception {
  const VaultLockedException(this.message);
  final String message;
  @override
  String toString() => 'VaultLockedException: $message';
}

// 파일 삭제/쓰기 실패 (권한 거부, 디스크 오류 등. 이미 없는 건 실패 아님)
// 호출부가 "지웠다/저장했다"고 착각하지 않게 실패 원인들을 그대로 들고 있음 (경로는 안 담음)
class VaultIoException implements Exception {
  const VaultIoException(this.message, this.failures);
  final String message;
  final List<Object> failures;
  @override
  String toString() => 'VaultIoException: $message (${failures.length})';
}

// 수신 파일 외에 앱에서 유일하게 디스크를 만지는 곳
class Vault {
  // resolveDir는 vault 디렉토리를 고르는 seam (프로덕션은 null = 앱 지원 디렉토리, 테스트는 임시 디렉토리 주입)
  Vault({Future<String> Function()? resolveDir})
    : _resolveDir = resolveDir ?? _defaultDir;

  final Future<String> Function() _resolveDir;

  // PIN 설정 때 시작한 KDF 결과를 세션 동안 재사용함. 디스크엔 키를 안 담음
  String? _pin;
  List<int>? _salt;
  SecretKeyData? _sessionKey;
  Future<void>? _keyReady;
  Object? _keyError;
  int _keyGeneration = 0;
  List<int>? _dchkSalt;
  Future<String>? _dchkReady;

  @visibleForTesting
  int debugKdfCount = 0;
  @visibleForTesting
  SecretKeyData? get debugSessionKey => _sessionKey;

  // duress PIN. 설정돼 있으면 그 PIN으로 load할 때 빈 세션이 뜨고 그 세션의 save는 무시됨
  // 디스크엔 PIN 자체가 아니라 확인용 값(_newDecoyCheck)만 dchk로 담김
  String? _decoyPin;
  bool _decoyMode = false;

  // 파일에서 읽은 dchk 원본. duress PIN이 없을 때 쓰는 난수 placeholder를 저장 간에 안정적으로
  // 유지함 (안 그러면 매 저장마다 바뀌어 "duress 없음"이 티남)
  String? _dchk;
  int _dchkIterations = kVaultPbkdf2Iterations;

  // 옛 dchk 형식 또는 100k 파일을 열었음. 다음 봉인 저장이 현행 형식으로 덮을 때까지 true
  bool _needsRewrite = false;

  final Chacha20 _aead = Chacha20.poly1305Aead();

  // 테스트 seam: 쓰기(path/sealed/tmp)와 로드(read/decrypted/decoy-checked)의 각 단계 경계에서,
  // epoch/decoy/전이 재확인 직전에 호출됨. 테스트가 그 순간에 duress 전이나 erase를 끼워 넣어
  // 어느 단계에서 끼어들어도 아카이브/세션 상태가 안 바뀌는지 결정적으로 검사함. 프로덕션에선 null
  @visibleForTesting
  Future<void> Function(String stage)? debugStageHook;

  // 디스크 작업(저장/삭제) 큐의 꼬리. 다음 작업은 항상 뒤에 붙어 순서대로 돌아서
  // save -> erase -> save가 겹쳐 서로 밟지 않음. 실패한 작업이 꼬리를 끊지 않게 catchError로 감쌈
  Future<void> _ioTail = Future<void>.value();

  // erase/load/unlock마다 증가. 큐에 있던(아직 안 돈) save가 붙잡은 epoch가 현재와 다르면
  // 실행 시 조용히 스킵함: 세션 전이 도중 옛 저장이 실제 archive를 되살리는 걸 막음
  int _epoch = 0;

  // load/unlock이 세션 전이를 시작한 뒤 real/decoy/실패로 확정되기 전까진 true
  // 이 동안의 save는 결과를 모르니 무조건 거부함
  bool _transitioning = false;

  bool get isDecoyMode => _decoyMode;
  bool get needsRewrite => _needsRewrite;

  static Future<String> _defaultDir() => privateAppDir();

  Future<File> _file() async => File(p.join(await _resolveDir(), 'vault.json'));

  Future<bool> isEncrypted() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return false;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map && decoded['enc'] == true;
    } on FormatException {
      return true; // 깨진 파일을 "없는 파일"로 착각해 덮으면 안 됨
    } on FileSystemException {
      return true; // 읽을 수 없는 파일은 잠금 게이트로 보존
    } on MissingPluginException {
      return false;
    }
  }

  Future<VaultSnapshot?> unlock(String pin) => load(pin: pin);

  // null이면 이후 save가 평문으로 씀. duress 세션에선 no-op
  // (강요당해 "새 PIN"을 설정해도 실제 보호 상태는 안 바뀜)
  // duress PIN과 같으면 거부(false). 재시작 뒤처럼 duress 원문이 없을 땐 호출부가
  // isDecoyPin으로 먼저 걸러야 함
  // duress 세션에선 성공한 척 true (거부 문구가 뜨면 duress인 게 티남)
  bool setPin(String? pin) {
    if (_decoyMode) return true;
    if (pin != null && pin == _decoyPin) return false;
    if (!_transitioning) _epoch++;
    _clearKey();
    _pin = pin;
    _salt = pin == null ? null : _randomBytes(16);
    if (pin == null) {
      _decoyPin = null;
      _dchk = null;
      _dchkSalt = null;
      _dchkReady = null;
    } else {
      final generation = _keyGeneration;
      _keyReady = _deriveKey(pin, _salt!).then(
        (key) {
          if (generation == _keyGeneration) {
            _sessionKey = key;
          } else {
            key.destroy();
          }
        },
        onError: (Object error) {
          if (generation == _keyGeneration) _keyError = error;
        },
      );
    }
    return true;
  }

  Future<bool> isDecoyPin(String pin) => _isDecoyPin(pin);

  // 진짜 세션 PIN과 같으면 거부(false). duress 세션에선 no-op(false)
  // null이면 해제되고 다음 저장에서 옛 dchk가 난수로 덮임
  bool setDecoyPin(String? pin) {
    if (_decoyMode) return false;
    if (pin != null && pin == _pin) return false;
    if (!_transitioning) _epoch++;
    _decoyPin = pin;
    _dchk = null;
    _dchkSalt = _randomBytes(16);
    _dchkReady = pin == null ? null : _newDecoyCheck(pin, _dchkSalt!);
    _dchkIterations = kVaultPbkdf2Iterations;
    // 저장 전에 실패해도 처리되지 않은 비동기 오류로 번지지 않게 함
    _dchkReady?.ignore();
    return true;
  }

  // 없거나 깨졌거나 디스크를 못 쓰면 null (호출자는 빈 세션으로 시작)
  // PIN 봉인이면 pin(또는 세션 PIN)이 필요하고 없거나 틀리면 null
  // 구현은 _VaultSession._load로 위임 (private 확장은 라이브러리 밖에서 직접 호출 불가)
  Future<VaultSnapshot?> load({String? pin}) => _load(pin: pin);

  // private 확장 메서드는 라이브러리 밖에서 못 불러서 이 한 줄 위임이 공개 진입점
  Future<void> save(VaultSnapshot snapshot) => _save(snapshot);

  Future<void> erase() => _erase();

  // 잠금 즉시 키를 0으로 덮고 진행 중인 전이와 저장을 무효화함
  void lock() {
    _epoch++;
    _transitioning = false;
    _clearKey();
    _pin = null;
    _salt = null;
    _decoyPin = null;
    _dchk = null;
    _dchkSalt = null;
    _dchkReady = null;
    _dchkIterations = kVaultPbkdf2Iterations;
    _needsRewrite = false;
  }

  void dispose() => lock();
}
