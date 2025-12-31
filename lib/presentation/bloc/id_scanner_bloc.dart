import 'dart:async';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/utils/app_logger.dart';
import '../../core/errors/failures.dart';
import '../../data/datasources/camera_data_source.dart';
import '../../data/datasources/tflite_data_source.dart';
import '../../data/repositories/id_detection_repository_impl.dart';
import '../../domain/entities/detection_result.dart';
import '../../domain/repositories/id_detection_repository.dart';
import 'id_scanner_event.dart';
import 'id_scanner_state.dart';

class IdScannerBloc extends Bloc<IdScannerEvent, IdScannerState> {
  IdScannerBloc() : super(const IdScannerInitial()) {
    _cameraDataSource = CameraDataSource();
    _tfliteDataSource = TFLiteDataSource();
    _repository = IdDetectionRepositoryImpl(
      cameraDataSource: _cameraDataSource,
      tfliteDataSource: _tfliteDataSource,
    );

    on<InitializeModel>(_onInitializeModel);
    on<InitializeCamera>(_onInitializeCamera);
    on<StartDetection>(_onStartDetection);
    on<StopDetection>(_onStopDetection);
    on<ProcessFrame>(_onProcessFrame);
  }

  late final CameraDataSource _cameraDataSource;
  late final TFLiteDataSource _tfliteDataSource;
  late final IdDetectionRepository _repository;
  bool _isDetecting = false;
  bool _isProcessingFrame = false;
  int _droppedFrameCount = 0;
  int _frameCounter = 0;
  DateTime? _lastUiEmitAt;
  DateTime? _lastDetectedAt;
  Size? _lastDetectedSourceSize;
  double? _lastDetectedConfidence;
  final List<_RecentDetectionCandidate> _recentCandidates = [];
  DateTime? _lastInferenceRequestedAt;

  Future<void> _onInitializeModel(
    InitializeModel event,
    Emitter<IdScannerState> emit,
  ) async {
    try {
      AppLogger.info('Initialize model requested', name: 'bloc');
      final result = await _repository.initializeModel();
      result.fold(
        (failure) {
          AppLogger.error(
            'Model init failed: ${failure.message}',
            name: 'bloc',
            error: failure,
          );
          emit(IdScannerError(failure.message ?? 'Model load failed'));
        },
        (_) => AppLogger.info('Model init OK', name: 'bloc'),
      );
    } catch (e) {
      AppLogger.error('Initialize model exception: $e', name: 'bloc', error: e);
      emit(IdScannerError('Failed to initialize model: $e'));
    }
  }

  Future<void> _onInitializeCamera(
    InitializeCamera event,
    Emitter<IdScannerState> emit,
  ) async {
    emit(const IdScannerLoading());
    try {
      AppLogger.info('Initialize camera requested', name: 'bloc');
      final controller = await _cameraDataSource.initializeCamera();
      AppLogger.info(
        'Camera ready. aspectRatio=${controller.value.aspectRatio}, previewSize=${controller.value.previewSize}',
        name: 'bloc',
      );
      emit(IdScannerReady(controller));
    } catch (e) {
      AppLogger.error('Initialize camera failed: $e', name: 'bloc', error: e);
      emit(IdScannerError('Failed to initialize camera: $e'));
    }
  }

