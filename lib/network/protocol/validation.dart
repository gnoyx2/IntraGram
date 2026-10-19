part of '../protocol.dart';

// bounded wire 필드 파서. 밖으로 절대 안 던짐: malformed 입력은 전부 null이고 호출부가
// 프레임 거부(MalformedInner)로 처리함 (0/빈 문자열 기본값으로 "정상 프레임"을 안 만듦)
// 예: 1e999가 double.infinity로 디코드돼 toInt()가
// 던지거나 1.0/"5"가 조용히 5로 coercion되던 경로를 차단

// JSON 정수(int)만 받음: 1.0, double.infinity, NaN, 문자열, 범위 밖은 전부 null
// 브라우저 JSON.stringify(5)도 5로 나가서 정상 클라이언트는 영향 없음
int? wireInt(Object? value, {required int min, required int max}) {
  if (value is! int) return null;
  if (value < min || value > max) return null;
  return value;
}

// ID/토큰용 ASCII 토큰: hex(newId)와 base64url+패딩(generateSecureToken)을
// 수용하는 [A-Za-z0-9_=-], 길이 1..128
// 경로 구분자/공백/control은 charset 밖이라 자동 거부
final RegExp _wireIdPattern = RegExp(r'^[A-Za-z0-9_=-]{1,128}$');

String? wireId(Object? value) {
  if (value is! String) return null;
  return _wireIdPattern.hasMatch(value) ? value : null;
}

// 문자열이 아니거나 UTF-8 바이트 길이가 maxUtf8Bytes를 넘으면 null
String? wireText(Object? value, {required int maxUtf8Bytes}) {
  if (value is! String) return null;
  if (utf8.encode(value).length > maxUtf8Bytes) return null;
  return value;
}

// base64로 온 고정 길이 바이트 필드(신원 공개키/서명). 문자열이 아니거나 디코드가 안 되거나 길이가 다르면 null
Uint8List? wireBytes(Object? value, {required int length}) {
  if (value is! String) return null;
  try {
    final bytes = base64.decode(value);
    return bytes.length == length ? bytes : null;
  } on FormatException {
    return null;
  }
}

// hello/web_hello의 자기 선언 표시 이름을 UTF-8 maxUtf8Bytes에 맞게 문자 경계에서 자름
// 이 이름은 방 프레임(joined/left)에 그대로 실리는데 엄격 파서 한도를 넘으면 그 프레임이 멤버 전원에게서 거부됨
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

// 필드 하나가 형식에 안 맞음. InboundInner.fromJson 안에서만
// 던지고 바로 MalformedInner로 바꿈 (라이브러리 밖으로 안 샘)
class _BadField implements Exception {
  const _BadField(this.field);
  final String field;
}

String _reqId(Map<String, dynamic> j, String key) =>
    wireId(j[key]) ?? (throw _BadField(key));

// 없거나 null이면 null. 값이 있는데 형식이 틀리면 프레임 전체를
// 거부함 (잘못된 선택 필드를 조용히 버리고 정상 프레임인 척하지 않음)
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

// 없으면 false. 있는데 bool이 아니면 거부
bool _optBool(Map<String, dynamic> j, String key) =>
    j[key] == null ? false : _reqBool(j, key);
