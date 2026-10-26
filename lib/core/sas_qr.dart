// SAS를 QR로 찍어 대조함. 같은 방 카메라라는 채널이 소리 내어 읽기와 강도가 같음(6자리 ≈ 20비트).
// intragram-sas: 접두사로 프레임에 우연히 든 다른 QR(포털 주소 등)을 SAS로 착각 안 함
library;

const String _sasQrPrefix = 'intragram-sas:';

String encodeSasQr(String sasDigits) => '$_sasQrPrefix$sasDigits';

// 같으면 true, SAS 코드인데 숫자가 다르면 false(중간자 신호라 바로 경고), SAS 코드가 아니면 null(다른 QR이라 계속 스캔)
bool? sasScanVerdict(String raw, String expectedSas) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith(_sasQrPrefix)) return null;
  return trimmed.substring(_sasQrPrefix.length) == expectedSas;
}
