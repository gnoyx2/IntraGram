import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// 설정 › 오픈소스 라이선스(showLicensePage)에 Flutter가 모은 패키지 고지와 함께
// 이 앱의 MIT 라이선스와 THIRD_PARTY_NOTICES(LocalSend Apache-2.0 원문, QR 스캐너 출처)를 띄움
// 저장소 파일을 에셋으로 그대로 실어서 문서와 앱 화면 내용이 갈라지지 않게 함
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'IntraGram',
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'IntraGram',
      'LocalSend',
    ], await rootBundle.loadString('THIRD_PARTY_NOTICES.md'));
  });
}
