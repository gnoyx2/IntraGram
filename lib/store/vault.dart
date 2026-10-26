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

// copyWith에서 '안 줌'과 명시적 null을 가르는 센티널 (langOverride를 null로 되돌리려고)
const Object _unset = Object();

// 보호 모드인데 세션 PIN이 없어서 저장을 거부함 (평문으로 몰래 안 바꿈)
class VaultLockedException implements Exception {
  const VaultLockedException(this.message);
  final String message;
  @override
  String toString() => 'VaultLockedException: $message';
}

// 삭제·쓰기 실패 (이미 없는 건 실패 아님). 호출부가 지웠다고 착각하지 않게 원인을 들고 있음 (경로는 안 담음)
class VaultIoException implements Exception {
  const VaultIoException(this.message, this.failures);
  final String message;
  final List<Object> failures;
  @override
  String toString() => 'VaultIoException: $message (${failures.length})';
}

// 사용자가 켠 보관소 파일(vault.json)을 읽고 씀
class Vault {
  // resolveDir: 폴더를 고르는 seam (프로덕션은 앱 비공개 폴더, 테스트는 임시 폴더)
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

  // 파일에서 읽은 dchk. duress가 없을 때의 난수 자리값도 저장마다 그대로 둠 (바뀌면 duress가 없는 게 티남)
  String? _dchk;
  int _dchkIterations = kVaultPbkdf2Iterations;

  // 옛 dchk 형식 또는 100k 파일을 열었음. 다음 봉인 저장이 현행 형식으로 덮을 때까지 true
  bool _needsRewrite = false;

  final Chacha20 _aead = Chacha20.poly1305Aead();

  // 테스트 seam: 저장·로드의 단계마다 재확인 직전에 불림. 테스트가 그 순간 duress 전이나 erase를 끼워 봄 (프로덕션은 null)
  @visibleForTesting
  Future<void> Function(String stage)? debugStageHook;

  // 디스크 작업 큐의 꼬리. 다 줄 서서 돌아서 저장·삭제가 겹쳐 밟지 않음
  Future<void> _ioTail = Future<void>.value();

  // erase·load·unlock마다 오름. 큐에서 기다리던 저장이 잡은 값과 다르면 건너뜀 (전이 중 옛 저장이 아카이브를 되살리면 안 됨)
  int _epoch = 0;

  // load·unlock이 진짜·duress·실패로 정해지기 전까지 true. 이 동안 저장은 다 거부
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

  // null이면 이후 평문으로 저장. duress PIN과 같으면 false (재시작 뒤엔 원문이 없어서 호출부가 isDecoyPin으로 먼저 거를 것).
  // duress 세션에선 아무것도 안 바꾸고 성공한 척 true (거부가 뜨면 duress인 게 티남)
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

  // 없거나 깨졌거나 못 읽으면 null (빈 세션으로 시작). 봉인이면 PIN이 맞아야 함
  Future<VaultSnapshot?> load({String? pin}) => _load(pin: pin);

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
