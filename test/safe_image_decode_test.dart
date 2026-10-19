import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/safe_image_decode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('image header limit is inclusive and invalid files fail closed', () async {
    final dir = Directory.systemTemp.createTempSync('image_header_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/image.png');
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      ),
    );
    expect(await isSafeToDecodeImage(file.path, maxPixels: 1), isTrue);
    expect(
      await isSafeToDecodeImage(
        file.path,
        maxFileBytes: await file.length() - 1,
      ),
      isFalse,
    );
    expect(await isSafeToDecodeImage(file.path, maxPixels: 0), isFalse);
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAJxAAABOICAYAAAAXV3dIAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      ),
    );
    expect(await isSafeToDecodeImage(file.path), isTrue);
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAJxAAABOJCAYAAADcC6TtAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      ),
    );
    expect(await isSafeToDecodeImage(file.path), isFalse);
    await file.writeAsString('invalid image');
    expect(await isSafeToDecodeImage(file.path), isFalse);
    await file.delete();
    expect(await isSafeToDecodeImage(file.path), isFalse);
  });
}
