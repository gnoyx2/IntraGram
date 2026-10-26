import 'package:flutter/material.dart';

// 홈 신원 카드와 피어 목록이 같은 기기를 다른 아이콘으로 그리지 않게 한곳에 둠
IconData platformIcon(String platform) => switch (platform) {
  'iOS' => Icons.phone_iphone,
  'iPadOS' => Icons.tablet_mac,
  'macOS' => Icons.laptop_mac,
  'Android' => Icons.android,
  'Windows' => Icons.window,
  'Linux' => Icons.terminal,
  'Web' => Icons.language,
  _ => Icons.devices,
};
