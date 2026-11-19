import 'package:flutter/foundation.dart';

import 'ocr_geometry.dart';

/// Semantic classification of a structured entity extracted from OCR text.
enum OcrEntityType {
  /// Electronic mail address (e.g. `hello@humanize.id`).
  email,

  /// Web URL or domain link (e.g. `https://humanize.id`).
  url,

  /// Phone or mobile number (e.g. `+62 812-3456-7890`).
  phone,

  /// Calendar date (ISO, US, or European format).
  date,

  /// Monetary currency amount (e.g. `$1,249.50`, `Rp 150.000`).
  amount,

  /// Percentage figure (e.g. `98.5%`).
  percentage,

  /// Document reference or invoice identifier (e.g. `INV-2026-0842`).
  invoiceNumber,

  /// Masked or unmasked payment/ID card sequence.
  cardNumber,

  /// Hashtag token (e.g. `#FlutterOCR`).
  hashtag,

  /// Structured `Key: Value` pair detected on a document line.
  keyValue,
}

/// A structured semantic entity automatically detected inside an [OcrResult].
@immutable
class OcrEntity {
  /// Creates an [OcrEntity].
  const OcrEntity({
    required this.type,
    required this.value,
    required this.rawText,
    required this.confidence,
    this.label,
    this.boundingBox,
    this.startIndex = 0,
    this.endIndex = 0,
  });

  /// Creates an [OcrEntity] from a JSON map.
  factory OcrEntity.fromJson(Map<String, Object?> json) {
    final typeName = json['type']! as String;
    final type = OcrEntityType.values.firstWhere(
      (OcrEntityType e) => e.name == typeName,
      orElse: () => OcrEntityType.keyValue,
    );
    final boxJson = json['boundingBox'];
    return OcrEntity(
      type: type,
      value: json['value']! as String,
      rawText: json['rawText']! as String,
      confidence: (json['confidence']! as num).toDouble(),
      label: json['label'] as String?,
      boundingBox: boxJson is Map<String, Object?>
          ? OcrRect.fromJson(boxJson)
          : null,
      startIndex: (json['startIndex'] as num?)?.toInt() ?? 0,
      endIndex: (json['endIndex'] as num?)?.toInt() ?? 0,
    );
  }

  /// Semantic category of this entity.
  final OcrEntityType type;

  /// Normalized value of the entity (trimmed of surrounding labels/delimiters).
  final String value;

  /// Original matched substring from the recognized document text.
  final String rawText;

  /// Optional key/field label when [type] is [OcrEntityType.keyValue].
  final String? label;

  /// Confidence score in `[0.0, 1.0]` inherited from overlapping OCR words.
  final double confidence;

  /// Approximate bounding box in image pixel coordinates, if matched to words.
  final OcrRect? boundingBox;

  /// Start character offset in the full recognized document text.
  final int startIndex;

  /// Exclusive end character offset in the full recognized document text.
  final int endIndex;

  /// Serializes this entity to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.name,
    'value': value,
    'rawText': rawText,
    if (label != null) 'label': label,
    'confidence': confidence,
    if (boundingBox != null) 'boundingBox': boundingBox!.toJson(),
    'startIndex': startIndex,
    'endIndex': endIndex,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrEntity &&
          other.type == type &&
          other.value == value &&
          other.rawText == rawText &&
          other.label == label &&
          other.startIndex == startIndex &&
          other.endIndex == endIndex;

  @override
  int get hashCode =>
      Object.hash(type, value, rawText, label, startIndex, endIndex);

  @override
  String toString() =>
      'OcrEntity(${type.name}: ${label != null ? '$label=' : ''}$value)';
}
