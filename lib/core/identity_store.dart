import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;

import 'package:intragram/core/private_dir.dart';

// Vault와 별개 파일(identity.json). 기기 이름은 대화 내용이 아니라서 vault 옵트인과
// 독립적으로 켜고 꺼야 함. 사용자가 "저장"을 골랐을 때만 파일이 생김
class IdentityStore {
  const IdentityStore({Future<String> Function()? resolveDir})
    : _resolveDir = resolveDir ?? _defaultDir;

  final Future<String> Function() _resolveDir;

  static Future<String> _defaultDir() => privateAppDir();

  Future<File> _file() async =>
      File(p.join(await _resolveDir(), 'identity.json'));

  // 없거나 깨졌거나 디스크를 못 쓰면 null (호출자는 랜덤 alias로 진행)
  Future<String?> loadAlias() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded['alias'] as String? : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  // .tmp에 쓰고 rename (중간에 죽어도 기존 파일 보존)
  Future<void> saveAlias(String alias) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(<String, String>{'alias': alias}),
        flush: true,
      );
      await tmp.rename(file.path);
    } on FileSystemException {
      // 권한 없음/디스크 꽉 참: 옵트인 편의 기능이라 조용히 포기
    } on MissingPluginException {
      // 플랫폼 채널 없는 테스트 환경용 폴백
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      FileSystemException? failure;
      for (final target in [file, tmp]) {
        try {
          await target.delete();
        } on FileSystemException catch (e) {
          // 이미 없는 파일만 성공 처리. 패닉 소각이 권한/디스크 오류를 성공처럼 보고하지 않게
          // 다른 실패는 두 파일 다 시도한 뒤 전파
          if (e.osError?.errorCode != 2 && e.osError?.errorCode != 3) {
            failure ??= e;
          }
        }
      }
      if (failure != null) throw failure;
    } on MissingPluginException {
      // 플랫폼 채널 없는 테스트 환경용 폴백
    }
  }
}
