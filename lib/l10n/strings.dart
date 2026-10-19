import 'package:flutter/widgets.dart';

import 'package:intragram/store/models.dart';
import 'translations/strings_en_core.dart';
import 'translations/strings_en_chat.dart';
import 'translations/strings_ko_core.dart';
import 'translations/strings_ko_chat.dart';
import 'translations/strings_ko_connect.dart';
import 'translations/strings_ko_privacy.dart';
import 'translations/strings_ko_settings.dart';

// en이 기준 언어. 새 키는 항상 영어 테이블(kStringsEn*)에 먼저 추가
enum AppLang { en, ko }

// 코드 생성/intl 없이 Map 두 개로 관리. 사용 예:
//   S.of(context).t('sys.memberJoined', {'alias': name})   // {alias} 치환
// S.of(context).plural(n, one: '{n} person',
// other: '{n} people') LocaleScope가 없으면 영어로 폴백
class S {
  const S(this.lang);

  final AppLang lang;

  static S of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleScope>()?.strings ??
      const S(AppLang.en);

  // 없으면 영어, 영어에도 없으면 key 그대로. args의 {name} 자리표시자를 치환
  String t(String key, [Map<String, String>? args]) {
    var value = _table[lang]?[key] ?? _en[key] ?? key;
    if (args != null) {
      args.forEach((k, v) => value = value.replaceAll('{$k}', v));
    }
    return value;
  }

  // 영어만 단/복수를 가름. 한국어는 항상 other. 템플릿의 {n}을 count로 치환
  String plural(int count, {required String one, required String other}) {
    final template = lang == AppLang.en && count == 1 ? one : other;
    return template.replaceAll('{n}', '$count');
  }

  String monthName(int month) {
    const en = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return lang == AppLang.ko ? '$month' : en[(month - 1) % 12];
  }

  // 오늘·어제, 올해면 월·일, 아니면 연도까지 (대화의 날짜 구분선과 검색 결과가 같이 씀)
  // 날짜 차이는 UTC 자정끼리 셈: 로컬 자정끼리는 서머타임 날에 23·25시간이라 하루가 어긋남
  String dayLabel(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final days = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;
    if (days == 0) return t('date.today');
    if (days == 1) return t('date.yesterday');
    return t(local.year == now.year ? 'date.monthDay' : 'date.monthDayYear', {
      'month': monthName(local.month),
      'day': '${local.day}',
      'year': '${local.year}',
    });
  }

  // OS 시계가 24시간제가 아니면 언어 관례대로 오전/오후를 붙인 12시간제 (오후 3:05 / 3:05 PM)
  String clock(DateTime time, {required bool use24h}) {
    final local = time.toLocal();
    final mm = local.minute.toString().padLeft(2, '0');
    if (use24h) return '${local.hour.toString().padLeft(2, '0')}:$mm';
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final pm = local.hour >= 12;
    return lang == AppLang.ko
        ? '${pm ? '오후' : '오전'} $h:$mm'
        : '$h:$mm ${pm ? 'PM' : 'AM'}';
  }

  // 키 대칭·사용 검사(test/l10n_parity_test.dart)용
  @visibleForTesting
  static Map<String, String> tableOf(AppLang lang) => _table[lang]!;

  static const Map<AppLang, Map<String, String>> _table = {
    AppLang.en: _en,
    AppLang.ko: _ko,
  };

  static const Map<String, String> _en = {...kStringsEnCore, ...kStringsEnChat};

  static const Map<String, String> _ko = {
    ...kStringsKoCore,
    ...kStringsKoChat,
    ...kStringsKoConnect,
    ...kStringsKoPrivacy,
    ...kStringsKoSettings,
  };
}

class LocaleScope extends InheritedWidget {
  const LocaleScope({required this.lang, required super.child, super.key});

  final AppLang lang;

  S get strings => S(lang);

  @override
  bool updateShouldNotify(LocaleScope oldWidget) => oldWidget.lang != lang;
}

// 방 제목은 네트워크 계층이 저장한 영어 이름(roomTitle) 대신 인원수로 화면 언어에 맞춰 만듦
extension ConversationTitle on S {
  String title(Conversation c) {
    if (!c.isRoom) return c.peerAlias;
    return c.memberCount <= 2
        ? t('chat.room')
        : t('chat.roomPeople', {'n': '${c.memberCount}'});
  }
}

extension SystemEventText on S {
  String describe(SystemEvent event) {
    final args = event.alias == null
        ? null
        : <String, String>{'alias': event.alias!};
    return switch (event.kind) {
      SystemEventKind.disconnected => t('sys.disconnected'),
      SystemEventKind.encrypted => t('sys.encrypted'),
      SystemEventKind.encryptedAgain => t('sys.encryptedAgain'),
      SystemEventKind.verifiedAgain => t('sys.verifiedAgain'),
      SystemEventKind.becameRoom => t('sys.becameRoom'),
      SystemEventKind.markedVerified => t('sys.markedVerified'),
      SystemEventKind.mutuallyVerified => t('sys.mutuallyVerified'),
      SystemEventKind.joinedRoom => t('sys.joinedRoom', args),
      SystemEventKind.memberJoined => t('sys.memberJoined', args),
      SystemEventKind.memberLeft => t('sys.memberLeft', args),
      SystemEventKind.screenshotByPeer => t('sys.screenshotPeer', args),
      SystemEventKind.screenshotByMe => t('sys.screenshotMine'),
      SystemEventKind.sasMismatch => t('sys.sasMismatch'),
      SystemEventKind.protocolVersionMismatch => t(
        'sys.protocolVersionMismatch',
      ),
      SystemEventKind.peerMismatch => t('sys.peerMismatch'),
      SystemEventKind.handshakeFailed => t('sys.handshakeFailed'),
      SystemEventKind.handshakeTimedOut => t('sys.handshakeTimedOut'),
      SystemEventKind.peerBlocked => t('sys.peerBlocked'),
    };
  }
}
