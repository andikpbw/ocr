import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ocr_entity.dart';
import 'ocr_geometry.dart';

/// A ranked candidate character hypothesis produced by the glyph classifier.
@immutable
class OcrCandidate {
  /// Creates an [OcrCandidate] for [character] with calibrated [confidence].
  const OcrCandidate({required this.character, required this.confidence});

  /// Creates an [OcrCandidate] from a JSON map.
  factory OcrCandidate.fromJson(Map<String, Object?> json) => OcrCandidate(
    character: json['character']! as String,
    confidence: (json['confidence']! as num).toDouble(),
  );

  /// The recognized character string (single grapheme).
  final String character;

  /// Confidence score in `[0.0, 1.0]`.
  final double confidence;

  /// Serializes this candidate to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'character': character,
    'confidence': confidence,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrCandidate &&
          other.character == character &&
          other.confidence == confidence;

  @override
  int get hashCode => Object.hash(character, confidence);

  @override
  String toString() =>
      'OcrCandidate($character: ${(confidence * 100).toStringAsFixed(1)}%)';
}

/// A single recognized character glyph with its bounding box and alternatives.
@immutable
class OcrCharacter {
  /// Creates an [OcrCharacter].
  OcrCharacter({
    required this.text,
    required this.boundingBox,
    required this.confidence,
    List<OcrCandidate> alternatives = const <OcrCandidate>[],
  }) : alternatives = List<OcrCandidate>.unmodifiable(alternatives);

  /// Creates an [OcrCharacter] from a JSON map.
  factory OcrCharacter.fromJson(Map<String, Object?> json) {
    final alts = (json['alternatives'] as List<Object?>? ?? const <Object?>[])
        .map((Object? e) => OcrCandidate.fromJson(e! as Map<String, Object?>))
        .toList(growable: false);
    return OcrCharacter(
      text: json['text']! as String,
      boundingBox: OcrRect.fromJson(
        json['boundingBox']! as Map<String, Object?>,
      ),
      confidence: (json['confidence']! as num).toDouble(),
      alternatives: alts,
    );
  }

  /// Recognized character symbol.
  final String text;

  /// Tight bounding box in original image coordinates.
  final OcrRect boundingBox;

  /// Calibrated confidence score in `[0.0, 1.0]`.
  final double confidence;

  /// Top-K ranked classifier candidates including [text].
  final List<OcrCandidate> alternatives;

  /// Returns a copy with selectively replaced fields.
  OcrCharacter copyWith({
    String? text,
    OcrRect? boundingBox,
    double? confidence,
    List<OcrCandidate>? alternatives,
  }) => OcrCharacter(
    text: text ?? this.text,
    boundingBox: boundingBox ?? this.boundingBox,
    confidence: confidence ?? this.confidence,
    alternatives: alternatives ?? this.alternatives,
  );

  /// Serializes this character to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'boundingBox': boundingBox.toJson(),
    'confidence': confidence,
    'alternatives': alternatives
        .map((OcrCandidate c) => c.toJson())
        .toList(growable: false),
  };

  @override
  String toString() => 'OcrCharacter("$text", $boundingBox)';
}

/// A contiguous recognized word composed of one or more [OcrCharacter] glyphs.
@immutable
class OcrWord {
  /// Creates an [OcrWord].
  OcrWord({
    required this.text,
    required this.boundingBox,
    required this.confidence,
    required List<OcrCharacter> characters,
  }) : characters = List<OcrCharacter>.unmodifiable(characters);

  /// Creates an [OcrWord] from a JSON map.
  factory OcrWord.fromJson(Map<String, Object?> json) {
    final chars = (json['characters'] as List<Object?>? ?? const <Object?>[])
        .map((Object? e) => OcrCharacter.fromJson(e! as Map<String, Object?>))
        .toList(growable: false);
    return OcrWord(
      text: json['text']! as String,
      boundingBox: OcrRect.fromJson(
        json['boundingBox']! as Map<String, Object?>,
      ),
      confidence: (json['confidence']! as num).toDouble(),
      characters: chars,
    );
  }

  /// Recognized word text.
  final String text;

