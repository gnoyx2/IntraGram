part of 'outgoing_transfers.dart';

extension _OutgoingTransfersThumb on OutgoingTransfers {
  // 12 MiB 이하 이미지면 축소된 PNG 썸네일(base64)을 생성함. 파일을 전체 1회 읽음
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

// 96px 폭 PNG로 축소하여 base64로 인코딩함. 디코딩 실패(SVG 등)나 24 KiB 초과 시 null을 반환함
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
