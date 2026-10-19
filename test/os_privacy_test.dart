import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/os_privacy.dart';

// 복사본 만료: 모바일은 내용을 안 읽고 native 소유 확인(clearIfOwn)만 부르고,
// Android 백그라운드처럼 확인이 막히면(null) 앱 복귀 때 다시 확인함. native가 없는
// 데스크톱은 내용이 그대로일 때만 지움. 추적한 디코드 이미지는 방출 때 캐시에서 빠짐

class _PendingDecode extends ImageStreamCompleter {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const privacy = MethodChannel('intragram/privacy');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(privacy, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('an expired copy is cleared by the owner check, retried on resume', () {
    final calls = <String>[];
    bool? own; // null: Android 백그라운드라 확인 불가
    messenger.setMockMethodCallHandler(privacy, (call) async {
      calls.add(call.method);
      return call.method == 'clearIfOwn' ? own : null;
    });

    fakeAsync((async) {
      OsPrivacy.copySensitive('secret');
      async.elapse(OsPrivacy.clipboardLifetime - const Duration(seconds: 1));
      expect(calls, ['copySensitive']);

      async.elapse(const Duration(seconds: 1));
      expect(calls, ['copySensitive', 'clearIfOwn']);

      own = true;
      OsPrivacy.onAppResumed();
      async.flushMicrotasks();
      expect(calls, ['copySensitive', 'clearIfOwn', 'clearIfOwn']);

      OsPrivacy.onAppResumed(); // 이미 확인함: 더 안 부름
      async.flushMicrotasks();
      expect(calls, hasLength(3));
    });
  });

  test('without the native channel only our unchanged text is cleared', () {
    String? clip;
    messenger.setMockMethodCallHandler(
      privacy,
      (_) => throw MissingPluginException(),
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clip = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': clip};
      }
      return null;
    });

    fakeAsync((async) {
      OsPrivacy.copySensitive('secret');
      async.elapse(OsPrivacy.clipboardLifetime);
      expect(clip, isEmpty);

      OsPrivacy.copySensitive('again');
      async.flushMicrotasks();
      clip = 'copied in another app';
      async.elapse(OsPrivacy.clipboardLifetime);
      expect(clip, 'copied in another app');
    });
  });

  test('evicting tracked images drops their decodes from the cache', () async {
    final cache = PaintingBinding.instance.imageCache;
    Future<Object> cached(Object owner, Uint8List bytes) async {
      final image = OsPrivacy.trackImage(owner, MemoryImage(bytes));
      final key = await image.obtainKey(ImageConfiguration.empty);
      cache.putIfAbsent(key, _PendingDecode.new);
      expect(cache.containsKey(key), isTrue);
      return key;
    }

    final burned = await cached('burned', Uint8List(8));
    final kept = await cached('kept', Uint8List(8));
    OsPrivacy.evictImages('burned'); // 메시지 소각
    expect(cache.containsKey(burned), isFalse);
    expect(cache.containsKey(kept), isTrue);

    final other = await cached('other', Uint8List(8));
    OsPrivacy.evictTrackedImages(); // 대화방 퇴장
    expect(cache.containsKey(kept), isFalse);
    expect(cache.containsKey(other), isFalse);
  });
}