  /// Bounding box enclosing all characters of this word.
  final OcrRect boundingBox;

  /// Mean confidence score in `[0.0, 1.0]`.
  final double confidence;

  /// Individual characters forming this word in reading order.
  final List<OcrCharacter> characters;

  /// Corner polygon derived from [boundingBox].
  OcrPolygon get polygon => boundingBox.toPolygon();

  /// Serializes this word to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'boundingBox': boundingBox.toJson(),
    'confidence': confidence,
    'characters': characters
        .map((OcrCharacter c) => c.toJson())
        .toList(growable: false),
  };

  @override
  String toString() =>
      'OcrWord("$text", ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// A single horizontal line of recognized words.
@immutable
class OcrLine {
  /// Creates an [OcrLine].
  OcrLine({
    required this.text,
    required this.boundingBox,
    required this.confidence,
    required List<OcrWord> words,
    this.baselineY,
  }) : words = List<OcrWord>.unmodifiable(words);

  /// Creates an [OcrLine] from a JSON map.
  factory OcrLine.fromJson(Map<String, Object?> json) {
    final words = (json['words'] as List<Object?>? ?? const <Object?>[])
        .map((Object? e) => OcrWord.fromJson(e! as Map<String, Object?>))
        .toList(growable: false);
    return OcrLine(
      text: json['text']! as String,
      boundingBox: OcrRect.fromJson(
        json['boundingBox']! as Map<String, Object?>,
      ),
      confidence: (json['confidence']! as num).toDouble(),
      words: words,
      baselineY: (json['baselineY'] as num?)?.toDouble(),
    );
  }

  /// Space-joined text of all [words] in this line.
  final String text;

  /// Bounding box enclosing all words on this line.
  final OcrRect boundingBox;

  /// Estimated typographic baseline Y coordinate in image pixels.
  final double? baselineY;

  /// Mean confidence score in `[0.0, 1.0]`.
  final double confidence;

  /// Words on this line ordered left-to-right.
  final List<OcrWord> words;

  /// Corner polygon derived from [boundingBox].
  OcrPolygon get polygon => boundingBox.toPolygon();

  /// Serializes this line to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'boundingBox': boundingBox.toJson(),
    if (baselineY != null) 'baselineY': baselineY,
    'confidence': confidence,
    'words': words.map((OcrWord w) => w.toJson()).toList(growable: false),
  };

  @override
  String toString() => 'OcrLine("$text")';
}

/// A paragraph, heading, or columnar block grouping related [OcrLine] entries.
@immutable
class OcrBlock {
  /// Creates an [OcrBlock].
  OcrBlock({
    required this.text,
    required this.boundingBox,
    required this.confidence,
    required List<OcrLine> lines,
  }) : lines = List<OcrLine>.unmodifiable(lines);

  /// Creates an [OcrBlock] from a JSON map.
  factory OcrBlock.fromJson(Map<String, Object?> json) {
    final lines = (json['lines'] as List<Object?>? ?? const <Object?>[])
        .map((Object? e) => OcrLine.fromJson(e! as Map<String, Object?>))
        .toList(growable: false);
    return OcrBlock(
      text: json['text']! as String,
      boundingBox: OcrRect.fromJson(
        json['boundingBox']! as Map<String, Object?>,
      ),
      confidence: (json['confidence']! as num).toDouble(),
      lines: lines,
    );
  }

  /// Newline-joined text of all [lines] in this block.
  final String text;

  /// Bounding box enclosing all lines in this block.
  final OcrRect boundingBox;

  /// Mean confidence score in `[0.0, 1.0]`.
  final double confidence;

  /// Lines belonging to this block ordered top-to-bottom.
  final List<OcrLine> lines;

  /// Corner polygon derived from [boundingBox].
  OcrPolygon get polygon => boundingBox.toPolygon();

  /// Serializes this block to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'boundingBox': boundingBox.toJson(),
    'confidence': confidence,
    'lines': lines.map((OcrLine l) => l.toJson()).toList(growable: false),
  };

  @override
  String toString() => 'OcrBlock(${lines.length} lines)';
}

