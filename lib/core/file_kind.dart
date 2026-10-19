// SPDX-License-Identifier: MIT AND Apache-2.0
// Portions adapted from LocalSend (Apache-2.0); see THIRD_PARTY_NOTICES.md.
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

// LocalSend(Apache-2.0)의 file_path_helper / file_type_ext에서 가져와 버킷을 확장함
// 출처와 변경 내용은 THIRD_PARTY_NOTICES.md 참고
enum FileKind {
  image,
  video,
  audio,
  pdf,
  document,
  spreadsheet,
  presentation,
  archive,
  code,
  font,
  disk,
  ebook,
  executable,
  other;

  IconData get icon => switch (this) {
    FileKind.image => Icons.image_outlined,
    FileKind.video => Icons.movie_outlined,
    FileKind.audio => Icons.audiotrack_outlined,
    FileKind.pdf => Icons.picture_as_pdf_outlined,
    FileKind.document => Icons.description_outlined,
    FileKind.spreadsheet => Icons.table_chart_outlined,
    FileKind.presentation => Icons.slideshow_outlined,
    FileKind.archive => Icons.folder_zip_outlined,
    FileKind.code => Icons.code,
    FileKind.font => Icons.font_download_outlined,
    FileKind.disk => Icons.album_outlined,
    FileKind.ebook => Icons.menu_book_outlined,
    FileKind.executable => Icons.terminal,
    FileKind.other => Icons.insert_drive_file_outlined,
  };

  // 전송 카드 배지 색. 흰 글리프와 3:1 이상 나오는 600 단계만 씀
  // 문서·PDF는 레드, 코드는 그린, 미디어는 퍼플 계열, 압축은 오렌지
  Color get tint => switch (this) {
    FileKind.image => const Color(0xFF7C3AED),
    FileKind.video => const Color(0xFF9333EA),
    FileKind.audio => const Color(0xFFC026D3),
    FileKind.pdf => const Color(0xFFDC2626),
    FileKind.document => const Color(0xFFE11D48),
    FileKind.spreadsheet => const Color(0xFF059669),
    FileKind.presentation => const Color(0xFFD97706),
    FileKind.archive => const Color(0xFFEA580C),
    FileKind.code => const Color(0xFF16A34A),
    FileKind.font => const Color(0xFF4F46E5),
    FileKind.disk => const Color(0xFF475569),
    FileKind.ebook => const Color(0xFF0D9488),
    FileKind.executable => const Color(0xFF334155),
    FileKind.other => const Color(0xFF64748B),
  };

  String get label => switch (this) {
    FileKind.image => 'Image',
    FileKind.video => 'Video',
    FileKind.audio => 'Audio',
    FileKind.pdf => 'PDF',
    FileKind.document => 'Document',
    FileKind.spreadsheet => 'Spreadsheet',
    FileKind.presentation => 'Presentation',
    FileKind.archive => 'Archive',
    FileKind.code => 'Code',
    FileKind.font => 'Font',
    FileKind.disk => 'Disk image',
    FileKind.ebook => 'E-book',
    FileKind.executable => 'Executable',
    FileKind.other => 'File',
  };

  // 확장자 우선(MIME 조회보다 커버리지가 넓음), 모르면 MIME 접두사로 폴백
  static FileKind of(String fileName, {String? mimeType}) {
    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final byExt = _byExtension[ext];
    if (byExt != null) return byExt;

    final mime = mimeType ?? '';
    if (mime.startsWith('image/')) return FileKind.image;
    if (mime.startsWith('video/')) return FileKind.video;
    if (mime.startsWith('audio/')) return FileKind.audio;
    if (mime.startsWith('text/')) return FileKind.document;
    if (mime.contains('pdf')) return FileKind.pdf;
    if (mime.contains('zip') || mime.contains('compressed')) {
      return FileKind.archive;
    }
    return FileKind.other;
  }

  static const Map<String, FileKind> _byExtension = <String, FileKind>{
    'jpg': FileKind.image,
    'jpeg': FileKind.image,
    'png': FileKind.image,
    'gif': FileKind.image,
    'bmp': FileKind.image,
    'webp': FileKind.image,
    'heic': FileKind.image,
    'heif': FileKind.image,
    'tiff': FileKind.image,
    'svg': FileKind.image,
    'ico': FileKind.image,
    'dng': FileKind.image,
    'raw': FileKind.image,
    'psd': FileKind.image,
    'mp4': FileKind.video,
    'mov': FileKind.video,
    'mkv': FileKind.video,
    'avi': FileKind.video,
    'webm': FileKind.video,
    'flv': FileKind.video,
    'm4v': FileKind.video,
    'wmv': FileKind.video,
    'mpg': FileKind.video,
    'mpeg': FileKind.video,
    '3gp': FileKind.video,
    'mp3': FileKind.audio,
    'wav': FileKind.audio,
    'flac': FileKind.audio,
    'aac': FileKind.audio,
    'ogg': FileKind.audio,
    'm4a': FileKind.audio,
    'opus': FileKind.audio,
    'aiff': FileKind.audio,
    'wma': FileKind.audio,
    'pdf': FileKind.pdf,
    'doc': FileKind.document,
    'docx': FileKind.document,
    'odt': FileKind.document,
    'rtf': FileKind.document,
    'txt': FileKind.document,
    'md': FileKind.document,
    'pages': FileKind.document,
    'tex': FileKind.document,
    'xls': FileKind.spreadsheet,
    'xlsx': FileKind.spreadsheet,
    'ods': FileKind.spreadsheet,
    'csv': FileKind.spreadsheet,
    'numbers': FileKind.spreadsheet,
    'ppt': FileKind.presentation,
    'pptx': FileKind.presentation,
    'odp': FileKind.presentation,
    'key': FileKind.presentation,
    'zip': FileKind.archive,
    'rar': FileKind.archive,
    '7z': FileKind.archive,
    'tar': FileKind.archive,
    'gz': FileKind.archive,
    'tgz': FileKind.archive,
    'bz2': FileKind.archive,
    'xz': FileKind.archive,
    'zst': FileKind.archive,
    'dart': FileKind.code,
    'js': FileKind.code,
    'ts': FileKind.code,
    'py': FileKind.code,
    'java': FileKind.code,
    'kt': FileKind.code,
    'swift': FileKind.code,
    'c': FileKind.code,
    'h': FileKind.code,
    'cpp': FileKind.code,
    'cs': FileKind.code,
    'go': FileKind.code,
    'rs': FileKind.code,
    'rb': FileKind.code,
    'php': FileKind.code,
    'sh': FileKind.code,
    'json': FileKind.code,
    'yaml': FileKind.code,
    'yml': FileKind.code,
    'xml': FileKind.code,
    'html': FileKind.code,
    'css': FileKind.code,
    'sql': FileKind.code,
    'ttf': FileKind.font,
    'otf': FileKind.font,
    'woff': FileKind.font,
    'woff2': FileKind.font,
    'iso': FileKind.disk,
    'dmg': FileKind.disk,
    'img': FileKind.disk,
    'epub': FileKind.ebook,
    'mobi': FileKind.ebook,
    'azw3': FileKind.ebook,
    'exe': FileKind.executable,
    'msi': FileKind.executable,
    'apk': FileKind.executable,
    'deb': FileKind.executable,
    'rpm': FileKind.executable,
    'appimage': FileKind.executable,
    'app': FileKind.executable,
  };
}
