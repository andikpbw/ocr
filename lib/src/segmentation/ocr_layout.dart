import 'dart:math' as math;

import '../models/ocr_config.dart';
import '../models/ocr_geometry.dart';
import 'ocr_ccl.dart';
import 'ocr_glyph_splitter.dart';

/// A segmented word consisting of ordered glyph blobs prior to classification.
class SegmentedWord {
  /// Creates a [SegmentedWord].
  const SegmentedWord({required this.glyphs, required this.boundingBox});

  /// Individual character blobs ordered left-to-right.
  final List<OcrGlyphBlob> glyphs;

  /// Tight bounding box of this word in preprocessed image coordinates.
  final OcrRect boundingBox;
}

/// A segmented horizontal text line with estimated typographic baselines.
class SegmentedLine {
  /// Creates a [SegmentedLine].
  const SegmentedLine({
    required this.words,
    required this.boundingBox,
    required this.capTop,
    required this.baselineY,
    required this.capHeight,
  });

  /// Words belonging to this line ordered left-to-right.
  final List<SegmentedWord> words;

  /// Bounding box enclosing the entire line.
  final OcrRect boundingBox;

  /// Estimated Y coordinate of uppercase / ascender tops.
  final double capTop;

  /// Estimated typographic baseline Y coordinate.
  final double baselineY;

  /// Estimated cap height (`baselineY - capTop`).
  final double capHeight;
}

/// A segmented paragraph, heading, or column block grouping related lines.
class SegmentedBlock {
  /// Creates a [SegmentedBlock].
  const SegmentedBlock({required this.lines, required this.boundingBox});

  /// Lines belonging to this block ordered top-to-bottom.
  final List<SegmentedLine> lines;

  /// Bounding box enclosing all lines in this block.
  final OcrRect boundingBox;
}

/// Groups connected components into hierarchically ordered blocks, lines, and
/// words with adaptive word-spacing and robust typographic baseline estimation.
class OcrLayoutAnalyzer {
  const OcrLayoutAnalyzer._();

  /// Segments [blobs] into reading-order [SegmentedBlock] hierarchies.
  static List<SegmentedBlock> segment(
    List<OcrGlyphBlob> blobs, {
    required OcrPageSegmentationMode mode,
  }) {
    if (blobs.isEmpty) return const <SegmentedBlock>[];

    // Estimate global characteristic glyph height to separate anchors from tiny
    // punctuation (`.`, `,`, `-`, `'`).
    final heights = blobs.map((OcrGlyphBlob b) => b.height).toList()..sort();
    final globalTallH =
        heights[(heights.length * 0.72).floor().clamp(0, heights.length - 1)]
            .toDouble();
    final minAnchorH = math.max(3.0, globalTallH * 0.38);

    List<List<OcrGlyphBlob>> rawLines;
    if (mode == OcrPageSegmentationMode.singleLine ||
        mode == OcrPageSegmentationMode.singleWord) {
      rawLines = <List<OcrGlyphBlob>>[List<OcrGlyphBlob>.from(blobs)];
    } else {
      rawLines = _clusterIntoLines(blobs, minAnchorH);
    }

    // Build typed SegmentedLine objects with multi-part reattachment, touching
    // glyph splitting, baseline estimation, and word grouping.
    final lines = <SegmentedLine>[];
    for (final raw in rawLines) {
      if (raw.isEmpty) continue;
      final lineTallH = _estimateLineCapHeightSeed(raw);
      final reattached = OcrCcl.mergeLineMultiPartGlyphs(
        raw,
        estimatedLineHeight: lineTallH,
      );
      final split = OcrGlyphSplitter.splitTouchingBlobs(
        reattached,
        estimatedLineHeight: lineTallH,
      );
      if (split.isEmpty) continue;

      final metrics = _estimateLineTypography(split);
      final words = mode == OcrPageSegmentationMode.singleWord
          ? <SegmentedWord>[_buildWord(split)]
          : _groupIntoWords(split, metrics.capHeight);

      var box = words.first.boundingBox;
      for (var i = 1; i < words.length; i++) {
        box = box.union(words[i].boundingBox);
      }

      lines.add(
        SegmentedLine(
          words: words,
          boundingBox: box,
          capTop: metrics.capTop,
          baselineY: metrics.baselineY,
          capHeight: metrics.capHeight,
        ),
      );
    }

    if (lines.isEmpty) return const <SegmentedBlock>[];

    // Sort lines top-to-bottom, then left-to-right.
    lines.sort((SegmentedLine a, SegmentedLine b) {
      final dy = a.boundingBox.top.compareTo(b.boundingBox.top);
      if (dy != 0) return dy;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });

    if (mode == OcrPageSegmentationMode.singleBlock ||
        mode == OcrPageSegmentationMode.singleLine ||
        mode == OcrPageSegmentationMode.singleWord) {
      var blockBox = lines.first.boundingBox;
      for (var i = 1; i < lines.length; i++) {
        blockBox = blockBox.union(lines[i].boundingBox);
      }
      return <SegmentedBlock>[
        SegmentedBlock(lines: lines, boundingBox: blockBox),
      ];
    }

    return _clusterIntoBlocks(lines);
  }