/// Detailed timing and pipeline telemetry produced alongside an [OcrResult].
@immutable
class OcrMetrics {
  /// Creates an [OcrMetrics] snapshot.
  const OcrMetrics({
    required this.processingTime,
    this.preprocessTime = Duration.zero,
    this.segmentationTime = Duration.zero,
    this.recognitionTime = Duration.zero,
    this.detectedSkewAngle = 0.0,
    this.wasInverted = false,
    this.usedAdaptiveThreshold = false,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.blockCount = 0,
    this.lineCount = 0,
    this.wordCount = 0,
    this.characterCount = 0,
  });

  /// Creates an [OcrMetrics] from a JSON map.
  factory OcrMetrics.fromJson(Map<String, Object?> json) => OcrMetrics(
    processingTime: Duration(
      microseconds: (json['processingTimeUs'] as num?)?.toInt() ?? 0,
    ),
    preprocessTime: Duration(
      microseconds: (json['preprocessTimeUs'] as num?)?.toInt() ?? 0,
    ),
    segmentationTime: Duration(
      microseconds: (json['segmentationTimeUs'] as num?)?.toInt() ?? 0,
    ),
    recognitionTime: Duration(
      microseconds: (json['recognitionTimeUs'] as num?)?.toInt() ?? 0,
    ),
    detectedSkewAngle: (json['detectedSkewAngle'] as num?)?.toDouble() ?? 0.0,
    wasInverted: json['wasInverted'] as bool? ?? false,
    usedAdaptiveThreshold: json['usedAdaptiveThreshold'] as bool? ?? false,
    imageWidth: (json['imageWidth'] as num?)?.toInt() ?? 0,
    imageHeight: (json['imageHeight'] as num?)?.toInt() ?? 0,
    blockCount: (json['blockCount'] as num?)?.toInt() ?? 0,
    lineCount: (json['lineCount'] as num?)?.toInt() ?? 0,
    wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
    characterCount: (json['characterCount'] as num?)?.toInt() ?? 0,
  );

  /// End-to-end recognition latency.
  final Duration processingTime;

  /// Time spent in image preprocessing and binarization.
  final Duration preprocessTime;

  /// Time spent in connected-component analysis and layout segmentation.
  final Duration segmentationTime;

  /// Time spent in glyph feature extraction, classification, and post-processing.
  final Duration recognitionTime;

  /// Detected document skew angle in degrees (positive = clockwise tilt).
  final double detectedSkewAngle;

  /// Whether dark-mode polarity inversion was applied automatically.
  final bool wasInverted;

  /// Whether local adaptive thresholding (Sauvola/Bradley) was used.
  final bool usedAdaptiveThreshold;

  /// Width of the recognized source image in pixels.
  final int imageWidth;

  /// Height of the recognized source image in pixels.
  final int imageHeight;

  /// Number of detected text blocks.
  final int blockCount;

  /// Number of detected text lines.
  final int lineCount;

  /// Number of detected words.
  final int wordCount;

  /// Number of detected characters.
  final int characterCount;

  /// Serializes metrics to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'processingTimeUs': processingTime.inMicroseconds,
    'preprocessTimeUs': preprocessTime.inMicroseconds,
    'segmentationTimeUs': segmentationTime.inMicroseconds,
    'recognitionTimeUs': recognitionTime.inMicroseconds,
    'detectedSkewAngle': detectedSkewAngle,
    'wasInverted': wasInverted,
    'usedAdaptiveThreshold': usedAdaptiveThreshold,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'blockCount': blockCount,
    'lineCount': lineCount,
    'wordCount': wordCount,
    'characterCount': characterCount,
  };
}

/// Complete hierarchical recognition output returned by [OcrRecognizer].
@immutable
class OcrResult {
  /// Creates an [OcrResult].
  OcrResult({
    required this.text,
    required List<OcrBlock> blocks,
    required this.confidence,
    required this.imageWidth,
    required this.imageHeight,
    required this.metrics,
    List<OcrEntity> entities = const <OcrEntity>[],
  }) : blocks = List<OcrBlock>.unmodifiable(blocks),
       entities = List<OcrEntity>.unmodifiable(entities);

