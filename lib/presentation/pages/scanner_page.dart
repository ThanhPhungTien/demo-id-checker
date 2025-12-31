import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants/app_constants.dart';
import '../bloc/id_scanner_bloc.dart';
import '../bloc/id_scanner_event.dart';
import '../bloc/id_scanner_state.dart';
import '../widgets/camera_preview_widget.dart';
import '../widgets/detection_overlay_widget.dart';

class ScannerPage extends StatelessWidget {
  const ScannerPage({
    super.key,
    this.autoInitialize = true,
    this.blocFactory,
  });

  /// In widget tests, set this to false to avoid invoking platform plugins
  /// (camera/TFLite) from the widget tree.
  final bool autoInitialize;

  /// Optional injection hook for tests.
  final IdScannerBloc Function()? blocFactory;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final bloc = (blocFactory ?? () => IdScannerBloc())();
        if (autoInitialize) {
          bloc
            ..add(const InitializeModel())
            ..add(const InitializeCamera());
        }
        return bloc;
      },
      child: const _ScannerView(),
    );
  }
}

class _ScannerView extends StatefulWidget {
  const _ScannerView();

  @override
  State<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<_ScannerView> {
  DateTime? _lastNotifyAt;
  bool _wasDetected = false;

  bool _shouldShowDetectionSnackBar({
    required DateTime now,
    required double topConfidence,
  }) {
    const cooldown = Duration(seconds: 2);
    final isRisingEdge = !_wasDetected;
    final isCooledDown =
        _lastNotifyAt == null || now.difference(_lastNotifyAt!) >= cooldown;
    return isRisingEdge &&
        isCooledDown &&
        topConfidence >= AppConstants.notifyConfidenceThreshold;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CCCD Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: BlocConsumer<IdScannerBloc, IdScannerState>(
        listener: (context, state) {
          if (state is IdScannerError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
            _wasDetected = false;
          } else if (state is IdScannerDetected) {
            final now = DateTime.now();
            final topConfidence = state.detections.isEmpty
                ? 0.0
                : state.detections.first.confidence;
            if (_shouldShowDetectionSnackBar(
                now: now, topConfidence: topConfidence)) {
              _lastNotifyAt = now;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Phát hiện ${state.detections.first.classLabel} '
                    '(${(topConfidence * 100).toStringAsFixed(1)}%)',
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            _wasDetected = true;
          } else if (state is IdScannerDetecting || state is IdScannerReady) {
            _wasDetected = false;
          }
        },
        builder: (context, state) {
          if (state is IdScannerInitial || state is IdScannerLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (state is IdScannerError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      context.read<IdScannerBloc>().add(
                            const InitializeCamera(),
                          );
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }

          if (state is IdScannerReady) {
            return _buildCameraView(
              context,
              state.controller,
              const [],
              null,
            );
          }

          if (state is IdScannerDetecting) {
            return _buildCameraView(
              context,
              state.controller,
              const [],
              null,
            );
          }

          if (state is IdScannerDetected) {
            return _buildCameraView(
              context,
              state.controller,
              state.detections,
              state.sourceImageSize,
            );
          }

          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
      floatingActionButton: BlocBuilder<IdScannerBloc, IdScannerState>(
        builder: (context, state) {
          if (state is IdScannerReady) {
            return FloatingActionButton(
              onPressed: () {
                context.read<IdScannerBloc>().add(const StartDetection());
              },
              child: const Icon(Icons.play_arrow),
            );
          }

          if (state is IdScannerDetecting || state is IdScannerDetected) {
            return FloatingActionButton(
              onPressed: () {
                context.read<IdScannerBloc>().add(const StopDetection());
              },
              child: const Icon(Icons.stop),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildCameraView(
    BuildContext context,
    CameraController controller,
    List<dynamic> detections,
    Size? sourceImageSize,
  ) {
    return CameraPreviewWidget(
      controller: controller,
      fit: CameraPreviewFit.contain,
      overlay: detections.isEmpty
          ? null
          : DetectionOverlayWidget(
              detections: detections.cast(),
              imageSize: sourceImageSize ?? Size.zero,
            ),
    );
  }
}
