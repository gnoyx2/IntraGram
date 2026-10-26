import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:intragram/core/target_platform.dart';

// 앱이 비활성/숨김일 때 화면 전체를 블러로 덮음. 앱 전환기 스냅샷용 native 커버
// (Android FLAG_SECURE, iOS AppDelegate 불투명 커버)가 못 막는 경우의 보조 수단임.
// 데스크톱은 포커스만 잃어도 inactive라 hidden/paused에서만 덮음
class PrivacyShield extends StatefulWidget {
  const PrivacyShield({required this.child, super.key});

  final Widget child;

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield> {
  late final AppLifecycleListener _listener;
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: _onStateChange);
  }

  void _onStateChange(AppLifecycleState state) {
    final obscured = switch (state) {
      AppLifecycleState.resumed || AppLifecycleState.detached => false,
      AppLifecycleState.inactive => isMobileTarget,
      AppLifecycleState.hidden || AppLifecycleState.paused => true,
    };
    if (obscured != _obscured) setState(() => _obscured = obscured);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_obscured)
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.7),
            ),
          ),
        ),
    ],
  );
}
