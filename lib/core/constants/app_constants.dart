class AppConstants {
  AppConstants._();

  static const String tfliteModelPath = 'assets/models/idChecker.tflite';
  // Using YOLO-style confidence (objProb * classProb). Raise this to reduce false positives.
  static const double detectionConfidenceThreshold = 0.30;
  // User notification should be stricter than overlay.
  static const double notifyConfidenceThreshold = 0.55;
  // Fallback only (the runtime reads actual input shape from the model).
  static const int modelInputWidth = 640;
  static const int modelInputHeight = 640;
  static const int maxDetectionResults = 10;
  static const int maxDetectionsAfterNms = 1;
  static const double nmsIouThreshold = 0.45;

  // Performance: run inference once per N frames.
  static const int inferenceFrameStride = 8;
}