  static List<List<OcrGlyphBlob>> _clusterIntoLines(
    List<OcrGlyphBlob> blobs,
    double minAnchorH,
  ) {
    final anchors = <OcrGlyphBlob>[];
    final smalls = <OcrGlyphBlob>[];
    for (final b in blobs) {
      if (b.height >= minAnchorH || b.width >= minAnchorH * 1.2) {
        anchors.add(b);
      } else {
        smalls.add(b);
      }
    }
    if (anchors.isEmpty) {
      anchors.addAll(smalls);
      smalls.clear();
    }

    // Sort anchors by vertical center so horizontal lines cluster cleanly.
    anchors.sort((OcrGlyphBlob a, OcrGlyphBlob b) {
      final cy = a.centerY.compareTo(b.centerY);
      return cy != 0 ? cy : a.left.compareTo(b.left);
    });

    final lineClusters = <_LineAccumulator>[];
    for (final blob in anchors) {
      _LineAccumulator? bestLine;
      var bestScore = double.infinity;

      for (final line in lineClusters) {
        final overlapY =
            math.min(line.bottom, blob.bottom.toDouble()) -
            math.max(line.top, blob.top.toDouble());
        final minH = math.min(line.avgHeight, blob.height.toDouble());
        final dy = (line.centerY - blob.centerY).abs();

        // Require meaningful vertical overlap or tight center proximity.
        final sameLine =
            (overlapY >= minH * 0.30) || (dy <= minH * 0.52 && overlapY > -2);
        if (!sameLine) continue;

        if (dy < bestScore) {
          bestScore = dy;
          bestLine = line;
        }
      }

      if (bestLine != null) {
        bestLine.add(blob);
      } else {
        lineClusters.add(_LineAccumulator(blob));
      }
    }

    // Assign small punctuation / diacritic blobs to their closest matching line.
    for (final s in smalls) {
      _LineAccumulator? target;
      var bestDist = double.infinity;
      for (final line in lineClusters) {
        final pad = math.max(4.0, line.avgHeight * 0.45);
        if (s.bottom < line.top - pad || s.top > line.bottom + pad) continue;
        final verticalDist = (s.centerY - line.centerY).abs();
        // Also ensure horizontal proximity so dots don't jump across columns.
        final hDist = s.right < line.left
            ? line.left - s.right
            : (s.left > line.right ? s.left - line.right : 0.0);
        if (hDist > line.avgHeight * 3.5) continue;

        final dist = verticalDist + hDist * 0.15;
        if (dist < bestDist) {
          bestDist = dist;
          target = line;
        }
      }
      if (target != null) {
        target.blobs.add(s);
      } else {
        lineClusters.add(_LineAccumulator(s));
      }
    }

    // Split wide side-by-side columns that happened to sit on the same Y band
    // only when separated by a massive horizontal gutter (> 5x line height).
    final splitLines = <List<OcrGlyphBlob>>[];
    for (final acc in lineClusters) {
      acc.blobs.sort(
        (OcrGlyphBlob a, OcrGlyphBlob b) => a.left.compareTo(b.left),
      );
      final gutterThreshold = math.max(40.0, acc.avgHeight * 5.2);
      var current = <OcrGlyphBlob>[acc.blobs.first];
      var prevRight = acc.blobs.first.right;

      for (var i = 1; i < acc.blobs.length; i++) {
        final b = acc.blobs[i];
        if (b.left - prevRight > gutterThreshold) {
          splitLines.add(current);
          current = <OcrGlyphBlob>[b];
        } else {
          current.add(b);
        }
        if (b.right > prevRight) prevRight = b.right;
      }
      splitLines.add(current);
    }

    return splitLines;
  }

  static double _estimateLineCapHeightSeed(List<OcrGlyphBlob> blobs) {
    final hs = blobs.map((OcrGlyphBlob b) => b.height).toList()..sort();
    return math.max(
      6.0,
      hs[(hs.length * 0.80).floor().clamp(0, hs.length - 1)].toDouble(),
    );
  }

