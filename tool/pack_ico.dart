// 크기별 PNG를 Windows ICO 항목에 그대로 넣음.
// 가로·세로 필드는 1바이트라 256px는 0으로 기록해야 함.
import 'dart:io';
import 'dart:typed_data';

const _sizes = [16, 24, 32, 48, 64, 128, 256];

void main() {
  final images = <int, Uint8List>{
    for (final size in _sizes)
      size: File('build/icon_master/windows/icon_$size.png').readAsBytesSync(),
  };

  final headerSize = 6 + 16 * _sizes.length;
  var offset = headerSize;

  final out = BytesBuilder();
  final header = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, _sizes.length, Endian.little);
  out.add(header.buffer.asUint8List());

  for (final size in _sizes) {
    final bytes = images[size]!;
    final wh = size == 256 ? 0 : size;
    final entry = ByteData(16)
      ..setUint8(0, wh)
      ..setUint8(1, wh)
      ..setUint8(2, 0)
      ..setUint8(3, 0)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, bytes.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    out.add(entry.buffer.asUint8List());
    offset += bytes.length;
  }

  for (final size in _sizes) {
    out.add(images[size]!);
  }

  final outFile = File('windows/runner/resources/app_icon.ico');
  final bytes = out.toBytes();
  outFile.writeAsBytesSync(bytes);
  stdout.writeln(
    'Wrote ${outFile.path} (${bytes.length} bytes, ${_sizes.length} entries)',
  );
}