  /// Creates an empty [OcrResult] for images containing no readable text.
  factory OcrResult.empty({
    int imageWidth = 0,
    int imageHeight = 0,
    OcrMetrics? metrics,
  }) => OcrResult(
    text: '',
    blocks: const <OcrBlock>[],
    confidence: 0,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    metrics:
        metrics ??
        OcrMetrics(
          processingTime: Duration.zero,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        ),
  );

  /// Creates an [OcrResult] from a JSON map.
  factory OcrResult.fromJson(Map<String, Object?> json) {
    final blocks = (json['blocks'] as List<Object?>? ?? const <Object?>[])
        .map((Object? e) => OcrBlock.fromJson(e! as Map<String, Object?>))
        .toList(growable: false);
    final entities = (json['entities'] as List<Object?>? ?? const <Object?>[])
        .map((Object? e) => OcrEntity.fromJson(e! as Map<String, Object?>))
        .toList(growable: false);
    return OcrResult(
      text: json['text']! as String,
      blocks: blocks,
      entities: entities,
      confidence: (json['confidence']! as num).toDouble(),
      imageWidth: (json['imageWidth']! as num).toInt(),
      imageHeight: (json['imageHeight']! as num).toInt(),
      metrics: OcrMetrics.fromJson(
        json['metrics'] as Map<String, Object?>? ?? const <String, Object?>{},
      ),
    );
  }

  /// Full recognized document text in natural reading order.
  final String text;

  /// Top-level paragraph/column blocks in reading order.
  final List<OcrBlock> blocks;

  /// Structured entities automatically extracted from [text].
  final List<OcrEntity> entities;

  /// Weighted overall confidence score in `[0.0, 1.0]`.
  final double confidence;

  /// Source image width in pixels.
  final int imageWidth;

  /// Source image height in pixels.
  final int imageHeight;

  /// Timing and pipeline diagnostic metrics.
  final OcrMetrics metrics;

  /// Whether no text was recognized.
  bool get isEmpty => text.trim().isEmpty;

  /// Whether at least one character of text was recognized.
  bool get isNotEmpty => !isEmpty;

  /// Flat list of all [OcrLine] entries across every block.
  List<OcrLine> get lines =>
      blocks.expand((OcrBlock b) => b.lines).toList(growable: false);

  /// Flat list of all [OcrWord] entries across every line.
  List<OcrWord> get words =>
      lines.expand((OcrLine l) => l.words).toList(growable: false);

  /// Flat list of all [OcrCharacter] entries across every word.
  List<OcrCharacter> get characters =>
      words.expand((OcrWord w) => w.characters).toList(growable: false);

  /// Returns all extracted entities of a specific [type].
  List<OcrEntity> entitiesOfType(OcrEntityType type) =>
      entities.where((OcrEntity e) => e.type == type).toList(growable: false);

  /// Returns the [OcrWord] containing [point], or `null` if none matches.
  OcrWord? wordAt(OcrPoint point) {
    for (final word in words) {
      if (word.boundingBox.containsPoint(point)) return word;
    }
    return null;
  }

  /// Returns the [OcrLine] containing [point], or `null` if none matches.
  OcrLine? lineAt(OcrPoint point) {
    for (final line in lines) {
      if (line.boundingBox.containsPoint(point)) return line;
    }
    return null;
  }

  /// Returns the [OcrBlock] containing [point], or `null` if none matches.
  OcrBlock? blockAt(OcrPoint point) {
    for (final block in blocks) {
      if (block.boundingBox.containsPoint(point)) return block;
    }
    return null;
  }

  /// Returns all words intersecting [selectionRect] in reading order.
  List<OcrWord> wordsInRect(OcrRect selectionRect) => words
      .where((OcrWord w) => w.boundingBox.intersects(selectionRect))
      .toList(growable: false);

  /// Finds all [OcrWord] entries matching [pattern] (case-insensitive for
  /// plain [String] queries, or exact for [RegExp]).
  List<OcrWord> findMatches(Pattern pattern) {
    if (pattern is String) {
      final needle = pattern.toLowerCase();
      return words
          .where((OcrWord w) => w.text.toLowerCase().contains(needle))
          .toList(growable: false);
    }
    return words
        .where((OcrWord w) => pattern.allMatches(w.text).isNotEmpty)
        .toList(growable: false);
  }

