part of '../chat_room_screen.dart';

mixin _ChatRoomDragDrop on _ChatRoomScreenStateBase {
  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  Future<void> _attach() async {
    // 데스크톱엔 사진첩 앱이 없고 file_picker의 "이미지" 필터도 같은 파일 브라우저를 확장자만 걸러
    // 보여줄 뿐이라, 시트를 건너뛰고 파일 브라우저로 바로 감 (드래그 앤 드롭이 이미지 붙여넣기 경로를 대신함)
    if (_isDesktop) {
      await _pickAndOffer(type: FileType.any);
      return;
    }
    final choice = await showAttachSheet(context);
    switch (choice) {
      case null:
        return;
      case AttachChoice.file:
        await _pickMobileAndOffer(imagesOnly: false);
      case AttachChoice.photoLibrary:
        await _pickMobileAndOffer(imagesOnly: true);
    }
  }

  Future<void> _pickAndOffer({required FileType type}) async {
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: type,
        dialogTitle: S.of(context).t('chat.sendFilesTitle'),
      );
    } on Exception {
      if (mounted) showPickerUnavailable(context);
      return;
    }
    if (files.isEmpty || !mounted) return;
    await _registry.offerFiles(widget.conversationId, files);
  }

  // 모바일 전용 zero-disk 첨부: file_picker의 앱 캐시
  // 복사 대신 네이티브 MobileFileSource로 바로 스트리밍함
  Future<void> _pickMobileAndOffer({required bool imagesOnly}) async {
    final List<MobileFileSource> sources;
    try {
      sources = await MobileFileSource.pick(imagesOnly: imagesOnly);
    } on PlatformException {
      // 사진을 못 받았거나 RAM 상한을 넘김: 조용히 사라지지 않게 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).t('attach.failed'))),
        );
      }
      return;
    }
    if (sources.isEmpty) return;
    if (!mounted) {
      // 선택기가 열려 있는 동안 화면이 닫힘: 아무도 제안하지 않을 소스의 native 권한을 바로 놓음
      await MobileFileSource.releaseEach(sources);
      return;
    }
    await _registry.offerStreamSources(widget.conversationId, sources);
  }

  void _onDrop(List<DropItem> items) {
    setState(() => _dragging = false);
    final paths = _flattenDrop(items);
    if (paths.isNotEmpty) {
      _registry.offerFilesFromPaths(widget.conversationId, paths);
    }
  }
}

// 드롭에 폴더가 섞일 수 있어서 안으로 들어가고, 읽을 시점에 아직 존재하는 경로만 남김
List<String> _flattenDrop(List<DropItem> items) {
  final out = <String>[];
  for (final item in items) {
    if (item is DropItemDirectory) {
      out.addAll(_flattenDrop(item.children));
    } else if (File(item.path).existsSync()) {
      out.add(item.path);
    }
  }
  return out;
}
