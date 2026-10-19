import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// intragram/file_source MethodChannel(네이티브 MemoryFileSource)의
// 가짜: 호출을 log에 순서대로 남겨서 open -> read -> close -> release의
// 순서/횟수를 검사함 (소스 id는 s1, s2..., reader id는 r1, r2...)
// readGate를 걸면 read가 그 Future가 끝날 때까지 멈추고(정지한 reader
// 흉내), pickGate/openGate는 pick/open 응답을 늦춰서
// "늦게 도착한 native 결과"를 흉내냄
class FakeFileSourceChannel {
  FakeFileSourceChannel({this.chunk = 4, this.chunksPerFile = 2});

  static const MethodChannel channel = MethodChannel('intragram/file_source');

  // 한 번 read할 때 주는 바이트 수와 파일 하나가 몇 조각인지 (그 뒤 EOF)
  final int chunk;
  final int chunksPerFile;

  // 순서 있는 호출 기록: pick, open:s1, read:r1, close:r1, release:s1, releaseAll
  final List<String> log = <String>[];

  Completer<void>? pickGate;
  Completer<void>? openGate;
  Completer<void>? readGate;

  // release 응답을 늦춤 (진행 중인 release를 흉내)
  Completer<void>? releaseGate;

  // release 호출이 실패하는 소스 id 집합
  final Set<String> failRelease = <String>{};

  int pickCount = 1;

  int _sources = 0;
  int _readers = 0;
  final Map<String, int> _reads = <String, int>{};

  int get fileSize => chunk * chunksPerFile;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, _handle);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  int count(String prefix) => log.where((e) => e.startsWith(prefix)).length;
  int indexOf(String entry) => log.indexOf(entry);

  Future<Object?> _handle(MethodCall call) async {
    final args = call.arguments as Map<Object?, Object?>?;
    switch (call.method) {
      case 'pick':
        log.add('pick');
        await pickGate?.future;
        return [
          for (var i = 0; i < pickCount; i++)
            {'id': 's${++_sources}', 'name': 'f$i.bin', 'size': fileSize},
        ];
      case 'open':
        final id = args!['sourceId']! as String;
        log.add('open:$id');
        await openGate?.future;
        final reader = 'r${++_readers}';
        _reads[reader] = 0;
        return reader;
      case 'read':
        final reader = args!['readerId']! as String;
        log.add('read:$reader');
        await readGate?.future;
        final done = _reads[reader]!;
        if (done >= chunksPerFile) return null;
        _reads[reader] = done + 1;
        return Uint8List.fromList(List<int>.filled(chunk, done + 1));
      case 'close':
        log.add('close:${args!['readerId']}');
        return null;
      case 'release':
        final id = args!['sourceId']! as String;
        log.add('release:$id');
        await releaseGate?.future;
        if (failRelease.contains(id)) {
          throw PlatformException(code: 'release_failed');
        }
        return null;
      case 'releaseAll':
        log.add('releaseAll');
        return null;
    }
    throw MissingPluginException(call.method);
  }
}
