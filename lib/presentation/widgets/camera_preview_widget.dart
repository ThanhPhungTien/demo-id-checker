import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

enum CameraPreviewFit {
  contain,
  cover,
}

class CameraPreviewWidget extends StatelessWidget {
  const CameraPreviewWidget({
    required this.controller,
    this.coverScaleMultiplier = 1,
    this.fit = CameraPreviewFit.contain,
    this.overlay,
    super.key,
  });

  final CameraController controller;
  final double coverScaleMultiplier;
  final CameraPreviewFit fit;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (fit == CameraPreviewFit.contain) {
      return Center(
        child: CameraPreview(
          controller,
          child: overlay,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenAspectRatio = constraints.maxWidth / constraints.maxHeight;
        var coverScale = controller.value.aspectRatio / screenAspectRatio;
        if (coverScale < 1) {
          coverScale = 1 / coverScale;
        }
        final scale = coverScale * coverScaleMultiplier;

        return ClipRect(
          child: Transform.scale(
            scale: scale,
            child: Center(
              child: CameraPreview(
                controller,
                child: overlay,
              ),
            ),
          ),
        );
      },
    );
  }
}
