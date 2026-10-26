import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;

import 'package:intragram/core/private_dir.dart';

// 기기 이름 저장(identity.json). 대화 내용이 아니라 vault와 따로 켜고 끔. 사용자가 저장을 골라야만 파일이 생김
class IdentityStore {
  const IdentityStore({Future<String> Function()? resolveDir})
    : _resolveDir = resolveDir ?? _defaultDir;

  final Future<String> Function() _resolveDir;

  static Future<String> _defaultDir() => privateAppDir();

  Future<File> _file() async =>
      File(p.join(await _resolveDir(), 'identity.json'));

  // 없거나 깨졌으면 null (호출부는 랜덤 이름으로 감)
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

  // .tmp에 쓰고 rename함 (도중에 비정상 종료돼도 기존 파일이 보존됨)
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
      // 권한·디스크 문제 시 저장을 건너뜀 (편의 기능임)
    } on MissingPluginException {
      // 플랫폼 채널이 없는 테스트 환경임
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
          // 없는 파일만 성공으로 침. 다른 실패는 둘 다 시도한 뒤 던짐 (패닉이 실패를 성공처럼 보고하면 안 됨)
          if (e.osError?.errorCode != 2 && e.osError?.errorCode != 3) {
            failure ??= e;
          }
        }
      }
      if (failure != null) throw failure;
    } on MissingPluginException {
      // 테스트 환경 (플랫폼 채널 없음)
    }
  }
}
