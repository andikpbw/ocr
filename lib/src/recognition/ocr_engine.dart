import 'dart:math' as math;

import '../models/ocr_config.dart';
import '../models/ocr_entity.dart';
import '../models/ocr_geometry.dart';
import '../models/ocr_image.dart';
import '../models/ocr_result.dart';
import '../preprocessing/ocr_preprocessor.dart';
import '../segmentation/ocr_ccl.dart';
import '../segmentation/ocr_layout.dart';
import 'ocr_classifier.dart';
import 'ocr_font_calibrator.dart';
import 'ocr_glyph_features.dart';
import 'ocr_post_processor.dart';
import 'ocr_vector_atlas.dart';

/// Abstract contract for pluggable OCR recognition backends.
///
/// Implement this interface to connect external engines (e.g., native ML Kit,
/// Apple Vision, Tesseract, or Cloud APIs) while preserving the full
/// `flutter_ocr` models, entity extraction, and Flutter UI overlay ecosystem.
abstract class OcrEngine {
  /// Creates an [OcrEngine].
  const OcrEngine();

  /// Human-readable identifier for this OCR engine.
  String get name;

  /// Runs asynchronous text recognition on [image] with the provided [config].
  Future<OcrResult> recognize(
    OcrImage image, {
    OcrConfig config = const OcrConfig(),
  });

  /// Releases any engine resources or caches.
  void dispose() {}
}

/// Zero-dependency, offline, pure-Dart + Flutter OCR engine.
///
/// Executes a full 6-stage computer-vision pipeline:
/// 1. Image preprocessing (luminance, contrast stretch, dark-mode inversion,
///    Otsu/Sauvola/Bradley binarization, despeckling, and automatic deskewing).
/// 2. 8-connectivity Union-Find connected component labeling & multi-part glyph
///    reattachment (`i`, `j`, `!`, `?`, `:`, `;`, `=`, `%`, `"`).
/// 3. Touching-character valley splitting & hierarchical reading-order layout
///    analysis (blocks, lines, baselines, and adaptive word boundaries).
/// 4. Optional live platform font calibration (when running in Flutter).
/// 5. Multi-cue hybrid glyph classification (blurred ZNCC, cosine, 4x4 zoning,
///    Sobel orientation gradients, Euler hole topology, and line typography).
/// 6. Context-aware linguistic post-processing & structured entity extraction.
class BuiltInOcrEngine implements OcrEngine {
  /// Creates a [BuiltInOcrEngine], optionally accepting [customPrototypes] to
  /// augment the built-in multi-style prototype bank.
  BuiltInOcrEngine({List<OcrGlyphPrototype>? customPrototypes})
    : _customPrototypes = customPrototypes ?? const <OcrGlyphPrototype>[];

  final List<OcrGlyphPrototype> _customPrototypes;
  OcrGlyphClassifier? _syncClassifier;
  final Map<String, OcrGlyphClassifier> _calibratedClassifiers =
      <String, OcrGlyphClassifier>{};

  @override
  String get name => 'BuiltInOcrEngine';

  @override
  Future<OcrResult> recognize(
    OcrImage image, {
    OcrConfig config = const OcrConfig(),
  }) async {
    final classifier = await _resolveClassifier(config);
    return _runPipeline(image, config, classifier);
  }

  /// Runs the complete OCR pipeline synchronously using the built-in universal
  /// vector prototype bank (ideal for headless isolates and synchronous tests).
  OcrResult recognizeSync(
    OcrImage image, {
    OcrConfig config = const OcrConfig(),
  }) {
    final classifier = _syncClassifier ??= OcrGlyphClassifier(
      <OcrGlyphPrototype>[...OcrVectorAtlas.prototypes, ..._customPrototypes],
    );
    return _runPipeline(image, config, classifier);
  }

  Future<OcrGlyphClassifier> _resolveClassifier(OcrConfig config) async {
    if (!config.enableFontCalibration) {
      return _syncClassifier ??= OcrGlyphClassifier(<OcrGlyphPrototype>[
        ...OcrVectorAtlas.prototypes,
        ..._customPrototypes,
      ]);
    }

    final key =
        '${config.calibrationFontFamilies.join("|")}:${config.script.name}';
    final cached = _calibratedClassifiers[key];
    if (cached != null) return cached;

    final calibrated = await OcrFontCalibrator.calibrate(
      fontFamilies: config.calibrationFontFamilies,
      script: config.script,
    );
    final classifier = OcrGlyphClassifier(<OcrGlyphPrototype>[
      ...OcrVectorAtlas.prototypes,
      ...calibrated,
      ..._customPrototypes,
    ]);
    _calibratedClassifiers[key] = classifier;
    return classifier;
  }

