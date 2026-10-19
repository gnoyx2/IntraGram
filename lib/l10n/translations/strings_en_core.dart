import 'strings_en_a11y.dart';
import 'strings_en_common.dart';
import 'strings_en_connect.dart';
import 'strings_en_privacy.dart';
import 'strings_en_room.dart';
import 'strings_en_settings.dart';

// 도메인별 테이블(Common / Room / Settings / A11y / Connect)을 합친 코어. S가 kStringsEnChat과 합쳐 씀
const Map<String, String> kStringsEnCore = {
  ...kStringsEnCommon,
  ...kStringsEnRoom,
  ...kStringsEnSettings,
  ...kStringsEnA11y,
  ...kStringsEnConnect,
  ...kStringsEnPrivacy,
};
