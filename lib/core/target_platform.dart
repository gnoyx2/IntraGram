import 'package:flutter/foundation.dart';

// 폰·태블릿(Android·iOS) 전용 화면 요소(카메라 스캔, 사진 보관함, 공유 시트) 표시 여부를 결정함.
// dart:io 말고 defaultTargetPlatform이라 기기에선 같은 값이고 위젯 테스트는 호스트와 상관없이 고를 수 있음 (OS API 호출은 dart:io로 가름)
bool get isMobileTarget =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
