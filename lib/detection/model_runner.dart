import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';

/// Runs the model on one input tensor. Separate from the rest of the detector
/// so its logic can be tested without a model file or native libraries.
abstract class ModelRunner {
  /// `[1, channels, anchors]` output shape.
  int get channels;
  int get anchors;

  /// Which accelerator is in use, for logging and the paper.
  String get accelerator;

  /// Returns the flattened output for the flattened NCHW [input]. The result is
  /// only valid until the next call.
  Float32List run(Float32List input);

  void close();
}

/// Creates a runner for [modelBytes], with [threads] CPU threads. Must be a
/// top-level function or static method: it is sent to the worker isolate.
typedef ModelRunnerFactory =
    ModelRunner Function(Uint8List modelBytes, int inputSize, int threads);

/// [ModelRunner] backed by `flutter_litert`. Tries the GPU delegate first and
/// falls back to CPU/XNNPACK, then plain CPU.
ModelRunner createLiteRtRunner(
  Uint8List modelBytes,
  int inputSize,
  int threads,
) {
  final List<_DelegateChoice> choices = <_DelegateChoice>[
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      _DelegateChoice(
        'gpu (OpenGL/OpenCL)',
        () => GpuDelegateV2(
          options: GpuDelegateOptionsV2(isPrecisionLossAllowed: true),
        ),
      ),
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
      const _DelegateChoice('gpu (Metal)', GpuDelegate.new),
    _DelegateChoice(
      'cpu (XNNPACK)',
      () =>
          XNNPackDelegate(options: XNNPackDelegateOptions(numThreads: threads)),
    ),
    _DelegateChoice('cpu', () => null),
  ];

  Object? lastError;
  for (final _DelegateChoice choice in choices) {
    Delegate? delegate;
    Interpreter? interpreter;
    try {
      delegate = choice.create();
      final InterpreterOptions options = InterpreterOptions()
        ..threads = threads;
      if (delegate != null) options.addDelegate(delegate);
      interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      interpreter.allocateTensors();
      return _LiteRtRunner(interpreter, delegate, choice.name, inputSize);
    } on ModelFormatException {
      interpreter?.close();
      delegate?.delete();
      rethrow; // A wrong model fails on every accelerator.
    } catch (error, stackTrace) {
      lastError = error;
      developer.log(
        '${choice.name} unavailable, trying the next option',
        name: 'detection',
        error: error,
        stackTrace: stackTrace,
      );
      interpreter?.close();
      delegate?.delete();
    }
  }
  throw StateError('no accelerator could run the model: $lastError');
}

/// The model file does not match what the app expects.
class ModelFormatException implements Exception {
  const ModelFormatException(this.message);

  final String message;

  @override
  String toString() => 'ModelFormatException: $message';
}

class _DelegateChoice {
  const _DelegateChoice(this.name, this.create);

  final String name;
  final Delegate? Function() create;
}

class _LiteRtRunner implements ModelRunner {
  factory _LiteRtRunner(
    Interpreter interpreter,
    Delegate? delegate,
    String accelerator,
    int inputSize,
  ) {
    final List<int> input = interpreter.getInputTensor(0).shape;
    final List<int> output = interpreter.getOutputTensor(0).shape;
    if (!listEquals(input, <int>[1, 3, inputSize, inputSize])) {
      throw ModelFormatException(
        'input shape $input, expected [1, 3, $inputSize, $inputSize]',
      );
    }
    if (output.length != 3 || output[0] != 1 || output[1] <= 4) {
      throw ModelFormatException(
        'output shape $output, expected [1, channels, anchors]',
      );
    }
    return _LiteRtRunner._(
      interpreter,
      delegate,
      accelerator,
      output[1],
      output[2],
    );
  }

  _LiteRtRunner._(
    this._interpreter,
    this._delegate,
    this.accelerator,
    this.channels,
    this.anchors,
  );

  final Interpreter _interpreter;
  final Delegate? _delegate;

  @override
  final String accelerator;

  @override
  final int channels;

  @override
  final int anchors;

  @override
  Float32List run(Float32List input) {
    _interpreter.getInputTensor(0).data = input.buffer.asUint8List(
      input.offsetInBytes,
      input.lengthInBytes,
    );
    _interpreter.invoke();
    return Uint8List.fromList(
      _interpreter.getOutputTensor(0).data,
    ).buffer.asFloat32List();
  }

  @override
  void close() {
    _interpreter.close();
    _delegate?.delete();
  }
}
