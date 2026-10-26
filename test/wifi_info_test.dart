import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/wifi_info.dart';

// `netsh wlan show interfaces` 출력. 라벨은 Windows 표시 언어를 따라 바뀜
const _english = '''

There is 1 interface on the system:

    Name                   : Wi-Fi
    Description            : 802.11n USB Wireless LAN Card
    GUID                   : 3f1a2b4c-0000-4000-8000-000000000000
    Physical address       : aa:bb:cc:dd:ee:ff
    Interface type         : Primary
    State                  : connected
    SSID                   : Home 5G
    AP BSSID               : 11:22:33:44:55:66
    Band                   : 5 GHz
    Channel                : 36
    Network type           : Infrastructure
    Radio type             : 802.11ac
    Authentication         : WPA2-Personal
    Cipher                 : CCMP
    Connection mode        : Auto Connect
    Receive rate (Mbps)    : 866.7
    Transmit rate (Mbps)   : 650
    Signal                 : 99%
    Profile                : Home 5G

    Hosted network status  : Not available
''';

// 실제 캡처가 아님: 공개된 netsh 파서들이 쓰는 한국어 라벨로 만든 것 (실기기 확인은 DEVICE_QA)
const _korean = '''

시스템에 1 인터페이스가 있습니다.

    이름                   : Wi-Fi
    설명                   : Intel(R) Wi-Fi 6 AX201 160MHz
    물리적 주소            : aa:bb:cc:dd:ee:ff
    상태                   : 연결됨
    SSID                   : 우리집
    BSSID                  : 11:22:33:44:55:66
    네트워크 종류          : 인프라
    라디오 종류            : 802.11ax
    인증                   : WPA2-개인
    암호                   : CCMP
    연결 모드              : 자동 연결
    채널                   : 149
    수신 속도 (Mbps)       : 1201
    전송 속도 (Mbps)       : 960
    신호                   : 87%
    프로필                 : 우리집
''';

// 앱이 라벨을 모르는 언어: 값 모양으로 찾는 칸만 채워짐
const _japanese = '''
    名前                   : Wi-Fi
    SSID                   : office
    無線の種類             : 802.11ax
    チャネル               : 36
    シグナル               : 72%
''';

// Windows 11 24H2부터 위치 서비스가 꺼져 있으면 연결 정보 대신 나오는 안내
const _locationOff = '''
Network shell commands need location permission to access WLAN information. Turn on Location services on the Location page in Privacy & security settings.

Here is the URI for the Location page in the Settings app:
ms-settings:privacy-location
To open the Location page in the Settings app, hold down the Ctrl key and select the link, or run the following command:
start ms-settings:privacy-location

Function WlanQueryInterface returns error 5:
Access is denied.
''';

void main() {
  test('reads every field from English netsh output', () {
    final info = parseNetshInterfaces(_english);

    expect(info?.ssid, 'Home 5G');
    expect(info?.channel, '36');
    // 어댑터 설명이 802.11로 시작해도 무선 종류로 잡지 않음
    expect(info?.phyMode, '802.11ac');
    expect(info?.linkRate, '866.7');
    expect(info?.signal, '99%');
    expect(info?.security, 'WPA2-Personal');
  });

  test('reads every field from Korean netsh output with CRLF lines', () {
    final info = parseNetshInterfaces(_korean.replaceAll('\n', '\r\n'));

    expect(info?.ssid, '우리집');
    expect(info?.channel, '149');
    expect(info?.phyMode, '802.11ax');
    expect(info?.linkRate, '1201');
    expect(info?.signal, '87%');
    expect(info?.security, 'WPA2-개인');
  });

  test('finds signal and radio type by value in an unknown language', () {
    final info = parseNetshInterfaces(_japanese);

    expect(info?.ssid, 'office');
    expect(info?.phyMode, '802.11ax');
    expect(info?.signal, '72%');
    expect(info?.channel, isNull);
    expect(info?.security, isNull);
  });

  test('a network named like a value never fills signal or mode', () {
    for (final name in ['50%', '802.11n']) {
      final info = parseNetshInterfaces(
        _japanese.replaceFirst(': office', ': $name'),
      );

      expect(info?.ssid, name);
      expect(info?.signal, '72%');
      expect(info?.phyMode, '802.11ax');
    }
    // 신호 줄이 없어도 프로필 줄(보통 네트워크 이름과 같음)을 신호로 잡지 않음
    final noSignal = parseNetshInterfaces('''
    SSID                   : 50%
    プロファイル           : 50%
''');
    expect(noSignal?.signal, isNull);
  });

  test('returns null when Windows hides Wi-Fi details without location', () {
    expect(parseNetshInterfaces(_locationOff), isNull);
  });

  // nmcli는 active 칸의 yes/no를 언어 설정에 따라 번역함: 언어와 무관한 in-use 표시로 찾음
  test('finds the connected Linux network by its in-use mark', () {
    const output =
        ' :Neighbor:40:6:2437 MHz:65 Mbit/s:WPA2\n'
        '*:우리집:87:149:5745 MHz:540 Mbit/s:WPA2 WPA3\n';

    final info = parseNmcliWifi(output);

    expect(info?.ssid, '우리집');
    expect(info?.signal, '87%');
    expect(info?.channel, '149 (5745 MHz)');
    // nmcli엔 802.11 세대 칸이 없음: 주파수를 모드 칸에 넣지 않음
    expect(info?.phyMode, isNull);
    expect(info?.security, 'WPA2 WPA3');
    expect(parseNmcliWifi(' :Neighbor:40:6:2437 MHz:65 Mbit/s:WPA2\n'), isNull);
  });

  // -t는 값 안의 ':'·'\'를 '\:'·'\\'로 씀: 풀지 않으면 칸이 밀려 신호에 '5G%'가 뜸
  test('reads a Linux network name that has a colon or a backslash', () {
    final info = parseNmcliWifi(
      r'*:Home\:5G\\x:87:149:5745 MHz:540 Mbit/s:WPA2',
    );

    expect(info?.ssid, r'Home:5G\x');
    expect(info?.signal, '87%');
    expect(info?.channel, '149 (5745 MHz)');
    expect(info?.security, 'WPA2');
  });

  test('returns null when no Wi-Fi is connected', () {
    expect(
      parseNetshInterfaces('''
    Name                   : Wi-Fi
    State                  : disconnected
    Radio status           : Hardware On
'''),
      isNull,
    );
  });
}
