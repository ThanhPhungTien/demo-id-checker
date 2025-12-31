import 'package:equatable/equatable.dart';
import 'package:camera/camera.dart';

abstract class IdScannerEvent extends Equatable {
  const IdScannerEvent();

  @override
  List<Object> get props => [];
}

class InitializeCamera extends IdScannerEvent {
  const InitializeCamera();
}

class StartDetection extends IdScannerEvent {
  const StartDetection();
}

class StopDetection extends IdScannerEvent {
  const StopDetection();
}

class ProcessFrame extends IdScannerEvent {
  const ProcessFrame(this.cameraImage);

  final CameraImage cameraImage;

  @override
  List<Object> get props => [cameraImage];
}

class InitializeModel extends IdScannerEvent {
  const InitializeModel();
}