  OcrResult _runPipeline(
    OcrImage image,
    OcrConfig config,
    OcrGlyphClassifier classifier,
  ) {
    final totalWatch = Stopwatch()..start();

    // 1. Preprocessing.
    final preWatch = Stopwatch()..start();
    final pre = OcrPreprocessor.process(
      image,
      config: config.preprocess,
      regionOfInterest: config.regionOfInterest,
    );
    preWatch.stop();

    // 2. Connected Component Labeling & Layout Segmentation.
    final segWatch = Stopwatch()..start();
    final blobs = OcrCcl.extractComponents(
      pre.binary,
      width: pre.width,
      height: pre.height,
    );
    final segBlocks = OcrLayoutAnalyzer.segment(
      blobs,
      mode: config.segmentationMode,
    );
    segWatch.stop();

    if (segBlocks.isEmpty) {
      totalWatch.stop();
      return OcrResult.empty(
        imageWidth: image.width,
        imageHeight: image.height,
        metrics: OcrMetrics(
          processingTime: totalWatch.elapsed,
          preprocessTime: preWatch.elapsed,
          segmentationTime: segWatch.elapsed,
          detectedSkewAngle: -pre.deskewAngle,
          wasInverted: pre.wasInverted,
          usedAdaptiveThreshold: pre.usedAdaptiveThreshold,
          imageWidth: image.width,
          imageHeight: image.height,
        ),
      );
    }

    // 3. Multi-Cue Glyph Classification + Line-Level Case Refinement + Post-Processing.
    final recWatch = Stopwatch()..start();
    final allowed = config.resolveAllowedCharacters();
    final excluded =
        (config.characterBlacklist != null &&
            config.characterBlacklist!.isNotEmpty)
        ? config.characterBlacklist!.split('').toSet()
        : null;

    final blocks = <OcrBlock>[];
    var totalChars = 0;
    var totalWords = 0;
    var totalLines = 0;
    var confSum = 0.0;

    for (final segBlock in segBlocks) {
      final ocrLines = <OcrLine>[];
      for (final segLine in segBlock.lines) {
        final recognizedLine = _recognizeLine(
          segLine,
          pre: pre,
          classifier: classifier,
          allowed: allowed,
          excluded: excluded,
          config: config,
        );
        if (recognizedLine != null) {
          ocrLines.add(recognizedLine);
          totalLines++;
          for (final w in recognizedLine.words) {
            totalWords++;
            for (final c in w.characters) {
              totalChars++;
              confSum += c.confidence;
            }
          }
        }
      }
      if (ocrLines.isEmpty) continue;
      var blockBox = ocrLines.first.boundingBox;
      var blockConfSum = 0.0;
      for (final l in ocrLines) {
        blockBox = blockBox.union(l.boundingBox);
        blockConfSum += l.confidence;
      }
      blocks.add(
        OcrBlock(
          text: ocrLines.map((OcrLine l) => l.text).join('\n'),
          boundingBox: blockBox,
          confidence: blockConfSum / ocrLines.length,
          lines: ocrLines,
        ),
      );
    }

    final fullText = blocks.map((OcrBlock b) => b.text).join('\n\n');
    final allLines = blocks
        .expand((OcrBlock b) => b.lines)
        .toList(growable: false);
    final allWords = allLines
        .expand((OcrLine l) => l.words)
        .toList(growable: false);

    // 4. Optional Structured Entity Extraction.
    final entities = config.extractEntities
        ? OcrEntityExtractor.extract(
            fullText: fullText,
            words: allWords,
            lines: allLines,
          )
        : const <OcrEntity>[];

    recWatch.stop();
    totalWatch.stop();

    final overallConfidence = totalChars > 0 ? confSum / totalChars : 0.0;

    final rawResult = OcrResult(
      text: fullText,
      blocks: blocks,
      entities: entities,
      confidence: overallConfidence,
      imageWidth: image.width,
      imageHeight: image.height,
      metrics: OcrMetrics(
        processingTime: totalWatch.elapsed,
        preprocessTime: preWatch.elapsed,
        segmentationTime: segWatch.elapsed,
        recognitionTime: recWatch.elapsed,
        detectedSkewAngle: -pre.deskewAngle,
        wasInverted: pre.wasInverted,
        usedAdaptiveThreshold: pre.usedAdaptiveThreshold,
        imageWidth: image.width,
        imageHeight: image.height,
        blockCount: blocks.length,
        lineCount: totalLines,
        wordCount: totalWords,
        characterCount: totalChars,
      ),
    );

    if (config.minConfidence > 0.0) {
      return rawResult.filterByConfidence(config.minConfidence);
    }
    return rawResult;
  }

