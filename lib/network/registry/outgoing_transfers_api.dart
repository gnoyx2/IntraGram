part of 'outgoing_transfers.dart';

extension OutgoingTransfersApi on OutgoingTransfers {
  Future<void> offerFile(String conversationId, PlatformFile file) =>
      _offerPicked(conversationId, file, null, null);

  // 파일마다 따로 offer하고 'n / 전체' 라벨만 붙음
  Future<void> offerFiles(
    String conversationId,
    List<PlatformFile> files,
  ) async {
    final batchId = files.length > 1 ? newId() : null;
    for (var i = 0; i < files.length; i++) {
      await _offerPicked(
        conversationId,
        files[i],
        files.length > 1 ? '${i + 1} / ${files.length}' : null,
        batchId,
      );
    }
  }

  // 데스크톱 끌어 놓기. 사라진 경로는 빈 파일로 안 내고 건너뜀
  Future<void> offerFilesFromPaths(
    String conversationId,
    List<String> paths,
  ) async {
    final present = paths.where((path) => File(path).existsSync()).toList();
    final batchId = present.length > 1 ? newId() : null;
    for (var i = 0; i < present.length; i++) {
      final path = present[i];
      final size = File(path).lengthSync();
      await _offer(
        conversationId: conversationId,
        name: p.basename(path),
        path: path,
        size: size,
        openStream: () => File(path).openRead(),
        batchLabel: present.length > 1 ? '${i + 1} / ${present.length}' : null,
        batchId: batchId,
        thumbFactory: () => _thumbForPath(path, p.basename(path), size),
      );
    }
  }

  // 모바일 첨부 하나: file_picker 캐시 사본 대신 네이티브 스트림을 그대로 씀 (디스크·캐시에 안 남김)
  Future<void> offerStreamSource({
    required String conversationId,
    required String name,
    required int size,
    required Stream<List<int>> Function() openStream,
    String? batchLabel,
    String? batchId,
    String? mime,
    Future<void> Function()? releaseSource,
  }) => _offer(
    conversationId: conversationId,
    name: name,
    path: null,
    size: size,
    openStream: openStream,
    batchLabel: batchLabel,
    batchId: batchId,
    mime: mime,
    releaseSource: releaseSource,
  );

  // 긴 메시지를 .txt로: 디스크엔 안 쓰고 RAM에서 흘림
  Future<void> offerInlineText(
    String conversationId,
    String name,
    String text,
  ) {
    final bytes = utf8.encode(text);
    return _offer(
      conversationId: conversationId,
      name: name,
      path: null,
      size: bytes.length,
      openStream: () => Stream<List<int>>.value(bytes),
      batchLabel: null,
      preview: _previewOf(bytes),
    );
  }

  // 앞부분 미리보기. 글자 중간에서 잘려도 대체 문자 하나로 끝남 (allowMalformed)
  static String _previewOf(List<int> bytes) => utf8.decode(
    bytes.length <= kSpillPreviewBytes
        ? bytes
        : bytes.sublist(0, kSpillPreviewBytes),
    allowMalformed: true,
  );

  Future<void> _offerPicked(
    String conversationId,
    PlatformFile file,
    String? batchLabel,
    String? batchId,
  ) async {
    final size = file.lengthSync() ?? await file.length();
    await _offer(
      conversationId: conversationId,
      name: file.name,
      path: file.path,
      size: size,
      openStream: () => file.readAsByteStream(),
      batchLabel: batchLabel,
      batchId: batchId,
      thumbFactory: () => _thumbForPath(file.path, file.name, size),
    );
  }
}