  static _LineTypography _estimateLineTypography(List<OcrGlyphBlob> blobs) {
    final maxH = blobs.fold<int>(
      0,
      (int m, OcrGlyphBlob b) => math.max(m, b.height),
    );
    final substantial = blobs
        .where((OcrGlyphBlob b) => b.height >= maxH * 0.42)
        .toList(growable: false);
    final pool = substantial.isNotEmpty ? substantial : blobs;

    // Baseline: find the dominant bottom-edge cluster (since most letters sit
    // directly on the baseline, while descenders dip below).
    final bottoms = pool.map((OcrGlyphBlob b) => b.bottom.toDouble()).toList()
      ..sort();
    final tol = math.max(2.0, maxH * 0.12);
    var bestClusterStart = 0;
    var bestClusterLen = 0;
    for (var i = 0; i < bottoms.length; i++) {
      var j = i;
      while (j < bottoms.length && bottoms[j] - bottoms[i] <= tol) {
        j++;
      }
      final len = j - i;
      // Prefer the largest cluster; break ties toward lower (baseline) cluster.
      if (len >= bestClusterLen) {
        bestClusterLen = len;
        bestClusterStart = i;
      }
    }
    final baselineY = bottoms[bestClusterStart + bestClusterLen ~/ 2];

    // Cap top: top edge of the tallest non-descender-only glyphs (15th percentile).
    final tops = pool.map((OcrGlyphBlob b) => b.top.toDouble()).toList()
      ..sort();
    final capTop = tops[(tops.length * 0.15).floor().clamp(0, tops.length - 1)];

    final capHeight = math.max(4.0, baselineY - capTop);
    return _LineTypography(
      capTop: capTop,
      baselineY: baselineY,
      capHeight: capHeight,
    );
  }

  static List<SegmentedWord> _groupIntoWords(
    List<OcrGlyphBlob> sortedBlobs,
    double capHeight,
  ) {
    if (sortedBlobs.length == 1) {
      return <SegmentedWord>[_buildWord(sortedBlobs)];
    }

    // Estimate characteristic character width (median of non-punctuation glyphs).
    final charWidths =
        sortedBlobs
            .where((OcrGlyphBlob b) => b.height >= capHeight * 0.45)
            .map((OcrGlyphBlob b) => b.width.toDouble())
            .toList()
          ..sort();
    final medianCharW = charWidths.isNotEmpty
        ? charWidths[charWidths.length ~/ 2]
        : capHeight * 0.62;

    // Collect positive inter-glyph gaps.
    final gaps = <double>[];
    for (var i = 1; i < sortedBlobs.length; i++) {
      final g = (sortedBlobs[i].left - sortedBlobs[i - 1].right).toDouble();
      if (g > 0) gaps.add(g);
    }

    // Compute adaptive space threshold combining typographic priors with
    // bimodal gap separation when the line contains multiple words.
    var spaceThreshold = math.max(capHeight * 0.30, medianCharW * 0.45);

    if (gaps.length >= 4) {
      final sortedGaps = List<double>.from(gaps)..sort();
      final minG = sortedGaps.first;
      final maxG = sortedGaps.last;
      if (maxG > minG * 2.2 && maxG >= capHeight * 0.28) {
        // 1D Otsu-style split on gap sizes bounded within typographic limits.
        var bestSplit = spaceThreshold;
        var bestVar = -1.0;
        for (var i = 1; i < sortedGaps.length; i++) {
          final cand = (sortedGaps[i - 1] + sortedGaps[i]) * 0.5;
          if (cand < capHeight * 0.27 || cand > capHeight * 0.58) continue;
          var sumL = 0.0;
          for (var k = 0; k < i; k++) {
            sumL += sortedGaps[k];
          }
          var sumR = 0.0;
          for (var k = i; k < sortedGaps.length; k++) {
            sumR += sortedGaps[k];
          }
          final meanL = sumL / i;
          final meanR = sumR / (sortedGaps.length - i);
          if (meanR < meanL * 1.9) continue;
          final diff = meanR - meanL;
          final betweenVar = i * (sortedGaps.length - i) * diff * diff;
          if (betweenVar > bestVar) {
            bestVar = betweenVar;
            bestSplit = cand;
          }
        }
        if (bestVar > 0) {
          spaceThreshold = bestSplit;
        }
      }
    }

    final words = <SegmentedWord>[];
    var current = <OcrGlyphBlob>[sortedBlobs.first];
    var prev = sortedBlobs.first;

    for (var i = 1; i < sortedBlobs.length; i++) {
      final curr = sortedBlobs[i];
      final gap = (curr.left - prev.right).toDouble();
      // Keep tight punctuation (`,` `.` `:` `;` `-`) attached to preceding glyph
      // and avoid splitting adjacent ultra-narrow glyphs (`11`, `II`).
      final trailingSmallPunct =
          curr.height < capHeight * 0.42 && curr.width < capHeight * 0.45;
      final bothUltraNarrow =
          prev.width < capHeight * 0.34 && curr.width < capHeight * 0.34;
      final effectiveThreshold = (trailingSmallPunct || bothUltraNarrow)
          ? spaceThreshold * 1.24
          : spaceThreshold;
      if (gap > effectiveThreshold) {
        words.add(_buildWord(current));
        current = <OcrGlyphBlob>[curr];
      } else {
        current.add(curr);
      }
      prev = curr;
    }
    words.add(_buildWord(current));
    return words;
  }

