import 'dart:io';
import 'dart:ui' as ui;

Future<bool> isSafeToDecodeImage(
  String filePath, {
  int maxPixels = 50000000,
  int maxFileBytes = 50 * 1024 * 1024,
}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    if (await File(filePath).length() > maxFileBytes) return false;
    buffer = await ui.ImmutableBuffer.fromFilePath(filePath);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return descriptor.width > 0 &&
        descriptor.height > 0 &&
        descriptor.width * descriptor.height <= maxPixels;
  } on Object {
    return false;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
