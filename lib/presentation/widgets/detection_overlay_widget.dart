import 'package:flutter/material.dart';
import '../../domain/entities/detection_result.dart';
import '../../core/constants/app_constants.dart';

class DetectionOverlayWidget extends StatelessWidget {
  const DetectionOverlayWidget({
    required this.detections,
    required this.imageSize,
    super.key,
  });

  final List<DetectionResult> detections;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      painter: DetectionPainter(
        detections: detections,
        imageSize: imageSize,
      ),
      child: Container(),
    );
  }
}

class DetectionPainter extends CustomPainter {
  DetectionPainter({
    required this.detections,
    required this.imageSize,
  });

  final List<DetectionResult> detections;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (final detection in detections) {
      if (detection.confidence < AppConstants.detectionConfidenceThreshold) {
        continue;
      }

      final boundingBox = detection.boundingBox;
      final rect = Rect.fromLTWH(
        boundingBox.x * scaleX,
        boundingBox.y * scaleY,
        boundingBox.width * scaleX,
        boundingBox.height * scaleY,
      );

      final paint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawRect(rect, paint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${detection.classLabel}\n${(detection.confidence * 100).toStringAsFixed(1)}%',
          style: const TextStyle(
            color: Colors.green,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 2,
                color: Colors.black,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(rect.left, rect.top - textPainter.height - 5),
      );
    }
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageSize != imageSize;
  }
}

