import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart'
    show compute, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import 'package:intragram/core/qr_decode.dart';
import 'camera_unavailable.dart';
import 'scanner_frame.dart';

export 'camera_unavailable.dart';

// QR 스캔 화면 몸통: 뒤 카메라 미리보기 + 조준틀 + 안내. 프레임의 밝기 평면을 백그라운드 isolate에서
// 순수 Dart로 풂(decodeQr). 카메라를 못 쓰면(데스크톱, 권한 거부, 카메라 없음) 조준틀 없이 대안 경로 문구를
// 보여 주고, 권한 거부면 설정 열기를 붙임
class ScannerView extends StatefulWidget {
  const ScannerView({
    required this.onCode,
    required this.hint,
    required this.noCamera,
    required this.reticleSide,
    required this.reticleRadius,
    super.key,
  });

  // 읽은 QR 글. 찾던 코드면 true를 돌려줌: 그 뒤로는 더 안 읽음
  final bool Function(String raw) onCode;
  final String hint;
  final String noCamera;
  final double reticleSide;
  final double reticleRadius;

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

enum _Problem { noCamera, denied }

class _ScannerViewState extends State<ScannerView> with WidgetsBindingObserver {
  // 한 장 푸는 동안 오는 프레임은 버리고, 풀기 사이도 이만큼은 띄움 (배터리·발열)
  static const _frameGap = Duration(milliseconds: 150);

  static bool get _hasCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  CameraController? _camera;
  _Problem? _problem;
  bool _decoding = false;
  bool _done = false;
  bool _disposed = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  // 앱이 앞에 있는지, 그리고 권한 창(비활성)만이 아니라 앱을 떠났다 왔는지 (설정에서 권한을 켤 기회)
  bool _foreground = true;
  bool _wentAway = false;

  // 열기·닫기는 한 번에 하나: 그사이 바뀐 상태는 끝난 뒤 다시 맞춤
  bool _busy = false;
  bool _again = false;

  @override
  void initState() {
    super.initState();
    if (!_hasCamera) return;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _done = true;
    _disposed = true;
    unawaited(_sync()); // 열리는 중이면 다 열린 뒤 닫힘
    super.dispose();
  }

  // 앱을 떠나면 카메라를 놓고(다른 앱이 쓸 수 있게) 돌아오면 다시 엶. 거부·카메라 없음은 설정 등에 다녀왔을 때만
  // 다시 시도함: 권한 창이 닫히며 오는 복귀마다 다시 열면 Android가 같은 권한을 연달아 물음
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        if (_wentAway) _problem = null;
        _wentAway = false;
      case AppLifecycleState.inactive:
        _foreground = false;
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _foreground = false;
        _wentAway = true;
    }
    unawaited(_sync());
  }

  // 지금 원하는 상태(화면이 살아 있고 앞에 있고 문제가 없으면 카메라 켬)로 맞춤
  Future<void> _sync() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        final want = !_done && _foreground && _problem == null;
        if (want && _camera == null) {
          await _open();
        } else if (!want && _camera != null) {
          await _release();
          _refresh();
        }
      } while (_again);
    } finally {
      _busy = false;
    }
  }

  Future<void> _open() async {
    final CameraDescription? back;
    try {
      final cameras = await availableCameras();
      back =
          cameras.firstWhereOrNull(
            (c) => c.lensDirection == CameraLensDirection.back,
          ) ??
          cameras.firstOrNull;
    } on CameraException {
      _fail(_Problem.noCamera);
      return;
    }
    // 목록을 기다리는 사이 화면을 닫았거나 앱을 떠났으면 열지 않음 (_sync가 다시 맞춤)
    if (_done || !_foreground) return;
    if (back == null) {
      _fail(_Problem.noCamera);
      return;
    }
    // Y 평면만 쓰는 형식(Android YUV_420_888, iOS 420 bi-planar). 마이크는 안 씀
    final camera = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _camera = camera;
    try {
      await camera.initialize();
      await camera.startImageStream(_onFrame);
    } on CameraException catch (e) {
      _camera = null;
      await camera.dispose();
      // Android CameraAccessDenied, iOS CameraAccessDenied·DeniedWithoutPrompt·Restricted
      _fail(
        e.code.startsWith('CameraAccess') ? _Problem.denied : _Problem.noCamera,
      );
      return;
    }
    _refresh();
  }

  // 카메라를 놓음. CameraController.dispose는 프레임 구독을 안 끊어서 먼저 멈춤
  Future<void> _release() async {
    final camera = _camera;
    _camera = null;
    if (camera == null) return;
    if (camera.value.isStreamingImages) {
      try {
        await camera.stopImageStream();
      } on CameraException {
        // 이미 닫히는 중: 아래 dispose가 세션째 정리함
      }
    }
    await camera.dispose();
  }

  void _fail(_Problem problem) {
    _problem = problem;
    _refresh();
  }

  void _refresh() {
    if (!_disposed && mounted) setState(() {});
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_decoding || _done || now.difference(_lastFrame) < _frameGap) return;
    _decoding = true;
    _lastFrame = now;
    final luma = image.planes.first;
    final frame = QrFrame(
      luma: Uint8List.fromList(luma.bytes),
      width: image.width,
      height: image.height,
      rowStride: luma.bytesPerRow,
    );
    unawaited(
      compute(decodeQr, frame).then(_onDecoded).whenComplete(() {
        _decoding = false;
      }),
    );
  }

  void _onDecoded(String? raw) {
    if (raw == null || _done) return;
    if (!widget.onCode(raw)) return;
    _done = true;
    unawaited(_sync());
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    if (!_hasCamera || problem != null) {
      return CameraUnavailable(
        text: widget.noCamera,
        denied: problem == _Problem.denied,
      );
    }
    final camera = _camera;
    final size = camera?.value.previewSize;
    if (camera == null || !camera.value.isInitialized || size == null) {
      return const ColoredBox(color: Colors.black);
    }
    return ScannerFrame(
      camera: camera,
      previewSize: size,
      hint: widget.hint,
      reticleSide: widget.reticleSide,
      reticleRadius: widget.reticleRadius,
    );
  }
}