  Future<void> _onStartDetection(
    StartDetection event,
    Emitter<IdScannerState> emit,
  ) async {
    if (_isDetecting) {
      return;
    }

    final currentState = state;
    if (currentState is! IdScannerReady) {
      return;
    }

    _isDetecting = true;
    _isProcessingFrame = false;
    _droppedFrameCount = 0;
    _frameCounter = 0;
    _lastUiEmitAt = null;
    _lastDetectedAt = null;
    _lastDetectedSourceSize = null;
    _lastDetectedConfidence = null;
    _recentCandidates.clear();
    _lastInferenceRequestedAt = null;
    AppLogger.info('Start detection', name: 'bloc');
    emit(IdScannerDetecting(currentState.controller));

    try {
      currentState.controller.startImageStream(
        (cameraImage) {
          if (!_isDetecting) {
            return;
          }

          // Prevent event-queue backlog: if we're already processing, don't enqueue more.
          if (_isProcessingFrame) {
            _droppedFrameCount++;
            return;
          }

          _frameCounter++;
          final now = DateTime.now();
          const minInferenceInterval = Duration(milliseconds: 160);
          if (_lastInferenceRequestedAt != null &&
              now.difference(_lastInferenceRequestedAt!) < minInferenceInterval) {
            return;
          }
          _lastInferenceRequestedAt = now;

          add(ProcessFrame(cameraImage));
        },
      );
    } catch (e, st) {
      AppLogger.error('startImageStream failed: $e', name: 'bloc', error: e, stackTrace: st);

      emit(IdScannerError('startImageStream failed: $e'));
    }
  }

  Future<void> _onStopDetection(
    StopDetection event,
    Emitter<IdScannerState> emit,
  ) async {
    _isDetecting = false;
    _isProcessingFrame = false;

    final currentState = state;
    CameraController? controller;
    if (currentState is IdScannerDetecting) {
      controller = currentState.controller;
    } else if (currentState is IdScannerDetected) {
      controller = currentState.controller;
    }

    if (controller != null) {
      AppLogger.info(
        'Stop detection. droppedFrames=$_droppedFrameCount',
        name: 'bloc',
      );

      await controller.stopImageStream();
      emit(IdScannerReady(controller));
    }
  }

