part of '../chat_input.dart';

// 입력창이 포커스를 얻을 때마다 클립보드의 텍스트/이미지/파일 유무를 확인해서 해당 퀵 버튼만 띄움
// 유무는 내용을 안 읽는 OS API로만 봄 (텍스트 hasStrings, 이미지·파일은 OsPrivacy.clipboardKinds).
// 내용은 붙여넣기를 눌렀을 때만 읽음. 종류만 물을 방법이 없는 Linux만 내용으로 확인함
mixin _ChatInputClipboard on _ChatInputStateBase {
  Future<void> _refreshClipboard() async {
    bool has;
    try {
      has = await Clipboard.hasStrings();
    } on PlatformException {
      has = false;
    } on MissingPluginException {
      has = false;
    }
    if (!mounted) return;
    if (has != _hasClipboardText) setState(() => _hasClipboardText = has);
    // 이미지/파일 프로브는 따로 돌림: 텍스트 버튼이 다른 채널 왕복을 안 기다리게 함
    unawaited(_refreshClipboardKinds());
  }

  // 데스크톱만: Pasteboard.files()가 Android에선 content URI를 줘서 못 씀 (데스크톱은 진짜 경로)
  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  Future<void> _refreshClipboardKinds() async {
    final wantImage = widget.onSendImage != null;
    final wantFiles = widget.onAttachPaths != null && _isDesktop;
    if (!wantImage && !wantFiles) return;
    final kinds =
        await OsPrivacy.clipboardKinds() ??
        (
          image: wantImage && await _imageByContent() != null,
          files: wantFiles && (await _filesByContent()).isNotEmpty,
        );
    if (!mounted) return;
    final hasImage = wantImage && kinds.image;
    final hasFiles = wantFiles && kinds.files;
    if (hasImage != _hasClipboardImage || hasFiles != _hasClipboardFiles) {
      setState(() {
        _hasClipboardImage = hasImage;
        _hasClipboardFiles = hasFiles;
      });
    }
  }

  Future<List<String>> _filesByContent() async {
    try {
      return await Pasteboard.files();
    } on Object {
      return const <String>[];
    }
  }

  // Windows는 플러그인이 %TEMP%에 BMP를 쓰니 메모리에서 바로 읽음
  Future<Uint8List?> _imageByContent() async {
    if (Platform.isWindows) return WindowsClipboard.readImage();
    try {
      return await Pasteboard.image;
    } on Object {
      return null;
    }
  }

  Future<void> _pasteFiles() async {
    final onAttachPaths = widget.onAttachPaths;
    if (!widget.enabled || onAttachPaths == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final files = await _filesByContent();
    if (files.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.t('input.clipboardEmpty'))),
      );
      if (mounted) setState(() => _hasClipboardFiles = false);
      return;
    }
    onAttachPaths(files);
  }

  Future<void> _pasteImage() async {
    final onSendImage = widget.onSendImage;
    if (!widget.enabled || onSendImage == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final bytes = await _imageByContent();
    if (bytes == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.t('input.noClipboardImage'))),
      );
      if (mounted) setState(() => _hasClipboardImage = false);
      return;
    }
    onSendImage(bytes);
  }

  Future<void> _pasteAndSend() async {
    if (!widget.enabled) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      text = null;
    } on MissingPluginException {
      text = null;
    }
    final trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.t('input.clipboardEmpty'))),
      );
      if (mounted) setState(() => _hasClipboardText = false);
      return;
    }
    widget.onSend(trimmed);
  }
}