  static SegmentedWord _buildWord(List<OcrGlyphBlob> glyphs) {
    var box = glyphs.first.rect;
    for (var i = 1; i < glyphs.length; i++) {
      box = box.union(glyphs[i].rect);
    }
    return SegmentedWord(glyphs: glyphs, boundingBox: box);
  }

  static List<SegmentedBlock> _clusterIntoBlocks(List<SegmentedLine> lines) {
    final blocks = <List<SegmentedLine>>[];
    final blockBoxes = <OcrRect>[];

    for (final line in lines) {
      var assignedIndex = -1;
      var bestGap = double.infinity;

      for (var i = 0; i < blocks.length; i++) {
        final lastLine = blocks[i].last;
        final bBox = blockBoxes[i];
        final vGap = line.boundingBox.top - lastLine.boundingBox.bottom;
        final refH = math.max(lastLine.capHeight, line.capHeight);

        // Must be vertically close and have comparable font scale.
        if (vGap < -refH * 0.4 || vGap > refH * 1.45) continue;
        final heightRatio =
            math.max(lastLine.capHeight, line.capHeight) /
            math.max(1.0, math.min(lastLine.capHeight, line.capHeight));
        if (heightRatio > 1.75) continue;

        // Must share horizontal overlap or close left alignment (same column).
        final overlapX =
            math.min(bBox.right, line.boundingBox.right) -
            math.max(bBox.left, line.boundingBox.left);
        final alignedLeft =
            (bBox.left - line.boundingBox.left).abs() <= refH * 2.5;
        if (overlapX <= 0 && !alignedLeft) continue;

        if (vGap < bestGap) {
          bestGap = vGap;
          assignedIndex = i;
        }
      }

      if (assignedIndex >= 0) {
        blocks[assignedIndex].add(line);
        blockBoxes[assignedIndex] = blockBoxes[assignedIndex].union(
          line.boundingBox,
        );
      } else {
        blocks.add(<SegmentedLine>[line]);
        blockBoxes.add(line.boundingBox);
      }
    }

    final result = <SegmentedBlock>[];
    for (var i = 0; i < blocks.length; i++) {
      result.add(SegmentedBlock(lines: blocks[i], boundingBox: blockBoxes[i]));
    }

    // Sort blocks in natural reading order (top-to-bottom, left-to-right).
    result.sort((SegmentedBlock a, SegmentedBlock b) {
      final verticalOverlap =
          math.min(a.boundingBox.bottom, b.boundingBox.bottom) -
          math.max(a.boundingBox.top, b.boundingBox.top);
      final minH = math.min(a.boundingBox.height, b.boundingBox.height);
      if (verticalOverlap > minH * 0.5) {
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      return a.boundingBox.top.compareTo(b.boundingBox.top);
    });

    return result;
  }
}

class _LineAccumulator {
  _LineAccumulator(OcrGlyphBlob first)
    : blobs = <OcrGlyphBlob>[first],
      top = first.top.toDouble(),
      bottom = first.bottom.toDouble(),
      left = first.left.toDouble(),
      right = first.right.toDouble(),
      _heightSum = first.height.toDouble(),
      _centerYSum = first.centerY;

  final List<OcrGlyphBlob> blobs;
  double top;
  double bottom;
  double left;
  double right;
  double _heightSum;
  double _centerYSum;

  double get avgHeight => _heightSum / blobs.length;
  double get centerY => _centerYSum / blobs.length;

  void add(OcrGlyphBlob b) {
    blobs.add(b);
    if (b.top < top) top = b.top.toDouble();
    if (b.bottom > bottom) bottom = b.bottom.toDouble();
    if (b.left < left) left = b.left.toDouble();
    if (b.right > right) right = b.right.toDouble();
    _heightSum += b.height;
    _centerYSum += b.centerY;
  }
}

class _LineTypography {
  const _LineTypography({
    required this.capTop,
    required this.baselineY,
    required this.capHeight,
  });

  final double capTop;
  final double baselineY;
  final double capHeight;
}
