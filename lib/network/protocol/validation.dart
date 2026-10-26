part of '../protocol.dart';

// 상한 있는 wire 필드 파서. 절대 안 던짐: 형식이 틀리면 null이고 호출부가 프레임째 거부함 (0·빈 문자열 기본값으로 정상 프레임을 안 만듦).
// 1e999가 double.infinity로 풀려 toInt()가 던지거나 1.0·"5"가 조용히 5로 바뀌던 길을 막음

// JSON int만 받음: 1.0·infinity·NaN·문자열·범위 밖은 null (브라우저 JSON.stringify(5)도 5라 정상 클라이언트는 괜찮음)
int? wireInt(Object? value, {required int min, required int max}) {
  if (value is! int) return null;
  if (value < min || value > max) return null;
  return value;
}

// ID·토큰: hex(newId)와 base64url(generateSecureToken)을 받는 [A-Za-z0-9_=-] 1..128자. 경로 구분자·공백·제어 문자는 자동으로 걸림
final RegExp _wireIdPattern = RegExp(r'^[A-Za-z0-9_=-]{1,128}$');

String? wireId(Object? value) {
  if (value is! String) return null;
  return _wireIdPattern.hasMatch(value) ? value : null;
}

String? wireText(Object? value, {required int maxUtf8Bytes}) {
  if (value is! String) return null;
  if (utf8.encode(value).length > maxUtf8Bytes) return null;
  return value;
}

// base64 고정 길이 바이트(신원 공개키·서명). 형식이나 길이가 다르면 null
Uint8List? wireBytes(Object? value, {required int length}) {
  if (value is! String || value.length > (length + 2) ~/ 3 * 4) {
    return null;
  }
  try {
    final bytes = base64.decode(value);
    return bytes.length == length ? bytes : null;
  } on FormatException {
    return null;
  }
}

// 자기 신고 표시 이름을 UTF-8 바이트 한도에 맞춰 글자 경계에서 자름: 방 프레임(joined/left)에 그대로 실려서 엄격 파서 한도를 넘으면
// 멤버 전원이 그 프레임을 버림
String boundedAlias(String alias, {int maxUtf8Bytes = 256}) {
  var bytes = 0;
  final out = StringBuffer();
  for (final rune in alias.runes) {
    final size = rune < 0x80
        ? 1
        : (rune < 0x800 ? 2 : (rune < 0x10000 ? 3 : 4));
    if (bytes + size > maxUtf8Bytes) break;
    bytes += size;
    out.writeCharCode(rune);
  }
  return out.toString();
}

// 상대가 밝힌 플랫폼 이름 (hello, mDNS os). 목록 부제·스크린 리더·보관소로 그대로 가서
// 앱이 쓰는 이름만 받고 나머진 Unknown (길이 제한 없는 아무 글이나 양방향 제어 문자가 화면에 안 뜸)
const Set<String> _kPlatformNames = <String>{
  'iOS',
  'iPadOS',
  'Android',
  'macOS',
  'Windows',
  'Linux',
};

String wirePlatform(Object? value) =>
    value is String && _kPlatformNames.contains(value) ? value : 'Unknown';

// 필드 하나가 형식에 안 맞음. InboundInner.fromJson 안에서만 던지고 바로 MalformedInner로 바뀜
class _BadField implements Exception {
  const _BadField(this.field);
  final String field;
}

String _reqId(Map<String, dynamic> j, String key) =>
    wireId(j[key]) ?? (throw _BadField(key));

// 없거나 null이면 null. 값이 있는데 틀리면 프레임째 거부 (틀린 선택 필드만 버리고 정상 프레임인 척 안 함)
String? _optId(Map<String, dynamic> j, String key) =>
    j[key] == null ? null : _reqId(j, key);

int _reqInt(Map<String, dynamic> j, String key, int min, int max) =>
    wireInt(j[key], min: min, max: max) ?? (throw _BadField(key));

int _optInt(Map<String, dynamic> j, String key, int min, int max, int dflt) =>
    j[key] == null ? dflt : _reqInt(j, key, min, max);

int? _optIntOrNull(Map<String, dynamic> j, String key, int min, int max) =>
    j[key] == null ? null : _reqInt(j, key, min, max);

String _reqText(
  Map<String, dynamic> j,
  String key,
  int maxUtf8Bytes, {
  bool allowEmpty = false,
}) {
  final value = wireText(j[key], maxUtf8Bytes: maxUtf8Bytes);
  if (value == null || (!allowEmpty && value.isEmpty)) throw _BadField(key);
  return value;
}

String? _optText(Map<String, dynamic> j, String key, int maxUtf8Bytes) =>
    j[key] == null ? null : _reqText(j, key, maxUtf8Bytes, allowEmpty: true);

bool _reqBool(Map<String, dynamic> j, String key) {
  final value = j[key];
  return value is bool ? value : throw _BadField(key);
}

bool _optBool(Map<String, dynamic> j, String key) =>
    j[key] == null ? false : _reqBool(j, key);

// 중첩 객체 필드(영수증·작성자 서명·자격 증명): 여기선 객체인지만 봄. 속은 그 값을 쓰는 증적·자격 단계가 엄격하게 파싱하고
// 중계 전 정규화(_canonicalWire)가 아는 필드만 다시 써서 끼워 넣은 키가 안 넘어감
Map<String, dynamic>? _optObject(Map<String, dynamic> j, String key) {
  final value = j[key];
  if (value == null) return null;
  if (value is! Map<String, dynamic>) throw _BadField(key);
  return value;
}
