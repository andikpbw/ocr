/// Modern, lightweight, zero-dependency Flutter OCR library for offline text
/// recognition, computer-vision preprocessing, structured entity extraction,
/// and interactive UI overlays.
///
/// Works seamlessly across Android, iOS, Web (JS & Wasm), macOS, Windows, and
/// Linux using only `package:flutter/widgets.dart` (no deprecated Material or
/// Cupertino framework imports).
///
/// ## Quick Start
/// ```dart
/// import 'package:flutter_ocr/flutter_ocr.dart';
///
/// final recognizer = OcrRecognizer();
/// final result = await recognizer.recognizeBytes(imageBytes);
/// print(result.text);
/// print(result.entities);
/// recognizer.dispose();
/// ```
library;

export 'src/models/ocr_config.dart';
export 'src/models/ocr_entity.dart';
export 'src/models/ocr_geometry.dart';
export 'src/models/ocr_image.dart';
export 'src/models/ocr_result.dart';
export 'src/preprocessing/ocr_deskew.dart';
export 'src/preprocessing/ocr_preprocessor.dart';
export 'src/recognition/ocr_classifier.dart';
export 'src/recognition/ocr_engine.dart';
export 'src/recognition/ocr_font_calibrator.dart';
export 'src/recognition/ocr_glyph_features.dart';
export 'src/recognition/ocr_post_processor.dart';
export 'src/recognition/ocr_recognizer.dart';
export 'src/recognition/ocr_vector_atlas.dart';
export 'src/segmentation/ocr_ccl.dart';
export 'src/segmentation/ocr_glyph_splitter.dart';
export 'src/segmentation/ocr_layout.dart';
export 'src/widgets/ocr_entity_chips.dart';
export 'src/widgets/ocr_icons.dart';
export 'src/widgets/ocr_inspector.dart';
export 'src/widgets/ocr_result_viewer.dart';
export 'src/widgets/ocr_scanner_overlay.dart';
export 'src/widgets/ocr_theme.dart';
