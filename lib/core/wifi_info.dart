import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

// 이 기기 MAC은 일부러 안 담음 (라우터 BSSID랑 헷갈림)
class WifiInfo {
  const WifiInfo({
    this.ssid,
    this.channel,
    this.phyMode,
    this.linkRate,
    this.signal,
    this.security,
  });

  // null이면 OS가 이름을 가림 (macOS 14.4+, 위치 권한 없음)
  final String? ssid;
  final String? channel;
  final String? phyMode;
  final String? linkRate;
  final String? signal;
  final String? security;
}

// 데스크톱에서만 채움 (OS 기본 명령을 돌려 파싱). iOS·Android는 SSID에 위치 권한이 필요한데 이 앱은 위치 권한을 안 쓰는 게 설계라 안 함
Future<WifiInfo?> currentWifiInfo() async {
  try {
    if (Platform.isMacOS) return await _macWifiInfo();
    if (Platform.isWindows) return await _windowsWifiInfo();
    if (Platform.isLinux) return await _linuxWifiInfo();
  } on Object {
    return null;
  }
  return null;
}

// spairport_current_network_information 밑에 SSID(_name)·채널·PHY·속도·신호·보안이 있음
Future<WifiInfo?> _macWifiInfo() async {
  final result = await Process.run('system_profiler', [
    'SPAirPortDataType',
    '-json',
  ]);
  if (result.exitCode != 0) return null;
  final decoded = jsonDecode(result.stdout as String);
  if (decoded is! Map) return null;
  final types = decoded['SPAirPortDataType'];
  if (types is! List) return null;
  final interfaces =
      (types.firstOrNull as Map?)?['spairport_airport_interfaces'];
  if (interfaces is! List) return null;
  final current =
      (interfaces.firstOrNull
          as Map?)?['spairport_current_network_information'];
  if (current is! Map) return null;
  final ssid = current['_name'];
  if (ssid is! String) return null;
  // macOS 14.4+는 위치 권한 없는 앱에 이름을 '<redacted>'로 줌: 그대로 안 보이고 이유를 띄움
  final hidden = ssid == '<redacted>';
  return WifiInfo(
    ssid: hidden ? null : ssid,
    channel: current['spairport_network_channel']?.toString(),
    phyMode: current['spairport_network_phymode']?.toString(),
    linkRate: current['spairport_network_rate']?.toString(),
    signal: current['spairport_signal_noise']?.toString(),
    security: current['spairport_security_mode']?.toString(),
  );
}

// wlanapi.dll을 직접 안 부름: Windows 11 24H2부터 현재 연결 조회에 위치 권한 창이 뜸 (위치 권한 안 쓰는 설계랑 충돌).
// System32의 netsh는 창을 안 띄우고, 위치가 꺼져 있으면 안내문만 내서 null이 됨. Windows 실기기 검증은 아직
Future<WifiInfo?> _windowsWifiInfo() async {
  final result = await Process.run('netsh', ['wlan', 'show', 'interfaces']);
  if (result.exitCode != 0) return null;
  return parseNetshInterfaces(result.stdout as String);
}

final _whitespace = RegExp(r'\s');
final _signalValue = RegExp(r'^\d{1,3}%$');
// 값 전체가 규격 이름일 때만: '802.11n USB Wireless LAN Card' 같은 어댑터 설명은 안 걸림
final _radioTypeValue = RegExp(r'^802\.11[a-z]{1,2}$');

// netsh 라벨은 Windows 표시 언어를 따름. 영어·한국어 라벨만 알고(한국어는 실기기 확인 전, DEVICE_QA),
// 모르는 언어면 신호(99%)·무선 종류(802.11ax)는 값 모양으로 찾고 채널·속도·인증은 비워 둠
@visibleForTesting
WifiInfo? parseNetshInterfaces(String output) {
  // 라벨은 공백을 빼고 비교: '수신 속도(Mbps)'와 '수신 속도 (Mbps)'가 같음
  final map = <String, String>{};
  for (final line in output.split('\n')) {
    final i = line.indexOf(':');
    if (i < 0) continue;
    final key = line.substring(0, i).replaceAll(_whitespace, '').toLowerCase();
    final value = line.substring(i + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) map[key] = value;
  }
  final ssid = map['ssid'];
  if (ssid == null) return null;
  String? labeled(List<String> keys) =>
      keys.map((key) => map[key]).nonNulls.firstOrNull;
  // 네트워크 이름은 사용자가 정해서 그 값(SSID·프로필 줄)은 빼고 찾음 ('50%'라는 이름이 신호 칸에 안 들어가게)
  String? shaped(RegExp shape) => map.values
      .where((value) => value != ssid && shape.hasMatch(value))
      .firstOrNull;
  return WifiInfo(
    ssid: ssid,
    channel: labeled(['channel', '채널']),
    phyMode: labeled(['radiotype', '라디오종류']) ?? shaped(_radioTypeValue),
    linkRate: labeled(['receiverate(mbps)', '수신속도(mbps)']),
    signal: labeled(['signal', '신호']) ?? shaped(_signalValue),
    security: labeled(['authentication', '인증']),
  );
}

// nmcli 없는 배포판이면 조용히 null
Future<WifiInfo?> _linuxWifiInfo() async {
  final result = await Process.run('nmcli', [
    '-t',
    '-f',
    'in-use,ssid,signal,chan,freq,rate,security',
    'dev',
    'wifi',
  ]);
  if (result.exitCode != 0) return null;
  return parseNmcliWifi(result.stdout as String);
}

// 연결된 줄은 in-use 칸의 '*'로 찾음 (active 칸의 yes/no는 번역됨). nmcli dev wifi엔 802.11 세대 칸이 없어서
// 모드는 비우고 주파수는 macOS처럼 채널 옆에 붙임
@visibleForTesting
WifiInfo? parseNmcliWifi(String output) {
  for (final line in output.split('\n')) {
    final fields = _terseFields(line);
    if (fields.length != 7 || fields[0] != '*') continue;
    final freq = fields[4];
    return WifiInfo(
      ssid: fields[1],
      channel: freq.isEmpty ? fields[3] : '${fields[3]} ($freq)',
      linkRate: fields[5],
      signal: '${fields[2]}%',
      security: fields[6],
    );
  }
  return null;
}

// nmcli -t는 값 안의 콜론과 역슬래시를 이스케이프해서 씀: 풀어야 콜론 든 SSID에서 칸이 안 밀림
List<String> _terseFields(String line) {
  final fields = <String>[];
  final field = StringBuffer();
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == r'\' && i + 1 < line.length) {
      i++;
      field.write(line[i]);
    } else if (char == ':') {
      fields.add(field.toString());
      field.clear();
    } else {
      field.write(char);
    }
  }
  return [...fields, field.toString()];
}
