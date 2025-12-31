import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static void info(
    String message, {
    String name = 'demo_id_checker',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!kDebugMode) {
      return;
    }
    developer.log(message, name: name, error: error, stackTrace: stackTrace);
  }

  static void warn(
    String message, {
    String name = 'demo_id_checker',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!kDebugMode) {
      return;
    }
    developer.log(
      message,
      name: name,
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error(
    String message, {
    String name = 'demo_id_checker',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!kDebugMode) {
      return;
    }
    developer.log(
      message,
      name: name,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static final Map<String, DateTime> _keyToLastLogAt = {};

  static bool shouldLogEvery(String key, Duration interval) {
    final now = DateTime.now();
    final lastLogAt = _keyToLastLogAt[key];

    if (lastLogAt == null) {
      _keyToLastLogAt[key] = now;
      return true;
    }

    if (now.difference(lastLogAt) >= interval) {
      _keyToLastLogAt[key] = now;
      return true;
    }

    return false;
  }
}


