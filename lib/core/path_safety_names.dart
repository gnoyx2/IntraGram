import 'dart:convert';

const int kMaxBasenameBytes = 200;

// 확장자를 길게 만들어 이름 바이트 예산을 모두 차지하는 것을 막음
const int kMaxExtensionBytes = 32;

const Set<String> _kWindowsReservedStems = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'CONIN\$',
  'CONOUT\$',
  'COM0',
  'COM¹',
  'COM²',
  'COM³',
  'LPT0',
  'LPT¹',
  'LPT²',
  'LPT³',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

// 호출부가 첫 '.' 앞만 떼서 넘김 (CON.txt도 장치로 열림)
bool isWindowsReservedStem(String stem) =>
    _kWindowsReservedStems.contains(stem.toUpperCase());

// rune 단위로 잘라서 멀티바이트 글자가 반으로 안 잘림
String truncateUtf8(String value, int maxBytes) {
  if (maxBytes <= 0) return '';
  if (utf8.encode(value).length <= maxBytes) return value;
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final runeBytes = utf8.encode(String.fromCharCode(rune)).length;
    if (used + runeBytes > maxBytes) break;
    buffer.writeCharCode(rune);
    used += runeBytes;
  }
  return buffer.toString();
}

// 한글 자모만 음절로 합침 (전체 NFC 아님). macOS가 한글 파일 이름을 NFD로 줘서 그대로 보내면 다른 OS에서 자모가 풀려 보임
const int _sBase = 0xAC00;
const int _lBase = 0x1100;
const int _vBase = 0x1161;
const int _tBase = 0x11A7;
const int _lCount = 19;
const int _vCount = 21;
const int _tCount = 28;
const int _nCount = _vCount * _tCount;
const int _sCount = _lCount * _nCount;

bool _isL(int c) => c >= _lBase && c < _lBase + _lCount;
bool _isV(int c) => c >= _vBase && c < _vBase + _vCount;
// _tBase 자체는 '종성 없음' 자리라 뺌
bool _isT(int c) => c > _tBase && c < _tBase + _tCount;
bool _isS(int c) => c >= _sBase && c < _sBase + _sCount;

// 전송·표시용 이름에만 씀. 원본 경로·파일 핸들엔 쓰면 안 됨 (OS가 준 그대로 열어야 함)
String normalizeHangulNfc(String value) {
  final runes = value.runes.toList();
  final out = <int>[];
  var i = 0;
  while (i < runes.length) {
    final ch = runes[i];
    if (_isL(ch) && i + 1 < runes.length && _isV(runes[i + 1])) {
      final lIndex = ch - _lBase;
      final vIndex = runes[i + 1] - _vBase;
      var syllable = _sBase + (lIndex * _nCount) + (vIndex * _tCount);
      var consumed = 2;
      if (i + 2 < runes.length && _isT(runes[i + 2])) {
        syllable += runes[i + 2] - _tBase;
        consumed = 3;
      }
      out.add(syllable);
      i += consumed;
    } else if (_isS(ch) &&
        (ch - _sBase) % _tCount == 0 &&
        i + 1 < runes.length &&
        _isT(runes[i + 1])) {
      // 완성형 LV 음절 뒤에 종성 자모가 따로 오는 경우
      out.add(ch + (runes[i + 1] - _tBase));
      i += 2;
    } else {
      out.add(ch);
      i += 1;
    }
  }
  return String.fromCharCodes(out);
}
