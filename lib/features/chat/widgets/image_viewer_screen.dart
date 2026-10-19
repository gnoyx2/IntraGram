import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/motion.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/safe_file_image.dart';
import 'package:intragram/widgets/share_origin.dart';

part 'image_viewer_screen/top_bar.dart';

class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({required this.path, super.key});

  final String path;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _dismissThreshold = 120.0;
  static const _dismissFadeExtent = 300.0;
  static const _doubleTapScale = 2.5;

  final TransformationController _zoomController = TransformationController();
  late final AnimationController _snapBackController;
  Animation<Offset>? _snapBackAnimation;

  Offset? _dragStart;
  Offset _dragOffset = Offset.zero;
  TapDownDetails? _doubleTapDetails;
  bool _chromeVisible = true;

  // 눌려 있는 포인터 id들. Listener는 제스처 아레나를 안 거치고 raw 포인터를 다 받아서,
  // 이걸로 안 거르면 핀치 중 한 손가락의 움직임을 "아래로 스와이프해서 닫기"로 착각해 배경이 튐
  final Set<int> _pointers = <int>{};

  bool get _isZoomed => _zoomController.value.getMaxScaleOnAxis() > 1.01;

  @override
  void initState() {
    super.initState();
    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _zoomController.dispose();
    _snapBackController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (_pointers.length > 1 || _isZoomed) {
      _dragStart = null;
      if (_dragOffset != Offset.zero) setState(() => _dragOffset = Offset.zero);
      return;
    }
    _dragStart = event.position;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final start = _dragStart;
    if (start == null || _pointers.length > 1 || _isZoomed) return;
    setState(() => _dragOffset = event.position - start);
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) _endDrag();
  }

  void _endDrag() {
    final start = _dragStart;
    _dragStart = null;
    if (start == null) return;
    if (_dragOffset.dy.abs() > _dismissThreshold) {
      Navigator.of(context).pop();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _dragOffset = Offset.zero);
      return;
    }
    _snapBackAnimation =
        Tween<Offset>(begin: _dragOffset, end: Offset.zero).animate(
          CurvedAnimation(parent: _snapBackController, curve: Curves.easeOut),
        )..addListener(
          () => setState(() => _dragOffset = _snapBackAnimation!.value),
        );
    _snapBackController.forward(from: 0);
  }

  void _onDoubleTapDown(TapDownDetails details) => _doubleTapDetails = details;

  void _onDoubleTap() {
    if (_isZoomed) {
      _zoomController.value = Matrix4.identity();
      return;
    }
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;
    _zoomController.value = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (_doubleTapScale - 1),
        -position.dy * (_doubleTapScale - 1),
        0,
        1,
      )
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, _doubleTapScale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final isMobile = Platform.isIOS || Platform.isAndroid;
    final fade = (_dragOffset.dy.abs() / _dismissFadeExtent).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - fade * 0.7),
      body: Stack(
        children: [
          Listener(
            key: const Key('imageViewerDismissListener'),
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: Transform.translate(
              key: const Key('imageViewerDismissTranslate'),
              offset: _dragOffset,
              child: GestureDetector(
                onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                onDoubleTapDown: _onDoubleTapDown,
                onDoubleTap: _onDoubleTap,
                child: InteractiveViewer(
                  transformationController: _zoomController,
                  minScale: 1,
                  maxScale: 4,
                  // fit·크기를 명시해야 썸네일 크롭에서 flight가 끝날 때 원본 크기로 튀지 않음
                  child: SizedBox.expand(
                    child: Hero(
                      tag: widget.path,
                      child: SafeFileImage(
                        path: widget.path,
                        fit: BoxFit.contain,
                        width: (size.width * dpr).round().clamp(1, 4096),
                        height: (size.height * dpr).round().clamp(1, 4096),
                        placeholder: const Icon(
                          Icons.insert_drive_file_outlined,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: motionDuration(context, AppMotion.press),
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                    stops: [0.9, 1],
                  ),
                ),
                child: SafeArea(
                  child: _ViewerTopBar(path: widget.path, canShare: isMobile),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _chromeVisible ? 1 : 0,
              duration: motionDuration(context, AppMotion.press),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                      stops: [0.9, 1],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        p.basename(widget.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
