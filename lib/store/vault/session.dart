part of '../vault.dart';

extension _VaultSession on Vault {
  // private이라 공개 진입점은 Vault.load의 위임. 전이를 시작하는 순간(첫 await 전, 동기적으로) _epoch를
  // 올리고 _transitioning을 켜서, 이미 큐에 있던 저장이 체크포인트에서 옛 epoch를 보고 스스로 멈추게 함
  // 판독도 저장/삭제와 같은 큐에 태워서 판독 도중 파일이 바뀌거나 전이가 결정된 뒤 옛 세션의 rename이
  // 아카이브를 바꾸는 일을 막음 (큐 앞의 저장은 epoch 체크에서 곧바로 물러나 교착 없음)
  // 오래된 전이가 새 전이(또는 erase)의 flag를 내리지 않게 지금 epoch가 시작 때 캡처한 값과 같을 때만 내림
  Future<VaultSnapshot?> _load({String? pin}) {
    _epoch++;
    _transitioning = true;
    final transitionEpoch = _epoch;
    return _enqueue(
      () => _loadLocked(pin: pin, epoch: transitionEpoch),
    ).whenComplete(() {
      if (_epoch == transitionEpoch) _transitioning = false;
    });
  }

  Future<VaultSnapshot?> _loadLocked({required int epoch, String? pin}) async {
    // 판독 대기/await 중 더 새 전이/erase가 왔으면 결과를 버림 (세션 상태는 안 만짐)
    bool stale() => epoch != _epoch;
    if (stale()) return null;
    SecretKeyData? openedKey;
    try {
      final file = await _file();
      if (stale() || !file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      await debugStageHook?.call('read');
      if (stale() || decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();

      if (map['enc'] == true) {
        final key = pin ?? _pin;
        if (key == null) return null; // 잠김: 호출자가 게이트를 띄움
        final decrypted = await _decrypt(map, key);
        openedKey = decrypted?.key;
        final plain = decrypted?.plain;
        await debugStageHook?.call('decrypted');
        if (stale()) return null;
        if (plain == null) {
          // duress PIN이면 조용히 빈 세션으로 들어감 (진짜 아카이브는 안 읽고 안 건드림)
          final isDecoy = await _matchesDecoy(map, key);
          await debugStageHook?.call('decoy-checked');
          if (stale()) return null;
          if (isDecoy) {
            _decoyMode = true;
            // 진짜 세션의 흔적을 전부 지움 (decoy가 실제 PIN/salt를
            // 참조하거나 나중에 실제 archive를 hydrate할 수단을 안 남김)
            _clearKey();
            _pin = null;
            _decoyPin = null;
            _dchk = null;
            _dchkReady = null;
            _dchkSalt = null;
            _salt = null;
            return const VaultSnapshot(
              settings: VaultSettings(enabled: true, pinProtected: true),
              conversations: <Conversation>[],
              messages: <EphemeralMessage>[],
              transfers: <FileTransfer>[],
            );
          }
          return null; // 틀린 PIN: 파일은 온전함
        }
        final inner = jsonDecode(plain);
        if (inner is! Map) return null;
        final kdf = (map['kdf'] as Map).cast<String, dynamic>();
        final iterations = _requireSupportedIterations(kdf['iter']);
        final dchkIterations = _requireSupportedIterations(
          map['di'] ?? iterations,
        );
        final session = await _migratedDchk(
          map,
          openedKey!,
          base64.decode(kdf['salt'].toString()),
        );
        if (stale()) return null;
        final snapshot = VaultSnapshot.fromJson(inner.cast<String, dynamic>());
        if (iterations != kVaultPbkdf2Iterations ||
            !_constantTimeEquals(
              session.salt,
              base64.decode(kdf['salt'].toString()),
            )) {
          openedKey.destroy();
          openedKey = await _deriveKey(key, session.salt);
          if (stale()) return null;
        }
        final dchkSalt = base64.decode((map['ds'] ?? kdf['salt']).toString());
        _clearKey();
        _sessionKey = openedKey;
        openedKey = null;
        _keyReady = Future<void>.value();
        _pin = key;
        _decoyPin = null;
        _dchkReady = null;
        _dchkSalt = dchkSalt;
        _dchkIterations = dchkIterations;
        // 진짜 PIN이 맞으면 이전에 duress로 들어와 decoyMode였더라도 정상 모드로 되돌림
        // erase는 이 플래그를 못 내리고 오직 진짜 unlock 성공 때만 내림
        _decoyMode = false;
        _salt = session.salt;
        _dchk = session.dchk;
        _needsRewrite =
            session.rewrite || iterations == kVaultLegacyPbkdf2Iterations;
        return snapshot;
      }

      return VaultSnapshot.fromJson(map);
    } on FormatException {
      return null;
    } on MissingPluginException {
      return null;
    } finally {
      openedKey?.destroy();
    }
  }
}
