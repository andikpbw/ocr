import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ocr_result.dart';
import 'ocr_glyph_features.dart';
import 'ocr_vector_atlas.dart';

/// Multi-cue hybrid character classifier combining blurred ZNCC, positive
/// cosine similarity, 4x4 zoning, directional Sobel gradients, topological hole
/// structure, stroke crossings, and line-relative typographic geometry.
class OcrGlyphClassifier {
  /// Creates an [OcrGlyphClassifier] backed by [prototypes].
  OcrGlyphClassifier(List<OcrGlyphPrototype> prototypes)
    : _prototypes = List<OcrGlyphPrototype>.unmodifiable(prototypes);

  final List<OcrGlyphPrototype> _prototypes;

  /// Number of loaded reference prototypes.
  int get prototypeCount => _prototypes.length;

  /// Classifies [query] and returns up to [topK] ranked [OcrCandidate]s.
  ///
  /// When [allowedCharacters] is non-null, only prototypes whose character is
  /// contained in [allowedCharacters] are scored.
  List<OcrCandidate> classify(
    OcrGlyphFeature query, {
    Set<String>? allowedCharacters,
    Set<String>? excludedCharacters,
    int topK = 3,
    bool useLineGeometry = true,
  }) {
    final bestPerChar = <String, double>{};

    for (var i = 0; i < _prototypes.length; i++) {
      final proto = _prototypes[i];
      final ch = proto.character;
      if (allowedCharacters != null && !allowedCharacters.contains(ch)) {
        continue;
      }
      if (excludedCharacters != null && excludedCharacters.contains(ch)) {
        continue;
      }

      final score = _score(
        query,
        proto.feature,
        priorityBias: proto.priorityBias,
        useLineGeometry: useLineGeometry,
      );
      final prev = bestPerChar[ch];
      if (prev == null || score > prev) {
        bestPerChar[ch] = score;
      }
    }

    if (bestPerChar.isEmpty) {
      return const <OcrCandidate>[OcrCandidate(character: '?', confidence: 0)];
    }

    final ranked = bestPerChar.entries.toList(growable: false)
      ..sort(
        (MapEntry<String, double> a, MapEntry<String, double> b) =>
            b.value.compareTo(a.value),
      );

    final bestScore = ranked.first.value;
    final secondScore = ranked.length > 1 ? ranked[1].value : 0.0;
    final margin = (bestScore - secondScore).clamp(0.0, 0.25);

    final count = math.min(topK, ranked.length);
    final out = <OcrCandidate>[];
    for (var i = 0; i < count; i++) {
      final entry = ranked[i];
      // Calibrate raw similarity into an intuitive [0, 1] probability-like score.
      final raw = entry.value;
      final boost = i == 0 ? margin * 0.45 : 0.0;
      final calibrated = ((raw - 0.18) / 0.80 + boost).clamp(0.0, 0.999);
      out.add(OcrCandidate(character: entry.key, confidence: calibrated));
    }
    return out;
  }

  static double _score(
    OcrGlyphFeature q,
    OcrGlyphFeature p, {
    required double priorityBias,
    required bool useLineGeometry,
  }) {
    // 1. Blurred Zero-Mean Normalized Cross-Correlation [-1, 1] -> [0, 1].
    final zncc = (_dot(q.blurredZncc, p.blurredZncc) + 1.0) * 0.5;

    // 2. Blurred Positive Cosine Similarity [0, 1].
    final cos = _dot(q.blurredCosine, p.blurredCosine).clamp(0.0, 1.0);

    // 3. 4x4 Spatial Zone Density Cosine [0, 1].
    final zone = _dot(q.zoneGrid, p.zoneGrid).clamp(0.0, 1.0);

    // 4. 2x2x4 Sobel Orientation Gradient Cosine [0, 1].
    final grad = _dot(q.gradientHist, p.gradientHist).clamp(0.0, 1.0);

    // 5. Aspect Ratio & Ink Fill Density agreement.
    final arRatio =
        math.max(0.08, q.aspectRatio) / math.max(0.08, p.aspectRatio);
    final arSim = math.exp(-math.log(arRatio).abs() * 1.35);
    final denSim = (1.0 - (q.inkDensity - p.inkDensity).abs() * 1.4).clamp(
      0.0,
      1.0,
    );

    // 6. Topological Interior Hole + Stroke Crossing similarity.
    var topoScore = 1.0;
    final holeDiff = (q.holeCount - p.holeCount).abs();
    if (holeDiff == 1) {
      topoScore -= 0.45;
    } else if (holeDiff >= 2) {
      topoScore -= 0.80;
    } else if (q.holeCount >= 1 &&
        q.holeCentroidY >= 0 &&
        p.holeCentroidY >= 0) {
      // Discriminates top-hole vs bottom-hole pairs (6/9, b/p, d/q, a/e, P/D).
      final dy = (q.holeCentroidY - p.holeCentroidY).abs();
      topoScore -= (dy * 1.3).clamp(0.0, 0.55);
    }

    var crossDiff = 0.0;
    for (var k = 0; k < 3; k++) {
      crossDiff += (q.hCrossings[k] - p.hCrossings[k]).abs();
      crossDiff += (q.vCrossings[k] - p.vCrossings[k]).abs();
    }
    final crossSim = math.exp(-crossDiff * 0.22);

    // Extra discrimination for narrow vertical glyphs (`i` vs `l`/`I`/`1`/`!`),
    // where the center-column vertical crossing count (2 vs 1) is decisive.
    var narrowSplitPenalty = 0.0;
    if (q.aspectRatio < 0.45 && p.aspectRatio < 0.45) {
      final centerVDiff = (q.vCrossings[1] - p.vCrossings[1]).abs();
      if (centerVDiff >= 1.0) {
        narrowSplitPenalty = 0.085;
      }
    }

    var combined =
        zncc * 0.39 +
        cos * 0.13 +
        zone * 0.14 +
        grad * 0.12 +
        arSim * 0.06 +
        denSim * 0.02 +
        topoScore.clamp(0.0, 1.0) * 0.08 +
        crossSim * 0.06 +
        priorityBias -
        narrowSplitPenalty;

    // 7. Line-relative typographic geometry penalty (solves case & punctuation).
    if (useLineGeometry &&
        q.relHeight != null &&
        p.relHeight != null &&
        q.relTop != null &&
        p.relTop != null &&
        q.relBottom != null &&
        p.relBottom != null) {
      final dH = (q.relHeight! - p.relHeight!).abs();
      final dTop = (q.relTop! - p.relTop!).abs();
      final dBot = (q.relBottom! - p.relBottom!).abs();

      // Penalize scale/position disagreement smoothly without breaking slight
      // baseline jitter.
      final geomErr = dH * 0.52 + dTop * 0.30 + dBot * 0.30;
      final penalty = (geomErr * 0.36).clamp(0.0, 0.32);
      combined -= penalty;
    }

    return combined;
  }

  static double _dot(Float32List a, Float32List b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }
}
