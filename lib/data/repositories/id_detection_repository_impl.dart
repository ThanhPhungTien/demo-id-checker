import 'package:camera/camera.dart';
import 'package:dartz/dartz.dart';
import '../../core/errors/failures.dart';
import '../../domain/entities/detection_result.dart';
import '../../domain/repositories/id_detection_repository.dart';
import '../datasources/camera_data_source.dart';
import '../datasources/tflite_data_source.dart';

class IdDetectionRepositoryImpl implements IdDetectionRepository {
  IdDetectionRepositoryImpl({
    required this.tfliteDataSource,
    required this.cameraDataSource,
  });

  final TFLiteDataSource tfliteDataSource;
  final CameraDataSource cameraDataSource;

  @override
  Future<Either<Failure, void>> initializeModel() async {
    try {
      await tfliteDataSource.initialize();
      return const Right(null);
    } catch (e) {
      return Left(ModelLoadFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<DetectionResult>>> detectId(
    CameraImage cameraImage,
  ) async {
    try {
      final controller = cameraDataSource.controller;
      if (controller == null || !controller.value.isInitialized) {
        return const Left(CameraFailure('Camera not initialized'));
      }

      final imageWidth = cameraImage.width;
      final imageHeight = cameraImage.height;

      final results = await tfliteDataSource.detect(
        cameraImage,
        imageWidth,
        imageHeight,
      );

      return Right(results);
    } on Exception catch (e) {
      return Left(TFLiteFailure(e.toString()));
    } catch (e) {
      return Left(TFLiteFailure('Unknown error: $e'));
    }
  }

  @override
  Future<void> disposeModel() async {
    tfliteDataSource.dispose();
  }
}

