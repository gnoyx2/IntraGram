// SAS 검증을 QR 스캔으로 자동 대조함. 채널이 "같은 방의 카메라"라 소리 내어 읽기와
// 보안 강도가 같음(6자리 ≈ 20비트). 페이로드는 intragram-sas:<6자리>이고, 접두사로
// 우연히 프레임에 든 다른 QR(포털 URL 등)을 SAS로 오인하지 않게 함
library;

const String _sasQrPrefix = 'intragram-sas:';

String encodeSasQr(String sasDigits) => '$_sasQrPrefix$sasDigits';

// 일치하면 true, SAS 코드인데 숫자가 다르면 false(중간자 신호라 바로 경고),
// SAS 코드가 아니면 null(다른 QR이라 계속 스캔)
bool? sasScanVerdict(String raw, String expectedSas) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith(_sasQrPrefix)) return null;
  return trimmed.substring(_sasQrPrefix.length) == expectedSas;
}
