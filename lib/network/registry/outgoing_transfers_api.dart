part of 'outgoing_transfers.dart';

extension OutgoingTransfersApi on OutgoingTransfers {
  Future<void> offerFile(String conversationId, PlatformFile file) =>
      _offerPicked(conversationId, file, null, null);

  // 각 파일은 평범한 독립 file_offer이고, 유일한 차이는 전송 타일마다
  // "n / total" 위치를 보여줘서 받는 쪽이 배치 진행을 보는 것
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

  // 데스크톱 드래그 앤 드롭 진입점. 더 이상 없는 경로는 빈 파일로 제안하지 않고 건너뜀
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

  // 모바일 zero-disk 첨부(MobileFileSource) 하나를 파일 제안으로:
  // file_picker의 캐시 복사 경로 대신 네이티브 메모리 스트리밍 소스를 그대로
  // 씀
  // (보내는 쪽 디스크/앱 캐시엔 아무것도 안 씀)
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

  // spillToFile 모드의 긴 메시지: 보내는 쪽 디스크엔 아무것도 안 쓰고(source
  // 스트림이 바이트를 RAM에서 흘림) 받는 쪽은 평범한 .txt 파일 제안으로 봄
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

  // 앞부분 kSpillPreviewBytes바이트 스니펫. allowMalformed라 멀티바이트
  // 문자 중간에서 잘려도 그 경계에 대체 문자 하나가 남을 뿐 throw 안 함 (미리보기용이라 충분)
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
