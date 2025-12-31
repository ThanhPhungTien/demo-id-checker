import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteUtils {
  TFLiteUtils._();

  static Future<Interpreter> loadModel(String modelPath) async {
    try {
      final options = InterpreterOptions();
      return Interpreter.fromAsset(
        modelPath,
        options: options,
      );
    } catch (e) {
      throw Exception('Failed to load model: $e');
    }
  }

  static void closeModel(Interpreter interpreter) {
    interpreter.close();
  }
}

