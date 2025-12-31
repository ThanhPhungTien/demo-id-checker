import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/image_utils.dart';
import '../../core/utils/tflite_utils.dart';
import '../models/detection_result_model.dart';
import '../../domain/entities/detection_result.dart';

class TFLiteDataSource {
  TFLiteDataSource();

  Interpreter? _interpreter;
  bool _isInitialized = false;
  int? _inputWidth;
  int? _inputHeight;
  TensorType? _inputType;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      AppLogger.info(
        'Loading TFLite model from asset: ${AppConstants.tfliteModelPath}',
        name: 'tflite',
      );
      _interpreter = await TFLiteUtils.loadModel(
        AppConstants.tfliteModelPath,
      );
      _isInitialized = true;

      final inputTensor = _interpreter!.getInputTensor(0);
      final inputShape = inputTensor.shape;
      _inputType = inputTensor.type;
      if (inputShape.length >= 4) {
        _inputHeight = inputShape[1];
        _inputWidth = inputShape[2];
      }

      AppLogger.info(
        'TFLite model loaded. inputShape=$inputShape inputType=$_inputType',
        name: 'tflite',
      );

      for (var outputIndex = 0;
          outputIndex < _interpreter!.getOutputTensors().length;
          outputIndex++) {
        final tensor = _interpreter!.getOutputTensor(outputIndex);
        AppLogger.info(
          'Output[$outputIndex] shape=${tensor.shape} type=${tensor.type}',
          name: 'tflite',
        );
      }
    } catch (e) {
      throw Exception('Failed to initialize TFLite model: $e');
    }
  }

  Future<List<DetectionResultModel>> detect(
    CameraImage cameraImage,
    int imageWidth,
    int imageHeight,
  ) async {
    if (!_isInitialized || _interpreter == null) {
      throw Exception('TFLite model not initialized');
    }

    try {
      final stopwatch = Stopwatch()..start();
      final image = await ImageUtils.convertCameraImageToImage(cameraImage);
      if (image == null) {
        if (AppLogger.shouldLogEvery('tflite.convert_failed', const Duration(seconds: 2))) {
          AppLogger.warn('CameraImage -> img.Image conversion failed.', name: 'tflite');
        }
        return [];
      }

      final inputWidth = _inputWidth ?? AppConstants.modelInputWidth;
      final inputHeight = _inputHeight ?? AppConstants.modelInputHeight;

      final letterbox = ImageUtils.letterboxImage(
        image,
        targetWidth: inputWidth,
        targetHeight: inputHeight,
      );

      final outputTensor = _interpreter!.getOutputTensor(0);
      final outputShape = outputTensor.shape;
      final outputElementCount = outputShape.fold<int>(1, (a, b) => a * b);
      final outputByteSize = outputTensor.numBytes();
      final outputByteBuffer = Uint8List(outputByteSize).buffer;

      final inputType = _inputType ?? _interpreter!.getInputTensor(0).type;

      if (inputType == TensorType.uint8) {
        final inputBytes = ImageUtils.imageToUint8ListRgb(
          letterbox.image,
          inputWidth,
          inputHeight,
        );
        // Use ByteBuffer input/output to prevent accidental tensor resize due to shape inference.
        _interpreter!.runForMultipleInputs(
          [inputBytes.buffer],
          {0: outputByteBuffer},
        );
      } else {
        final inputBuffer = ImageUtils.imageToByteListFloat32(
          letterbox.image,
          inputWidth,
          // Switch to [0..1] normalization; current runtime evidence shows input is
          // almost always -1.0 which indicates we're effectively feeding a near-black tensor.
          0.0,
          1.0,
        );

        // Pass ByteBuffer to avoid interpreter resizing input tensor to [N] (1D) which breaks the graph.
        _interpreter!.runForMultipleInputs(
          [inputBuffer.buffer],
          {0: outputByteBuffer},
        );
      }

      final outputBuffer = Float32List.view(
        outputByteBuffer,
        0,
        outputElementCount,
      );

      final results = _parseOutput(
        outputBuffer,
        outputShape,
        imageWidth,
        imageHeight,
        inputWidth,
        inputHeight,
        letterbox.scale,
        letterbox.padLeft,
        letterbox.padTop,
      );

      stopwatch.stop();
      if (results.isNotEmpty) {
        final top = results.first;
        AppLogger.info(
          'DETECTED ${results.length} objects in ${stopwatch.elapsedMilliseconds}ms. '
          'Top: ${top.classLabel} conf=${top.confidence.toStringAsFixed(3)} '
          'box=[${top.boundingBox.x.toStringAsFixed(1)},${top.boundingBox.y.toStringAsFixed(1)},'
          '${top.boundingBox.width.toStringAsFixed(1)},${top.boundingBox.height.toStringAsFixed(1)}]',
          name: 'tflite',
        );
      } else if (AppLogger.shouldLogEvery('tflite.no_detection', const Duration(seconds: 2))) {
        AppLogger.info(
          'No detection. inference=${stopwatch.elapsedMilliseconds}ms',
          name: 'tflite',
        );
      }

      return results;
    } catch (e) {
      throw Exception('Detection failed: $e');
    }
  }

  List<DetectionResultModel> _parseOutput(
    Float32List output,
    List<int> outputShape,
    int imageWidth,
    int imageHeight,
    int inputWidth,
    int inputHeight,
    double letterboxScale,
    int letterboxPadLeft,
    int letterboxPadTop,
  ) {
    final results = <DetectionResultModel>[];
    if (outputShape.isEmpty) {
      return results;
    }

    // YOLO-style: [1, 7, N] where 7 = [cx, cy, w, h, obj, cls0, cls1]
    if (outputShape.length == 3 &&
        outputShape[0] == 1 &&
        outputShape[1] == 7 &&
        outputShape[2] > 0) {
      final anchors = outputShape[2];
      final imageWidthDouble = imageWidth.toDouble();
      final imageHeightDouble = imageHeight.toDouble();
      final inputWidthDouble = inputWidth.toDouble();
      final inputHeightDouble = inputHeight.toDouble();
      final padLeftDouble = letterboxPadLeft.toDouble();
      final padTopDouble = letterboxPadTop.toDouble();

      for (var i = 0; i < anchors; i++) {
        final cx = output[(0 * anchors) + i];
        final cy = output[(1 * anchors) + i];
        final w = output[(2 * anchors) + i];
        final h = output[(3 * anchors) + i];
        final obj = output[(4 * anchors) + i];
        final cls0 = output[(5 * anchors) + i];
        final cls1 = output[(6 * anchors) + i];

        // Many YOLO exports output logits for obj/cls. Apply sigmoid.
        final objProb = _sigmoid(obj.toDouble());
        final cls0Prob = _sigmoid(cls0.toDouble());
        final cls1Prob = _sigmoid(cls1.toDouble());

        final classIndex = cls1Prob > cls0Prob ? 1 : 0;
        final classProb = classIndex == 0 ? cls0Prob : cls1Prob;

        // For false-positive reduction, use the stricter YOLO-style confidence.
        final confidence = objProb * classProb;

        if (confidence < AppConstants.detectionConfidenceThreshold) {
          continue;
        }

        // Most YOLO exports provide normalized cx/cy/w/h in [0..1] w.r.t. the model input.
        // Some exports provide pixel coordinates directly; handle both.
        final isNormalized =
            cx.abs() <= 1.5 && cy.abs() <= 1.5 && w.abs() <= 1.5 && h.abs() <= 1.5;

        final cxInput = isNormalized ? cx.toDouble() * inputWidthDouble : cx.toDouble();
        final cyInput = isNormalized ? cy.toDouble() * inputHeightDouble : cy.toDouble();
        final wInput = isNormalized ? w.toDouble() * inputWidthDouble : w.toDouble();
        final hInput = isNormalized ? h.toDouble() * inputHeightDouble : h.toDouble();

        // Convert from (cx,cy,w,h) on letterboxed input -> (left,top,width,height) in original image space.
        // Un-letterbox: subtract pad, then divide by scale.
        var left = (cxInput - (wInput / 2.0) - padLeftDouble) / letterboxScale;
        var top = (cyInput - (hInput / 2.0) - padTopDouble) / letterboxScale;
        var width = wInput / letterboxScale;
        var height = hInput / letterboxScale;

        // Clamp to image bounds.
        if (left.isNaN || top.isNaN || width.isNaN || height.isNaN) {
          continue;
        }
        if (width <= 0 || height <= 0) {
          continue;
        }
        left = left.clamp(0.0, imageWidthDouble);
        top = top.clamp(0.0, imageHeightDouble);
        width = width.clamp(0.0, imageWidthDouble - left);
        height = height.clamp(0.0, imageHeightDouble - top);

        results.add(
          DetectionResultModel(
            boundingBox: BoundingBox(
              x: left,
              y: top,
              width: width,
              height: height,
            ),
            confidence: confidence.toDouble(),
            classLabel: classIndex == 0 ? 'CCCD' : 'Passport',
          ),
        );
      }

      results.sort((a, b) => b.confidence.compareTo(a.confidence));
      final filtered = _nonMaximumSuppression(
        results,
        iouThreshold: AppConstants.nmsIouThreshold,
        maxResults: AppConstants.maxDetectionsAfterNms,
      );
      return filtered;
    }

    int numDetections;
    int numValuesPerDetection;
    if (outputShape.length == 3 && outputShape[0] == 1) {
      numDetections = outputShape[1];
      numValuesPerDetection = outputShape[2];
    } else if (outputShape.length == 2) {
      numDetections = outputShape[0];
      numValuesPerDetection = outputShape[1];
    } else {
      // Unknown format; log once and return empty to avoid false parsing.
      if (AppLogger.shouldLogEvery('tflite.unknown_output_shape', const Duration(seconds: 5))) {
        AppLogger.warn('Unknown outputShape=$outputShape, cannot parse.', name: 'tflite');
      }
      return results;
    }

    for (var i = 0; i < numDetections; i++) {
      final offset = i * numValuesPerDetection;
      if (offset + 5 >= output.length) {
        break;
      }
      final confidence = output[offset + 4];

      if (confidence < AppConstants.detectionConfidenceThreshold) {
        continue;
      }

      final detectionData = <double>[];
      for (var j = 0; j < numValuesPerDetection; j++) {
        detectionData.add(output[offset + j]);
      }

      try {
        final result = DetectionResultModel.fromTFLiteOutput(
          detectionData,
          imageWidth,
          imageHeight,
          AppConstants.modelInputWidth,
          AppConstants.modelInputHeight,
        );

        if (result.confidence >= AppConstants.detectionConfidenceThreshold) {
          results.add(result);
        }
      } catch (e) {
        continue;
      }
    }

    results.sort((a, b) => b.confidence.compareTo(a.confidence));

    return results.take(AppConstants.maxDetectionResults).toList();
  }

  static List<DetectionResultModel> _nonMaximumSuppression(
    List<DetectionResultModel> sortedDetections, {
    required double iouThreshold,
    required int maxResults,
  }) {
    final selected = <DetectionResultModel>[];

    for (final candidate in sortedDetections) {
      if (selected.length >= maxResults) {
        break;
      }

      var shouldSelect = true;
      for (final kept in selected) {
        final iou = _intersectionOverUnion(candidate.boundingBox, kept.boundingBox);
        if (iou >= iouThreshold) {
          shouldSelect = false;
          break;
        }
      }

      if (shouldSelect) {
        selected.add(candidate);
      }
    }

    return selected;
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

  static double _sigmoid(double value) {
    // Numerically stable sigmoid.
    if (value >= 0) {
      final z = exp(-value);
      return 1 / (1 + z);
    } else {
      final z = exp(value);
      return z / (1 + z);
    }
  }

  void dispose() {
    if (_interpreter != null) {
      TFLiteUtils.closeModel(_interpreter!);
      _interpreter = null;
      _isInitialized = false;
    }
  }
}

