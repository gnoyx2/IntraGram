part of '../vault.dart';

extension _VaultIo on Vault {
  // private 확장이라 공개 진입점은 Vault.save의 한 줄 위임. .tmp에 쓰고 rename해서
  // 중간에 죽어도 기존 파일이 안 깨지고, 디스크를 못 쓰면 조용히 포기함 (RAM 상태는 그대로)
  // 보관 + PIN 보호 + 세션 PIN이 있으면 봉인해서 씀. 보호 모드인데 세션 PIN이 없으면 평문으로 자동 전환하지
  // 않고 VaultLockedException. _ioTail에 줄을 서서 앞선 저장/삭제가 끝난 뒤에만 파일을 건드림
  Future<void> _save(VaultSnapshot snapshot) {
    if (_transitioning) {
      // load/unlock이 진짜/duress/실패 중 뭐가 될지 확정 전이라 이 동안의 저장은 안전하게 처리 못 해서 거부
      return Future<void>.error(
        const VaultLockedException(
          'vault session is transitioning (load/unlock in progress)',
        ),
      );
    }
    if (_decoyMode) return Future<void>.value(); // duress 편집은 디스크에 절대 안 감
    if (!snapshot.settings.enabled) return Future<void>.value();
    final ready = _keyReady;
    if (snapshot.settings.pinProtected && ready == null) {
      return Future<void>.error(
        const VaultLockedException(
          'vault is PIN-protected but no session PIN is set',
        ),
      );
    }
    final epoch = _epoch;
    return _enqueue(() => _writeLocked(snapshot, epoch: epoch, ready: ready));
  }

  Future<void> _writeLocked(
    VaultSnapshot snapshot, {
    required int epoch,
    required Future<void>? ready,
  }) async {
    // epoch 불일치뿐 아니라 decoy/transitioning도 매 체크포인트마다 다시 봄. epoch만으로 충분하지만
    // "decoy 세션은 절대 안 씀"이 epoch 부기의 부작용이 아니라 이 함수의 불변식으로 보이게 함
    bool stale() => epoch != _epoch || _decoyMode || _transitioning;
    if (stale()) return;
    // 이 저장이 만든 임시 파일. 이름은 고정이지만 큐가 직렬화해서 한 번에 한 저장만 쥠
    // rename으로 못 넘기고 끝나면(실패든 늦게 온 stale이든) finally가 이 저장 소유분을 치움
    // (실패 시 봉인된 내용이 든 .tmp가 남지 않게)
    File? tmp;
    var renamed = false;
    Object? failure;
    try {
      final file = await _file();
      await debugStageHook?.call('path');
      if (stale()) return; // 경로 조회(await)하는 동안 늦게 옴
      await file.parent.create(recursive: true);
      tmp = File('${file.path}.tmp');
      final sealed = snapshot.settings.pinProtected;
      if (sealed) {
        await ready;
        if (stale()) return;
        if (_keyError != null) throw _keyError!;
        if (_sessionKey == null) {
          throw const VaultLockedException('no session key');
        }
        final dchk = await _dchkReady;
        if (stale()) return;
        if (dchk != null) _dchk = dchk;
      }
      final payload = sealed
          ? await _encrypt(jsonEncode(snapshot.toJson()), _sessionKey!)
          : jsonEncode(snapshot.toJson());
      await debugStageHook?.call('sealed');
      if (stale()) return; // 봉인(await)하는 동안 늦게 옴
      await tmp.writeAsString(payload, flush: true);
      await debugStageHook?.call('tmp');
      // rename 직전에 stale이면 방금 쓴 임시 파일은 finally가
      // 치우고 rename은 절대 안 함 (지운 뒤 되살아난 것처럼 보이면 안 됨)
      if (stale()) return;
      await tmp.rename(file.path);
      renamed = true;
      if (sealed) _needsRewrite = false;
    } on MissingPluginException {
      // 플랫폼 채널 없는 테스트 환경: 이 환경엔 디스크가 없다는 뜻
    } on Object catch (e) {
      // 권한 없음/디스크 꽉 참 같은 진짜 실패는 삼키지 않고 호출자에게 전달 (호출부가 화면에 드러냄)
      failure = e;
      rethrow;
    } finally {
      final leftover = tmp;
      if (leftover != null && !renamed) {
        try {
          await _deleteIfExists(leftover);
        } on FileSystemException {
          // 원래 실패가 이미 전파 중이면 그쪽이 우선. 저장 자체는 성공적으로 건너뛴(stale) 경우엔
          // 치우지 못한 임시 파일을 그대로 드러냄
          if (failure == null) rethrow;
        }
      }
    }
  }

  // 소거는 duress 여부와 무관하게 실제 파일까지 지움
  // _decoyMode는 이 메서드가 못 내림: 진짜 PIN으로 load가 성공했을 때만 내려감
  Future<void> _erase() {
    lock();
    return _enqueue(_eraseLocked);
  }

  // 파일과 임시 파일을 둘 다 지워 봄 (하나가 실패해도 나머지는 시도). 이미 없는 건 무해하고,
  // 권한 거부/디스크 오류는 VaultIoException으로 모아 던짐
  // (패닉/보관 끄기가 "지웠다"고 믿는데 파일이 남아 있으면 안 됨)
  Future<void> _eraseLocked() async {
    final failures = <Object>[];
    try {
      final file = await _file();
      for (final target in [file, File('${file.path}.tmp')]) {
        try {
          await _deleteIfExists(target);
        } on FileSystemException catch (e) {
          failures.add(e);
        }
      }
    } on MissingPluginException {
      // 플랫폼 채널 없는 테스트 환경: 지울 디스크가 없음
    }
    if (failures.isNotEmpty) {
      throw VaultIoException('vault erase failed', failures);
    }
  }

  // action을 내부 꼬리 뒤에 붙여 앞선 저장/삭제/판독이 끝난 뒤에만 실행되게 함. 반환값은 action의 결과 그대로이고,
  // 그 오류가 _ioTail을 끊어 다음 큐 항목이 영원히 안 도는 일이 없게 별도 브랜치에서 삼킴
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _ioTail.then((_) => action());
    _ioTail = result.then((_) {}, onError: (_) {});
    return result;
  }
}

// 이미 없으면(다른 작업이 먼저 지웠거나 애초에 없음) 성공 처리하고,
// 권한 거부/디스크 오류 등 진짜 실패는 던져서 호출부가 삼키지 않게 함
Future<void> _deleteIfExists(File file) async {
  try {
    await file.delete();
  } on FileSystemException catch (e) {
    // POSIX ENOENT(2), Windows ERROR_FILE_NOT_FOUND(2)/ERROR_PATH_NOT_FOUND(3)
    const notFoundCodes = {2, 3};
    if (notFoundCodes.contains(e.osError?.errorCode)) return;
    rethrow;
  }
}
