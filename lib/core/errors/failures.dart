import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  const Failure([this.message]);

  final String? message;

  @override
  List<Object?> get props => [message];
}

class CameraFailure extends Failure {
  const CameraFailure([super.message]);
}

class TFLiteFailure extends Failure {
  const TFLiteFailure([super.message]);
}

class ModelLoadFailure extends Failure {
  const ModelLoadFailure([super.message]);
}

class PermissionFailure extends Failure {
  const PermissionFailure([super.message]);
}