  OcrLine? _recognizeLine(
    SegmentedLine segLine, {
    required PreprocessedImage pre,
    required OcrGlyphClassifier classifier,
    required Set<String>? allowed,
    required Set<String>? excluded,
    required OcrConfig config,
  }) {
    final allBlobs = segLine.words
        .expand((SegmentedWord w) => w.glyphs)
        .toList(growable: false);
    if (allBlobs.isEmpty) return null;

    var capTop = segLine.capTop;
    var capHeight = segLine.capHeight;

    // Detect uniform-height all-lowercase lines (no ascenders/capitals) by
    // checking whether shape-only recognition yields distinct lowercase forms.
    if (allBlobs.length >= 2) {
      final nonSmall = allBlobs
          .where((OcrGlyphBlob b) => b.height >= capHeight * 0.55)
          .toList(growable: false);
      if (nonSmall.length >= 2) {
        final minH = nonSmall.fold<int>(
          nonSmall.first.height,
          (int m, OcrGlyphBlob b) => math.min(m, b.height),
        );
        final maxH = nonSmall.fold<int>(
          nonSmall.first.height,
          (int m, OcrGlyphBlob b) => math.max(m, b.height),
        );
        if (maxH <= minH * 1.16) {
          var lowerCue = 0;
          var upperCue = 0;
          for (final b in nonSmall) {
            final feat = OcrGlyphFeature.extractFromBlob(b);
            final top = classifier.classify(
              feat,
              allowedCharacters: allowed,
              excludedCharacters: excluded,
              topK: 1,
              useLineGeometry: false,
            );
            final ch = top.first.character;
            if (_distinctLowercase.contains(ch)) lowerCue++;
            if (_distinctUppercase.contains(ch)) upperCue++;
          }
          if (lowerCue > 0 && upperCue == 0) {
            // Line consists purely of x-height lowercase letters; synthesize
            // virtual capTop above x-height so case-ambiguous letters (c,o,s,v)
            // resolve cleanly to lowercase.
            final xHeight = capHeight;
            capHeight = xHeight / 0.72;
            capTop = segLine.baselineY - capHeight;
          }
        }
      }
    }

    final ocrWords = <OcrWord>[];
    for (final segWord in segLine.words) {
      var chars = <OcrCharacter>[];
      for (final blob in segWord.glyphs) {
        final feature = OcrGlyphFeature.extractFromBlob(
          blob,
          capTop: capTop,
          capHeight: capHeight,
        );
        final candidates = classifier.classify(
          feature,
          allowedCharacters: allowed,
          excludedCharacters: excluded,
          topK: config.maxAlternatives,
          useLineGeometry: allBlobs.length > 1,
        );
        final best = candidates.first;
        chars.add(
          OcrCharacter(
            text: best.character,
            boundingBox: pre.mapRectToSource(blob.rect),
            confidence: best.confidence,
            alternatives: candidates,
          ),
        );
      }

      if (config.enablePostProcessing) {
        final prevWord = ocrWords.isNotEmpty ? ocrWords.last.text : null;
        chars = OcrPostProcessor.refineWordCharacters(
          chars,
          previousWordText: prevWord,
        );
      }

      if (chars.isEmpty) continue;
      var wordBox = chars.first.boundingBox;
      var wordConfSum = 0.0;
      for (final c in chars) {
        wordBox = wordBox.union(c.boundingBox);
        wordConfSum += c.confidence;
      }
      ocrWords.add(
        OcrWord(
          text: chars.map((OcrCharacter c) => c.text).join(),
          boundingBox: wordBox,
          confidence: wordConfSum / chars.length,
          characters: chars,
        ),
      );
    }

    if (ocrWords.isEmpty) return null;
    var lineBox = ocrWords.first.boundingBox;
    var lineConfSum = 0.0;
    for (final w in ocrWords) {
      lineBox = lineBox.union(w.boundingBox);
      lineConfSum += w.confidence;
    }

    final mappedBaseline = pre
        .mapRectToSource(
          OcrRect(
            left: segLine.boundingBox.left,
            top: segLine.baselineY,
            width: 1,
            height: 1,
          ),
        )
        .top;

    return OcrLine(
      text: ocrWords.map((OcrWord w) => w.text).join(' '),
      boundingBox: lineBox,
      baselineY: mappedBaseline,
      confidence: lineConfSum / ocrWords.length,
      words: ocrWords,
    );
  }

  static const Set<String> _distinctLowercase = <String>{
    'a',
    'e',
    'g',
    'm',
    'n',
    'q',
    'r',
    'u',
  };

  static const Set<String> _distinctUppercase = <String>{
    'A',
    'B',
    'D',
    'E',
    'F',
    'G',
    'H',
    'L',
    'M',
    'N',
    'Q',
    'R',
    'T',
    'U',
  };

  @override
  void dispose() {
    _calibratedClassifiers.clear();
    _syncClassifier = null;
  }
}
