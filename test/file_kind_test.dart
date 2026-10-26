import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/file_kind.dart';

import 'support/contrast.dart';

void main() {
  test('classifies by extension, case-insensitive', () {
    expect(FileKind.of('holiday.JPG'), FileKind.image);
    expect(FileKind.of('clip.mp4'), FileKind.video);
    expect(FileKind.of('song.flac'), FileKind.audio);
    expect(FileKind.of('report.pdf'), FileKind.pdf);
    expect(FileKind.of('notes.md'), FileKind.document);
    expect(FileKind.of('budget.xlsx'), FileKind.spreadsheet);
    expect(FileKind.of('deck.pptx'), FileKind.presentation);
    expect(FileKind.of('archive.tar.gz'), FileKind.archive);
    expect(FileKind.of('main.dart'), FileKind.code);
    expect(FileKind.of('Inter.woff2'), FileKind.font);
    expect(FileKind.of('ubuntu.iso'), FileKind.disk);
    expect(FileKind.of('novel.epub'), FileKind.ebook);
    expect(FileKind.of('setup.exe'), FileKind.executable);
    expect(FileKind.of('installer.apk'), FileKind.executable);
  });

  test('falls back to the MIME prefix when the extension is unknown', () {
    expect(FileKind.of('blob', mimeType: 'image/png'), FileKind.image);
    expect(FileKind.of('capture', mimeType: 'video/webm'), FileKind.video);
    expect(FileKind.of('track', mimeType: 'audio/mpeg'), FileKind.audio);
    expect(FileKind.of('data', mimeType: 'application/pdf'), FileKind.pdf);
    expect(
      FileKind.of('bundle', mimeType: 'application/zip'),
      FileKind.archive,
    );
  });

  test('unknown extension and no MIME is other', () {
    expect(FileKind.of('mystery.qqq'), FileKind.other);
    expect(FileKind.of('noext'), FileKind.other);
    expect(FileKind.of('.zshrc'), FileKind.other); // dotfile은 확장자 없음
  });

  test('every kind has an icon', () {
    for (final kind in FileKind.values) {
      expect(kind.icon, isA<IconData>());
    }
  });

  test('every kind badge keeps its white glyph at 3:1 or more', () {
    for (final kind in FileKind.values) {
      expect(
        contrastRatio(const Color(0xFFFFFFFF), kind.tint),
        greaterThanOrEqualTo(3),
        reason: kind.name,
      );
    }
  });
}
