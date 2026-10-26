import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'display_regions.dart';
import 'windows_clipboard.dart';

part 'os_privacy_accessibility.dart';

// 클립보드·디코드 이미지·접근성은 같은 네이티브 채널로 처리함.
abstract final class OsPrivacy {
  static const MethodChannel _channel = MethodChannel('intragram/privacy');
  static const Duration clipboardLifetime = Duration(seconds: 60);
  static final reduceTransparency = _PrivacyAccessibility.reduceTransparency;
  static final reduceMotion = _PrivacyAccessibility.reduceMotion;
  static final highContrast = _PrivacyAccessibility.highContrast;
  static bool? cachedIsPad;
  static bool _localNetworkRequested = false;
  static Future<bool>? _localNetworkPending;

  static Future<void> refreshDisplayRegions() =>
      _PrivacyAccessibility.refreshDisplayRegions();
  static Future<void> refreshReduceTransparency() =>
      _PrivacyAccessibility.refresh('reduceTransparency');
  static Future<void> refreshAccessibility() =>
      _PrivacyAccessibility.refreshAll();

  // 권한 요청은 세션당 한 번만 보냄. 거부 뒤 자동 재탐색은 설정 변경 여부만 확인함
  static Future<bool> localNetworkPermission() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _localNetworkPending ??= _readLocalNetworkPermission().whenComplete(
      () => _localNetworkPending = null,
    );
  }

  static Future<bool> _readLocalNetworkPermission() async {
    final method = _localNetworkRequested
        ? 'checkLocalNetworkPermission'
        : 'requestLocalNetworkPermission';
    _localNetworkRequested = true;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  static Timer? _clipboardTimer;
  // 만료 확인을 백그라운드라 못 했으면 앱 복귀 때 다시 함
  static bool _clipboardCheckPending = false;
  static final Map<Object, Set<Object>> _imageKeys = {};

  // ResizeImage 키까지 적어 둬야 실제 디코드 캐시가 빠짐
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

  // 대화방 나갈 때: 거기서 디코드한 사진을 소각된 것까지 다 캐시에서 뺌
  static void evictTrackedImages() {
    for (final owner in _imageKeys.keys.toList()) {
      evictImages(owner);
    }
  }

  // Android 13+ 민감 표시, iOS localOnly·macOS currentHostOnly(Universal Clipboard 차단), Windows는 기록·클라우드 동기화에서 제외함.
  // clipboardLifetime 뒤에도 이 복사본이면 지움
  static Future<void> copySensitive(String text) async {
    _clipboardTimer?.cancel();
    _clipboardCheckPending = false;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
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

  // iOS만: UIDevice로 iPad인지 물음 (창 크기 짐작은 Split View 1/3로 켜면 틀림). 모르면 null을 반환함
  static Future<bool?> isPad() async {
    if (cachedIsPad != null) return cachedIsPad;
    if (kIsWeb || !Platform.isIOS) return null;
    try {
      return cachedIsPad = await _channel.invokeMethod<bool>('isPad');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  // 백그라운드라 못 지운 만료 복사본을 복귀 때 확인함
  static Future<void> onAppResumed() async {
    if (_clipboardCheckPending) await _clearOwnCopy();
  }

  // 내용은 안 읽고 네이티브가 이 앱 복사본인지만 봄 (Android 라벨, iOS changeCount). 다른 앱의 내용을 읽으면 iOS 붙여넣기 허용 창,
  // Android 12+ 토스트가 뜸. null이면 Android 백그라운드 상태라 복귀 때 다시 확인함
  static Future<void> _clearOwnCopy() async {
    _clipboardCheckPending = false;
    try {
      final result = await _channel.invokeMethod<bool>('clearIfOwn');
      _clipboardCheckPending = result == null;
    } on PlatformException {
      // 네이티브 호출이 실패하면 다른 앱의 내용일 수 있어 건드리지 않음
    } on MissingPluginException {
      // 엔진 종료·테스트라 채널이 없음
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

  // 패닉 전용. Linux는 다른 앱의 복사본을 보호하려고 우리 소유일 때만 비움.
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

  // 붙여넣기 버튼용으로 이미지·파일이 있는지 종류만 물음. 내용을 읽으면 iOS 16+ 허용 창, macOS 15.4+ 경고,
  // Android 12+ 알림이 뜨고 Windows 플러그인은 임시 BMP를 씀. null이면 네이티브 채널이 없음
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

  static void clearDecodedImages() {
    _imageKeys.clear();
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }
}
