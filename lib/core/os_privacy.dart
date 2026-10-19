import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'windows_clipboard.dart';

// OS 쪽으로 새는 흔적(스냅샷, 클립보드, 디코드된 이미지) 정리
// native 채널은 Android(MainActivity)·iOS(AppDelegate)·macOS(MainFlutterWindow), Windows는 user32 FFI,
// Linux만 Flutter 기본 API로 대체 (클립보드 관리자가 복사본을 기록할 수 있음)
abstract final class OsPrivacy {
  static const MethodChannel _channel = MethodChannel('intragram/privacy');

  static const Duration clipboardLifetime = Duration(seconds: 60);

  static Timer? _clipboardTimer;
  // 만료 확인을 백그라운드라 못 했으면 앱 복귀 때 다시 함
  static bool _clipboardCheckPending = false;
  static final Map<Object, Set<Object>> _imageKeys = {};

  // ResizeImage 키까지 기록해서 실제 디코드 캐시를 제거함
  static ImageProvider trackImage(Object owner, ImageProvider image) {
    final keys = _imageKeys.putIfAbsent(owner, () => <Object>{});
    unawaited(
      image.obtainKey(ImageConfiguration.empty).then((key) {
        if (identical(_imageKeys[owner], keys)) keys.add(key);
      }),
    );
    return image;
  }

  static void evictImages(Object? owner) {
    final keys = _imageKeys.remove(owner);
    if (keys == null) return;
    for (final key in keys) {
      PaintingBinding.instance.imageCache.evict(key);
    }
  }

  // 대화방을 나갈 때: 그 방에서 디코드한 사진을 소각된 것까지 전부 내보냄
  static void evictTrackedImages() {
    for (final owner in _imageKeys.keys.toList()) {
      evictImages(owner);
    }
  }

  // Android 13+ 민감 표시(미리보기 숨김), iOS localOnly·macOS currentHostOnly(Universal Clipboard 차단),
  // Windows는 클립보드 기록·클라우드 동기화 제외 형식. clipboardLifetime 뒤 아직 이 복사본이면 지움
  static Future<void> copySensitive(String text) async {
    _clipboardTimer?.cancel();
    _clipboardCheckPending = false;
    if (!kIsWeb &&
        Platform.isWindows &&
        WindowsClipboard.setPrivateText(text)) {
      _clipboardTimer = Timer(clipboardLifetime, WindowsClipboard.clearIfOwn);
      return;
    }
    try {
      await _channel.invokeMethod<void>('copySensitive', text);
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
      _clipboardTimer = Timer(clipboardLifetime, () {
        unawaited(_clearDesktopCopy(text));
      });
      return;
    }
    _clipboardTimer = Timer(clipboardLifetime, () {
      unawaited(_clearOwnCopy());
    });
  }

  // iOS만: UIDevice가 iPad인지. 창 크기 짐작은 Split View 1/3·Slide Over로 켜면 틀림
  // (이 채널은 iOS 쪽 기기 질의도 같이 받음). 모르면 null
  static Future<bool?> isPad() async {
    if (kIsWeb || !Platform.isIOS) return null;
    try {
      return await _channel.invokeMethod<bool>('isPad');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  // macOS만: 시스템 설정의 '동작 줄이기'. macOS 임베더는 이 값을 Flutter에 안 넘김
  // 다른 OS는 MediaQuery.disableAnimations로 이미 들어와서 false
  static Future<bool> macReduceMotion() async {
    if (kIsWeb || !Platform.isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('reduceMotion') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  // 앱 복귀 때 호출: 백그라운드라 못 지운 만료 복사본을 이제 확인함
  static Future<void> onAppResumed() async {
    if (_clipboardCheckPending) await _clearOwnCopy();
  }

  // 내용을 읽지 않고 native가 소유만 확인함 (Android 라벨, iOS changeCount)
  // 다른 앱 내용을 읽으면 iOS 붙여넣기 허용 팝업, Android 12+ 접근 토스트가 뜸
  // null = Android 백그라운드라 확인 불가 -> 복귀 때 재시도
  static Future<void> _clearOwnCopy() async {
    _clipboardCheckPending = false;
    try {
      final result = await _channel.invokeMethod<bool>('clearIfOwn');
      _clipboardCheckPending = result == null;
    } on PlatformException {
      // native 실패면 남의 내용일 수 있어 건드리지 않음
    } on MissingPluginException {
      // 채널이 사라진 뒤(엔진 종료/테스트)라 확인할 수 없음
    }
  }

  // native 채널 없는 데스크톱: 내용이 그대로일 때만 지움
  static Future<void> _clearDesktopCopy(String text) async {
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } on PlatformException {
      // 읽기가 막히면 다른 앱 내용을 건드리지 않음
    }
  }

  // 클립보드 내용이 앱 것인지 모르므로 무조건 비움 (패닉 전용)
  static Future<void> clearClipboard() async {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
    _clipboardCheckPending = false;
    try {
      await _channel.invokeMethod<void>('clearClipboard');
    } on MissingPluginException {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  // 붙여넣기 버튼 표시용으로 클립보드에 이미지·파일이 있는지 종류만 물음. 내용을 읽으면 iOS 16+ 붙여넣기
  // 허용 창, macOS 15.4+ 경고, Android 12+ 접근 알림이 뜨고 Windows 플러그인은 임시 BMP를 씀
  // null이면 이 플랫폼은 종류만 물을 방법이 없음 (Linux)
  static Future<({bool image, bool files})?> clipboardKinds() async {
    if (!kIsWeb && Platform.isWindows) return WindowsClipboard.kinds();
    try {
      final kinds = await _channel.invokeMapMethod<String, bool>(
        'clipboardKinds',
      );
      return (image: kinds?['image'] ?? false, files: kinds?['files'] ?? false);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return (image: false, files: false);
    }
  }

  // 디코드된 썸네일/이미지가 ImageCache에 남지 않게 비움
  static void clearDecodedImages() {
    _imageKeys.clear();
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }
}
