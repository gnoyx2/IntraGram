import 'dart:async';

import 'package:flutter/services.dart';

import 'package:intragram/core/constants.dart';

part 'mobile_file_source/stream.dart';

// intragram/file_source 채널(Android MemoryFileSource.kt, iOS MemoryFileSource.swift)의 Dart 쪽. 캐시 복사 없이 스트리밍함.
// 데스크톱은 채널이 없어 FilePicker 경로를 씀
final class MobileFileSource {
  MobileFileSource._(this.id, this.name, this.size, this._issuedIn);

  final String id;
  final String name;
  final int size;

  // releaseAll로 세대가 오른 뒤엔 옛 세대 소스는 못 씀: 패닉·종료 중 늦게 온 pick·open 결과가 새 세션에 스며드는 걸 막음
  final int _issuedIn;

  static int _generation = 0;

  static const MethodChannel _channel = MethodChannel('intragram/file_source');

  Future<void>? _releasing;

  // 메타데이터만 받고 바이트는 openRead 때 읽음. 취소하면 빈 리스트
  static Future<List<MobileFileSource>> pick({bool imagesOnly = false}) async {
    final generation = _generation;
    final raw = await _channel.invokeMethod<List<Object?>>('pick', {
      'imagesOnly': imagesOnly,
    });
    if (raw == null) return const <MobileFileSource>[];
    final picked = raw
        .whereType<Map<Object?, Object?>>()
        .map(
          (m) => MobileFileSource._(
            m['id']! as String,
            m['name']! as String,
            (m['size']! as num).toInt(),
            generation,
          ),
        )
        .toList();
    if (generation != _generation) {
      // pick 도중 releaseAll이 돌았음: 끝난 세션 결과라 버리고 네이티브 권한도 놓음
      await releaseEach(picked);
      return const <MobileFileSource>[];
    }
    return picked;
  }

  // Dart가 달라고 할 때만 kMobileFileReadChunkBytes씩 읽음. 재시도는 다시 부르면 새 reader가 열림
  Stream<Uint8List> openRead() => _openMobileFileSourceRead(this);

  // 다시 안 읽을 게 확실할 때만 부름 (재시도할 실패면 같은 소스로 reader를 다시 열어야 해서 부르면 안 됨)
  Future<void> release() =>
      _releasing ??= _channel.invokeMethod<void>('release', {'sourceId': id});

  // 제안 안 할 소스들의 네이티브 권한을 다 놓음. 개별 실패는 삼켜서 호출부의 원래 예외를 안 가림
  static Future<void> releaseEach(Iterable<MobileFileSource> sources) =>
      Future.wait(
        sources.map(
          (source) =>
              source.release().then<void>((_) {}, onError: (Object _) {}),
        ),
      );

  // 패닉용: iOS는 security-scoped 자원, Android는 열린 스트림을 바로 닫음. 세대를 올려서 진행 중이던 pick·open이 나중에 끝나도
  // 등록 안 되게 함. 채널 없는 환경은 성공으로 치고 진짜 네이티브 실패만 던짐
  static Future<void> releaseAll() async {
    _generation++; // 동기로 올림: 뒤에 오는 결과는 전부 무효
    try {
      await _channel.invokeMethod<void>('releaseAll');
    } on MissingPluginException {
      // 채널 없는 데스크톱·테스트
    }
  }
}