  /// Returns a filtered copy retaining only words with confidence >= [minConfidence].
  OcrResult filterByConfidence(double minConfidence) {
    final filteredBlocks = <OcrBlock>[];
    for (final block in blocks) {
      final filteredLines = <OcrLine>[];
      for (final line in block.lines) {
        final keptWords = line.words
            .where((OcrWord w) => w.confidence >= minConfidence)
            .toList(growable: false);
        if (keptWords.isEmpty) continue;
        var lineBox = keptWords.first.boundingBox;
        var sumConf = 0.0;
        for (final w in keptWords) {
          lineBox = lineBox.union(w.boundingBox);
          sumConf += w.confidence;
        }
        filteredLines.add(
          OcrLine(
            text: keptWords.map((OcrWord w) => w.text).join(' '),
            boundingBox: lineBox,
            baselineY: line.baselineY,
            confidence: sumConf / keptWords.length,
            words: keptWords,
          ),
        );
      }
      if (filteredLines.isEmpty) continue;
      var blockBox = filteredLines.first.boundingBox;
      var sumConf = 0.0;
      for (final l in filteredLines) {
        blockBox = blockBox.union(l.boundingBox);
        sumConf += l.confidence;
      }
      filteredBlocks.add(
        OcrBlock(
          text: filteredLines.map((OcrLine l) => l.text).join('\n'),
          boundingBox: blockBox,
          confidence: sumConf / filteredLines.length,
          lines: filteredLines,
        ),
      );
    }
    final allWords = filteredBlocks
        .expand((OcrBlock b) => b.lines)
        .expand((OcrLine l) => l.words)
        .toList(growable: false);
    final avgConf = allWords.isEmpty
        ? 0.0
        : allWords.fold<double>(
                0.0,
                (double s, OcrWord w) => s + w.confidence,
              ) /
              allWords.length;
    return OcrResult(
      text: filteredBlocks.map((OcrBlock b) => b.text).join('\n\n'),
      blocks: filteredBlocks,
      entities: entities
          .where((OcrEntity e) => e.confidence >= minConfidence)
          .toList(growable: false),
      confidence: avgConf,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      metrics: metrics,
    );
  }

  /// Exports the recognized document layout as clean Markdown text.
  String toMarkdown() {
    if (blocks.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) buffer.writeln();
      buffer.writeln(blocks[i].text);
    }
    return buffer.toString().trimRight();
  }

  /// Exports all detected words and bounding boxes as RFC-4180 CSV rows.
  String toCsv() {
    final buffer = StringBuffer()
      ..writeln('block,line,word,text,confidence,left,top,width,height');
    for (var b = 0; b < blocks.length; b++) {
      final block = blocks[b];
      for (var l = 0; l < block.lines.length; l++) {
        final line = block.lines[l];
        for (var w = 0; w < line.words.length; w++) {
          final word = line.words[w];
          final escaped = '"${word.text.replaceAll('"', '""')}"';
          final box = word.boundingBox;
          buffer.writeln(
            '$b,$l,$w,$escaped,${word.confidence.toStringAsFixed(4)},'
            '${box.left.toStringAsFixed(1)},${box.top.toStringAsFixed(1)},'
            '${box.width.toStringAsFixed(1)},${box.height.toStringAsFixed(1)}',
          );
        }
      }
    }
    return buffer.toString();
  }

  /// Serializes this result to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'confidence': confidence,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'blocks': blocks.map((OcrBlock b) => b.toJson()).toList(growable: false),
    'entities': entities
        .map((OcrEntity e) => e.toJson())
        .toList(growable: false),
    'metrics': metrics.toJson(),
  };

  /// Encodes this result as a formatted JSON string.
  String toJsonString({bool pretty = false}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  @override
  String toString() =>
      'OcrResult(${words.length} words, '
      '${(confidence * 100).toStringAsFixed(1)}% confidence)';
}
