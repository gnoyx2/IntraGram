import 'dart:async';

import 'package:flutter/services.dart';

import 'package:intragram/core/constants.dart';

part 'mobile_file_source/stream.dart';

// intragram/file_source MethodChannel(Android
// MemoryFileSource.kt / iOS MemoryFileSource.swift)의
// Dart 래퍼. 캐시 복사 없이 스트리밍함. 데스크톱엔 채널이 없어서 기존 FilePicker 경로를 씀
final class MobileFileSource {
  MobileFileSource._(this.id, this.name, this.size, this._issuedIn);

  final String id;
  final String name;
  final int size;

  // releaseAll로 세대가 오른 뒤엔 이전 세대 소스는 못 씀. 패닉/종료 중 늦게 도착한
  // pick/open 결과가 새 세션에 스며드는 걸 막음
  final int _issuedIn;

  static int _generation = 0;

  static const MethodChannel _channel = MethodChannel('intragram/file_source');

  // release가 멱등이라 두 번째 호출은 같은 Future를 돌려줌
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
      // releaseAll이 pick 도중 실행됨. 늦게 도착한 결과는 이미 끝난 세션 것이라 버리고 native 권한도 놓음
      await releaseEach(picked);
      return const <MobileFileSource>[];
    }
    return picked;
  }

  // kMobileFileReadChunkBytes씩, Dart가 요청할
  // 때만 native가 읽음 (무제한 EventChannel 버퍼링 없음)
  // 재시도는 같은 id로 다시 부르면 native가 새 reader를 엶
  Stream<Uint8List> openRead() => _openMobileFileSourceRead(this);

  // 전송이 끝났거나 다시 안 읽을 게 확실할 때만 호출 (멱등)
  // 재시도 가능한 실패에선 같은 소스로 reader를 다시 열어야 해서 부르면 안 됨
  Future<void> release() =>
      _releasing ??= _channel.invokeMethod<void>('release', {'sourceId': id});

  // 제안되지 않을 소스들의 native 권한을 전부 놓음
  // 개별 실패는 삼켜서 호출부의 더 큰 오류(원래 예외)를 가리지 않음
  static Future<void> releaseEach(Iterable<MobileFileSource> sources) =>
      Future.wait(
        sources.map(
          (source) =>
              source.release().then<void>((_) {}, onError: (Object _) {}),
        ),
      );

  // 패닉 소각용. iOS는 security-scoped 자원을 즉시 해제하고 Android는 열린 스트림을 즉시 close함
  // 세대를 올려서 진행 중이던 pick/open이 나중에 끝나도 새 소스/reader를 등록하지 않고 바로 닫음
  // MissingPluginException(채널 없는 플랫폼/테스트)은 성공 취급. 여기서 멎으면 뒤의 secureWipe가 안 불림
  // 진짜 native 실패(PlatformException)는 던져서 executePanicWipe의 단계별 실패 수집으로 넘김
  static Future<void> releaseAll() async {
    _generation++; // 동기 증가: 이후 도착하는 pick/open 결과는 전부 무효
    try {
      await _channel.invokeMethod<void>('releaseAll');
    } on MissingPluginException {
      // 네이티브 채널 없는 데스크톱/테스트 환경용 폴백
    }
  }
}
