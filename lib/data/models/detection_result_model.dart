import '../../domain/entities/detection_result.dart';

class DetectionResultModel extends DetectionResult {
  const DetectionResultModel({
    required super.boundingBox,
    required super.confidence,
    required super.classLabel,
  });

  factory DetectionResultModel.fromTFLiteOutput(
    List<dynamic> output,
    int imageWidth,
    int imageHeight,
    int modelInputWidth,
    int modelInputHeight,
  ) {
    final x = (output[0] as num).toDouble();
    final y = (output[1] as num).toDouble();
    final width = (output[2] as num).toDouble();
    final height = (output[3] as num).toDouble();
    final confidence = (output[4] as num).toDouble();
    final classIndex = (output[5] as num).toInt();

    final scaleX = imageWidth / modelInputWidth;
    final scaleY = imageHeight / modelInputHeight;

    final boundingBox = BoundingBox(
      x: x * scaleX,
      y: y * scaleY,
      width: width * scaleX,
      height: height * scaleY,
    );

    final classLabel = _getClassLabel(classIndex);

    return DetectionResultModel(
      boundingBox: boundingBox,
      confidence: confidence,
      classLabel: classLabel,
    );
  }

  static String _getClassLabel(int classIndex) {
    switch (classIndex) {
      case 0:
        return 'CCCD';
      case 1:
        return 'Passport';
      default:
        return 'Unknown';
    }
  }
}

