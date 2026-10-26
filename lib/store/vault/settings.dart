part of '../vault.dart';

// 제로 디스크의 유일한 옵트인 예외 (기본 꺼짐). 켜면 고른 만큼(메시지, 전송 기록)이 앱 비공개 폴더의 vault.json 하나에 담김.
// PIN을 안 켜면 암호화 없이 OS 파일 권한만 믿음. 세션 키, 소각된 메시지, 안 끝난 전송은 절대 안 담고 패닉이 이 파일을 지움
class VaultSettings {
  const VaultSettings({
    this.enabled = false,
    this.keepMessages = true,
    this.keepTransfers = true,
    this.largeMessageMode = LargeMessageMode.inline,
    this.pinProtected = false,
    this.autoLockMinutes = 5,
    this.stayConnectedInBackground = false,
    this.onlyChatsIStart = false,
    this.langOverride,
    this.savedAlias,
    this.textScale = 1.0,
  });

  final bool enabled;
  final bool keepMessages;
  final bool keepTransfers;

  // 보관소가 꺼져 있어도 RAM에서 적용됨 (그땐 재시작하면 초기화)
  final LargeMessageMode largeMessageMode;

  // enabled일 때만 의미 있음
  final bool pinProtected;
  final int autoLockMinutes;

  // Android 전용: 백그라운드에서도 포그라운드 서비스로 링크를 살려 둠 (기본 꺼짐, 배터리)
  final bool stayConnectedInBackground;

  // 이번 세션에 대화한 적 없는 기기가 여는 연결(대화·방 초대)을 거절. 보관소가 꺼져 있어도 RAM에서 적용됨
  final bool onlyChatsIStart;

  // 'en' / 'ko' / null(OS 로케일). 보관소가 꺼져 있어도 RAM에서 적용됨
  final String? langOverride;

  // 보관소가 켜졌을 때의 기기 이름. 스냅샷의 일부라 duress 세션은 자연히 null을 봄. 보관소가 꺼져 있으면 identity.json이 따로 담음
  final String? savedAlias;

  // 앱 글자 배율(OS 글자 크기에 곱함). macOS는 OS 값이 Flutter에 안 넘어와 이것만 먹음
  final double textScale;

  VaultSettings copyWith({
    bool? enabled,
    bool? keepMessages,
    bool? keepTransfers,
    LargeMessageMode? largeMessageMode,
    bool? pinProtected,
    int? autoLockMinutes,
    bool? stayConnectedInBackground,
    bool? onlyChatsIStart,
    Object? langOverride = _unset,
    Object? savedAlias = _unset,
    double? textScale,
  }) => VaultSettings(
    enabled: enabled ?? this.enabled,
    keepMessages: keepMessages ?? this.keepMessages,
    keepTransfers: keepTransfers ?? this.keepTransfers,
    largeMessageMode: largeMessageMode ?? this.largeMessageMode,
    pinProtected: pinProtected ?? this.pinProtected,
    autoLockMinutes: (autoLockMinutes ?? this.autoLockMinutes).clamp(1, 60),
    stayConnectedInBackground:
        stayConnectedInBackground ?? this.stayConnectedInBackground,
    onlyChatsIStart: onlyChatsIStart ?? this.onlyChatsIStart,
    langOverride: langOverride == _unset
        ? this.langOverride
        : langOverride as String?,
    savedAlias: savedAlias == _unset ? this.savedAlias : savedAlias as String?,
    textScale: textScale ?? this.textScale,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'keepMessages': keepMessages,
    'keepTransfers': keepTransfers,
    'largeMessageMode': largeMessageMode.name,
    'pinProtected': pinProtected,
    'autoLockMinutes': autoLockMinutes,
    'stayConnectedInBackground': stayConnectedInBackground,
    'onlyChatsIStart': onlyChatsIStart,
    'langOverride': ?langOverride,
    'savedAlias': ?savedAlias,
    if (textScale != 1.0) 'textScale': textScale,
  };

  factory VaultSettings.fromJson(Map<String, dynamic> j) => VaultSettings(
    enabled: j['enabled'] == true,
    keepMessages: j['keepMessages'] != false,
    keepTransfers: j['keepTransfers'] != false,
    largeMessageMode: LargeMessageMode.values.firstWhere(
      (m) => m.name == j['largeMessageMode'],
      orElse: () => LargeMessageMode.inline,
    ),
    pinProtected: j['pinProtected'] == true,
    autoLockMinutes: j['autoLockMinutes'] is int
        ? (j['autoLockMinutes'] as int).clamp(1, 60)
        : 5,
    stayConnectedInBackground: j['stayConnectedInBackground'] == true,
    onlyChatsIStart: j['onlyChatsIStart'] == true,
    langOverride: switch (j['langOverride']) {
      'en' => 'en',
      'ko' => 'ko',
      _ => null,
    },
    savedAlias: j['savedAlias'] is String ? j['savedAlias'] as String : null,
    textScale: switch (j['textScale']) {
      final num v when kTextScales.contains(v) => v.toDouble(),
      _ => 1.0,
    },
  );
}

// 설정·⌘+/⌘−가 고르는 앱 글자 배율
const kTextScales = <double>[0.85, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0];

// step 0이면 100%로, 아니면 목록에서 한 칸씩 (끝에선 멈춤)
double stepTextScale(double current, int step) {
  if (step == 0) return 1.0;
  final at = kTextScales.indexOf(current);
  final from = at < 0 ? kTextScales.indexOf(1.0) : at;
  return kTextScales[(from + step).clamp(0, kTextScales.length - 1)];
}