  Future<void> _onProcessFrame(
    ProcessFrame event,
    Emitter<IdScannerState> emit,
  ) async {
    if (!_isDetecting) {
      return;
    }

    if (_isProcessingFrame) {
      _droppedFrameCount++;
      if (AppLogger.shouldLogEvery('bloc.drop_frames', const Duration(seconds: 2))) {
        AppLogger.warn(
          'Dropping frames: $_droppedFrameCount (inference is slower than camera stream)',
          name: 'bloc',
        );
      }
      return;
    }

    _isProcessingFrame = true;
    try {
      if (AppLogger.shouldLogEvery('bloc.infer', const Duration(seconds: 2))) {
        AppLogger.info(
          'Running inference... frame=$_frameCounter dropped=$_droppedFrameCount',
          name: 'bloc',
        );
      }

      final result = await _repository.detectId(event.cameraImage);
      result.fold(
        (failure) {
          if (failure is! TFLiteFailure) {
            AppLogger.warn(
              'Detection failure: ${failure.message}',
              name: 'bloc',
              error: failure,
            );
            emit(IdScannerError(failure.message ?? 'Detection failed'));
          }
        },
        (detections) {
          final now = DateTime.now();
          if (detections.isNotEmpty) {
            final top = detections.first;
            final isConfirmed = _shouldConfirmDetection(top, now);
            if (!isConfirmed) {
              _handleNoConfirmedDetections(now, emit);
              return;
            }

            final currentState = state;
            CameraController? controller;
            if (currentState is IdScannerDetecting) {
              controller = currentState.controller;
            } else if (currentState is IdScannerDetected) {
              controller = currentState.controller;
            }
            if (controller != null) {
              const uiEmitCooldown = Duration(milliseconds: 350);
              final shouldEmitByTime = _lastUiEmitAt == null ||
                  now.difference(_lastUiEmitAt!) >= uiEmitCooldown;

              final topConfidence = top.confidence;
              final confidenceChangedEnough = _lastDetectedConfidence == null ||
                  (topConfidence - _lastDetectedConfidence!).abs() >= 0.02;

              if (shouldEmitByTime || confidenceChangedEnough) {
                _lastUiEmitAt = now;
                _lastDetectedAt = now;
                _lastDetectedSourceSize = Size(
                  event.cameraImage.width.toDouble(),
                  event.cameraImage.height.toDouble(),
                );
                _lastDetectedConfidence = topConfidence;

                emit(IdScannerDetected(
                  controller: controller,
                  detections: detections,
                  sourceImageSize: _lastDetectedSourceSize!,
                ));
              } else {
                _lastDetectedAt = now;
              }
            }
          } else {
            _handleNoConfirmedDetections(now, emit);
          }
        },
      );
    } catch (e) {
      // Silently handle detection errors to avoid spamming
      if (AppLogger.shouldLogEvery('bloc.detect_exception', const Duration(seconds: 2))) {
        AppLogger.warn('Detection exception: $e', name: 'bloc', error: e);
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  Future<void> close() async {
    final currentState = state;
    if (currentState is IdScannerDetecting) {
      await currentState.controller.stopImageStream();
    } else if (currentState is IdScannerDetected) {
      await currentState.controller.stopImageStream();
    }
    await _cameraDataSource.dispose();
    await _repository.disposeModel();
    return super.close();
  }

  bool _shouldConfirmDetection(
    DetectionResult detection,
    DateTime now,
  ) {
    const confirmationWindow = Duration(milliseconds: 1100);
    const requiredHits = 3;
    const minIou = 0.50;

    _recentCandidates.removeWhere(
      (candidate) => now.difference(candidate.timestamp) > confirmationWindow,
    );
    _recentCandidates.add(
      _RecentDetectionCandidate(
        timestamp: now,
        classLabel: detection.classLabel,
        boundingBox: detection.boundingBox,
      ),
    );

    final sameClass = _recentCandidates
        .where((c) => c.classLabel == detection.classLabel)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (sameClass.length < requiredHits) {
      return false;
    }

    final last = sameClass.sublist(sameClass.length - requiredHits);
    for (var i = 1; i < last.length; i++) {
      final iou = _intersectionOverUnion(
        last[i - 1].boundingBox,
        last[i].boundingBox,
      );
      if (iou < minIou) {
        return false;
      }
    }

    return true;
  }

  static double _intersectionOverUnion(BoundingBox a, BoundingBox b) {
    final left = a.x > b.x ? a.x : b.x;
    final top = a.y > b.y ? a.y : b.y;
    final rightA = a.x + a.width;
    final bottomA = a.y + a.height;
    final rightB = b.x + b.width;
    final bottomB = b.y + b.height;
    final right = rightA < rightB ? rightA : rightB;
    final bottom = bottomA < bottomB ? bottomA : bottomB;

    final intersectionWidth = right - left;
    final intersectionHeight = bottom - top;
    if (intersectionWidth <= 0 || intersectionHeight <= 0) {
      return 0.0;
    }

    final intersectionArea = intersectionWidth * intersectionHeight;
    final areaA = a.width * a.height;
    final areaB = b.width * b.height;
    final unionArea = areaA + areaB - intersectionArea;
    if (unionArea <= 0) {
      return 0.0;
    }

    return intersectionArea / unionArea;
  }

  void _handleNoConfirmedDetections(
    DateTime now,
    Emitter<IdScannerState> emit,
  ) {
    // If we haven't confirmed anything recently, fall back to Detecting to stop
    // repainting the overlay constantly.
    final currentState = state;
    CameraController? controller;
    if (currentState is IdScannerDetected) {
      controller = currentState.controller;
    } else if (currentState is IdScannerDetecting) {
      controller = currentState.controller;
    }

    final shouldClearOverlay = _lastDetectedAt != null &&
        now.difference(_lastDetectedAt!) >= const Duration(milliseconds: 800);

    if (controller != null && shouldClearOverlay && currentState is IdScannerDetected) {
      emit(IdScannerDetecting(controller));
    }
  }
}

class _RecentDetectionCandidate {
  _RecentDetectionCandidate({
    required this.timestamp,
    required this.classLabel,
    required this.boundingBox,
  });

  final DateTime timestamp;
  final String classLabel;
  final BoundingBox boundingBox;
}


