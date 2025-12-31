import 'package:camera/camera.dart';
import 'package:dartz/dartz.dart';
import '../../core/errors/failures.dart';
import '../entities/detection_result.dart';
import '../repositories/id_detection_repository.dart';

class DetectIdUseCase {
  DetectIdUseCase(this.repository);

  final IdDetectionRepository repository;

  Future<Either<Failure, List<DetectionResult>>> call(
    CameraImage cameraImage,
  ) async {
    return await repository.detectId(cameraImage);
  }
}

