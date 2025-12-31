import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class LetterboxResult {
  LetterboxResult({
    required this.image,
    required this.scale,
    required this.padLeft,
    required this.padTop,
  });

  final img.Image image;
  final double scale;
  final int padLeft;
  final int padTop;
}

class ImageUtils {
  ImageUtils._();

  static Future<img.Image?> convertCameraImageToImage(
    CameraImage cameraImage,
  ) async {
    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToImage(cameraImage);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static img.Image _convertYUV420ToImage(CameraImage cameraImage) {
    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];

    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;

    final ySize = (yPlane.width ?? 0) * (yPlane.height ?? 0);
    final uvSize = (uPlane.width ?? 0) * (uPlane.height ?? 0);

    final yBytes = Uint8List(ySize);
    final uBytes = Uint8List(uvSize);
    final vBytes = Uint8List(uvSize);

    yBytes.setRange(0, ySize, yBuffer);
    uBytes.setRange(0, uvSize, uBuffer);
    vBytes.setRange(0, uvSize, vBuffer);

    final image = img.Image(
      width: cameraImage.width,
      height: cameraImage.height,
    );

    for (var y = 0; y < cameraImage.height; y++) {
      for (var x = 0; x < cameraImage.width; x++) {
        final yIndex = y * cameraImage.width + x;
        final uvIndex = (y ~/ 2) * (uPlane.width ?? 0) + (x ~/ 2);

        final yValue = yBytes[yIndex];
        final uValue = uBytes[uvIndex];
        final vValue = vBytes[uvIndex];

        final r = _yuv2r(yValue, uValue, vValue);
        final g = _yuv2g(yValue, uValue, vValue);
        final b = _yuv2b(yValue, uValue, vValue);

        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return image;
  }

  static img.Image _convertBGRA8888ToImage(CameraImage cameraImage) {
    final plane = cameraImage.planes[0];
    final bytes = plane.bytes;

    final image = img.Image(
      width: cameraImage.width,
      height: cameraImage.height,
    );

    for (var y = 0; y < cameraImage.height; y++) {
      for (var x = 0; x < cameraImage.width; x++) {
        final offset = (y * plane.bytesPerRow) + (x * 4);
        final b = bytes[offset];
        final g = bytes[offset + 1];
        final r = bytes[offset + 2];
        final a = bytes[offset + 3];

        image.setPixelRgba(x, y, r, g, b, a);
      }
    }

    return image;
  }

  static int _yuv2r(int y, int u, int v) {
    var r = (y + (1.402 * (v - 128))).round();
    r = r.clamp(0, 255);
    return r;
  }

  static int _yuv2g(int y, int u, int v) {
    var g = (y - (0.344 * (u - 128)) - (0.714 * (v - 128))).round();
    g = g.clamp(0, 255);
    return g;
  }

  static int _yuv2b(int y, int u, int v) {
    var b = (y + (1.772 * (u - 128))).round();
    b = b.clamp(0, 255);
    return b;
  }

  static img.Image resizeImage(
    img.Image image,
    int targetWidth,
    int targetHeight,
  ) {
    return img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Letterbox resize (keep aspect ratio + padding) to match common YOLO training pipelines.
  ///
  /// Returns the padded image and the parameters needed to map detections back to the
  /// original image space (un-letterbox).
  static LetterboxResult letterboxImage(
    img.Image source, {
    required int targetWidth,
    required int targetHeight,
    int padColor = 114,
  }) {
    final sourceWidth = source.width;
    final sourceHeight = source.height;

    final scaleWidth = targetWidth / sourceWidth;
    final scaleHeight = targetHeight / sourceHeight;
    final scale = scaleWidth < scaleHeight ? scaleWidth : scaleHeight;

    final resizedWidth = (sourceWidth * scale).round();
    final resizedHeight = (sourceHeight * scale).round();

    final resized = img.copyResize(
      source,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.linear,
    );

    final padded = img.Image(
      width: targetWidth,
      height: targetHeight,
    );
    img.fill(
      padded,
      color: img.ColorRgb8(padColor, padColor, padColor),
    );

    final padLeft = ((targetWidth - resizedWidth) / 2).round();
    final padTop = ((targetHeight - resizedHeight) / 2).round();

    img.compositeImage(
      padded,
      resized,
      dstX: padLeft,
      dstY: padTop,
    );

    return LetterboxResult(
      image: padded,
      scale: scale,
      padLeft: padLeft,
      padTop: padTop,
    );
  }

  static Float32List imageToByteListFloat32(
    img.Image image,
    int inputSize,
    double mean,
    double std,
  ) {
    final convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    final buffer = Float32List.view(convertedBytes.buffer);

    int pixelIndex = 0;
    for (var i = 0; i < inputSize; i++) {
      for (var j = 0; j < inputSize; j++) {
        final pixel = image.getPixel(j, i);
        buffer[pixelIndex++] = (pixel.r.toDouble() / 255.0 - mean) / std;
        buffer[pixelIndex++] = (pixel.g.toDouble() / 255.0 - mean) / std;
        buffer[pixelIndex++] = (pixel.b.toDouble() / 255.0 - mean) / std;
      }
    }
    return buffer;
  }

  static Uint8List imageToUint8ListRgb(
    img.Image image,
    int inputWidth,
    int inputHeight,
  ) {
    final bytes = Uint8List(inputWidth * inputHeight * 3);
    var byteIndex = 0;

    for (var y = 0; y < inputHeight; y++) {
      for (var x = 0; x < inputWidth; x++) {
        final pixel = image.getPixel(x, y);
        bytes[byteIndex++] = pixel.r.toInt();
        bytes[byteIndex++] = pixel.g.toInt();
        bytes[byteIndex++] = pixel.b.toInt();
      }
    }

    return bytes;
  }
}

