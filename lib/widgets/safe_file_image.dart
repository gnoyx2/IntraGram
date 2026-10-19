import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/safe_image_decode.dart';

class SafeFileImage extends StatefulWidget {
  const SafeFileImage({
    required this.path,
    required this.fit,
    required this.placeholder,
    this.width,
    this.height,
    super.key,
  });

  final String path;
  final BoxFit fit;
  final Widget placeholder;
  final int? width;
  final int? height;

  @override
  State<SafeFileImage> createState() => _SafeFileImageState();
}

class _SafeFileImageState extends State<SafeFileImage> {
  late Future<bool> _safe = isSafeToDecodeImage(widget.path);

  @override
  void didUpdateWidget(SafeFileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _safe = isSafeToDecodeImage(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _safe,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done ||
          snapshot.data != true) {
        return widget.placeholder;
      }
      return Image(
        image: OsPrivacy.trackImage(
          widget.path,
          ResizeImage(
            FileImage(File(widget.path)),
            width: widget.width,
            height: widget.height,
            policy: ResizeImagePolicy.fit,
          ),
        ),
        fit: widget.fit,
        errorBuilder: (_, _, _) => widget.placeholder,
      );
    },
  );
}
