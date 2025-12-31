import 'package:equatable/equatable.dart';

class DetectionResult extends Equatable {
  const DetectionResult({
    required this.boundingBox,
    required this.confidence,
    required this.classLabel,
  });

  final BoundingBox boundingBox;
  final double confidence;
  final String classLabel;

  @override
  List<Object> get props => [boundingBox, confidence, classLabel];
}

class BoundingBox extends Equatable {
  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  @override
  List<Object> get props => [x, y, width, height];
}

