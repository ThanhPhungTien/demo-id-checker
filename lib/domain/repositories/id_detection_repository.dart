import 'package:camera/camera.dart';
import 'package:dartz/dartz.dart';
import '../../core/errors/failures.dart';
import '../entities/detection_result.dart';

abstract class IdDetectionRepository {
  Future<Either<Failure, List<DetectionResult>>> detectId(
    CameraImage cameraImage,
  );
  Future<Either<Failure, void>> initializeModel();
  Future<void> disposeModel();
}

