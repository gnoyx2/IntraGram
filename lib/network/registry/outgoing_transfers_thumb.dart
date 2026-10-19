part of 'outgoing_transfers.dart';

extension _OutgoingTransfersThumb on OutgoingTransfers {
  // 파일 경로가 이미지고 너무 크지 않으면 다운스케일 PNG 썸네일(base64), 아니면 null
  // 한계: 썸네일 만들려고 파일 전체를 한 번 읽음 (12 MiB 넘으면 건너뜀, 전송 스트림이 어차피 다시 읽으니 큰 낭비는 아님)
  Future<String?> _thumbForPath(String? path, String name, int size) async {
    if (path == null) return null;
    if (!(_mimeFor(name)?.startsWith('image/') ?? false)) return null;
    if (size > 12 * 1024 * 1024) return null;
    try {
      return await _imageThumb(await File(path).readAsBytes());
    } on Object {
      return null;
    }
  }
}

String? _mimeFor(String fileName) => lookupMimeType(safeBasename(fileName));

// 이미지 바이트를 96px 폭 PNG로 줄여 base64로. 디코드 실패(SVG
// 등)나 결과가 24 KB 넘으면 null (제안은 썸네일 없이 나감)
Future<String?> _imageThumb(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 96);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    final png = data.buffer.asUint8List();
    if (png.length > 24 * 1024) return null;
    return base64.encode(png);
  } on Object {
    return null;
  }
}
