import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// 설정 › 오픈소스 라이선스에 Flutter 패키지 고지와 함께 이 앱 LICENSE와 THIRD_PARTY_NOTICES를 띄움.
// 저장소 파일을 에셋으로 그대로 실어서 문서와 앱 화면이 안 갈라짐
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
