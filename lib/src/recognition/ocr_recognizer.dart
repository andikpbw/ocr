import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../models/ocr_config.dart';
import '../models/ocr_image.dart';
import '../models/ocr_result.dart';
import 'ocr_engine.dart';

/// High-level, ergonomic facade for offline Optical Character Recognition.
///
/// Works out of the box with zero external dependencies across Android, iOS,
/// Web (JS & Wasm), macOS, Windows, and Linux.
///
/// ```dart
/// final recognizer = OcrRecognizer();
/// final result = await recognizer.recognizeBytes(pngBytes);
/// print(result.text);
/// recognizer.dispose();
/// ```
class OcrRecognizer {
  /// Creates an [OcrRecognizer] using [config] and an optional custom [engine].
  OcrRecognizer({this.config = const OcrConfig(), OcrEngine? engine})
    : _engine = engine ?? BuiltInOcrEngine();

  /// Default configuration applied when individual calls omit `config`.
  final OcrConfig config;

  final OcrEngine _engine;

  /// Active underlying [OcrEngine] backing this recognizer.
  OcrEngine get engine => _engine;

  /// One-line helper to recognize text directly from encoded PNG/JPEG/WebP/BMP
  /// [bytes] without manually instantiating or disposing a recognizer.
  static Future<OcrResult> quickRead(
    Uint8List bytes, {
    OcrConfig config = const OcrConfig(),
  }) async {
    final recognizer = OcrRecognizer(config: config);
    try {
      return await recognizer.recognizeBytes(bytes);
    } finally {
      recognizer.dispose();
    }
  }

  /// One-line helper to recognize text directly from an [OcrImage].
  static Future<OcrResult> quickReadImage(
    OcrImage image, {
    OcrConfig config = const OcrConfig(),
  }) async {
    final recognizer = OcrRecognizer(config: config);
    try {
      return await recognizer.recognizeImage(image);
    } finally {
      recognizer.dispose();
    }
  }

  /// Runs OCR on an [OcrImage].
  Future<OcrResult> recognizeImage(OcrImage image, {OcrConfig? config}) {
    return _engine.recognize(image, config: config ?? this.config);
  }

  /// Runs synchronous OCR on an [OcrImage] when backed by [BuiltInOcrEngine].
  OcrResult recognizeImageSync(OcrImage image, {OcrConfig? config}) {
    final eng = _engine;
    if (eng is BuiltInOcrEngine) {
      return eng.recognizeSync(image, config: config ?? this.config);
    }
    throw UnsupportedError(
      'Synchronous recognition is only supported by BuiltInOcrEngine '
      '(active engine: ${eng.name}).',
    );
  }

  /// Decodes encoded image bytes (PNG, JPEG, WebP, GIF, or BMP) and runs OCR.
  Future<OcrResult> recognizeBytes(Uint8List bytes, {OcrConfig? config}) async {
    final image = await OcrImage.fromBytes(bytes);
    return recognizeImage(image, config: config);
  }

  /// Converts a Flutter [ui.Image] and runs OCR.
  Future<OcrResult> recognizeUiImage(
    ui.Image image, {
    OcrConfig? config,
  }) async {
    final ocrImage = await OcrImage.fromUiImage(image);
    return recognizeImage(ocrImage, config: config);
  }

  /// Runs OCR directly on a raw RGBA8888 pixel buffer.
  Future<OcrResult> recognizeRgba(
    Uint8List rgba, {
    required int width,
    required int height,
    OcrConfig? config,
  }) {
    final image = OcrImage.fromRgba(rgba, width: width, height: height);
    return recognizeImage(image, config: config);
  }

  /// Runs OCR directly on a raw BGRA8888 pixel buffer (iOS/macOS cameras).
  Future<OcrResult> recognizeBgra(
    Uint8List bgra, {
    required int width,
    required int height,
    OcrConfig? config,
  }) {
    final image = OcrImage.fromBgra(bgra, width: width, height: height);
    return recognizeImage(image, config: config);
  }

  /// Runs OCR directly on the Y luminance plane of a YUV420 camera frame.
  Future<OcrResult> recognizeYuv420({
    required Uint8List yPlane,
    required int width,
    required int height,
    int? bytesPerRow,
    OcrConfig? config,
  }) {
    final image = OcrImage.fromYuv420(
      yPlane: yPlane,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
    );
    return recognizeImage(image, config: config);
  }

  /// Captures a Flutter [RepaintBoundary] identified by [boundaryKey] and runs
  /// OCR on the rendered widget snapshot.
  Future<OcrResult> recognizeWidget(
    GlobalKey boundaryKey, {
    double pixelRatio = 2.0,
    OcrConfig? config,
  }) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError(
        'boundaryKey must be attached to a mounted RepaintBoundary widget.',
      );
    }
    final uiImage = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      return await recognizeUiImage(uiImage, config: config);
    } finally {
      uiImage.dispose();
    }
  }

  /// Recognizes a batch of [images] sequentially and returns results in order.
  Future<List<OcrResult>> recognizeBatch(
    List<OcrImage> images, {
    OcrConfig? config,
  }) async {
    final results = <OcrResult>[];
    for (final img in images) {
      results.add(await recognizeImage(img, config: config));
    }
    return results;
  }

  /// Transforms a stream of [frames] (e.g., live camera feed) into a stream of
  /// [OcrResult] snapshots.
  Stream<OcrResult> recognizeStream(
    Stream<OcrImage> frames, {
    OcrConfig? config,
  }) async* {
    await for (final frame in frames) {
      yield await recognizeImage(frame, config: config);
    }
  }

  /// Releases resources held by the underlying [OcrEngine].
  void dispose() => _engine.dispose();
}
