import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../core/utils/app_logger.dart';

class CameraDataSource {
  CameraDataSource();

  CameraController? _controller;
  List<CameraDescription>? _cameras;

  Future<List<CameraDescription>> getAvailableCameras() async {
    if (_cameras != null) {
      return _cameras!;
    }
    _cameras = await availableCameras();
    AppLogger.info('Available cameras: ${_cameras!.length}', name: 'camera');
    return _cameras!;
  }

  Future<CameraController> initializeCamera() async {
    final cameras = await getAvailableCameras();
    if (cameras.isEmpty) {
      throw Exception('No cameras available');
    }

    final selectedCamera = cameras[0];
    AppLogger.info(
      'Initializing camera: ${selectedCamera.name} (lens: ${selectedCamera.lensDirection})',
      name: 'camera',
    );

    final imageFormatGroup = defaultTargetPlatform == TargetPlatform.iOS
        ? ImageFormatGroup.bgra8888
        : ImageFormatGroup.yuv420;

    _controller = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: imageFormatGroup,
    );

    await _controller!.initialize();
    AppLogger.info(
      'Camera initialized. aspectRatio=${_controller!.value.aspectRatio}, '
      'previewSize=${_controller!.value.previewSize}',
      name: 'camera',
    );
    return _controller!;
  }

  CameraController? get controller => _controller;

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}

