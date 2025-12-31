import 'package:equatable/equatable.dart';
import 'package:camera/camera.dart';
import 'dart:ui' show Size;
import '../../domain/entities/detection_result.dart';

abstract class IdScannerState extends Equatable {
  const IdScannerState();

  @override
  List<Object?> get props => [];
}

class IdScannerInitial extends IdScannerState {
  const IdScannerInitial();
}

class IdScannerLoading extends IdScannerState {
  const IdScannerLoading();
}

class IdScannerReady extends IdScannerState {
  const IdScannerReady(this.controller);

  final CameraController controller;

  @override
  List<Object?> get props => [controller];
}

class IdScannerDetecting extends IdScannerState {
  const IdScannerDetecting(this.controller);

  final CameraController controller;

  @override
  List<Object?> get props => [controller];
}

class IdScannerDetected extends IdScannerState {
  const IdScannerDetected({
    required this.controller,
    required this.detections,
    required this.sourceImageSize,
  });

  final CameraController controller;
  final List<DetectionResult> detections;
  final Size sourceImageSize;

  @override
  List<Object?> get props => [controller, detections, sourceImageSize];
}

class IdScannerError extends IdScannerState {
  const IdScannerError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

