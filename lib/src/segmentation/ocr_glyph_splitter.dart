import 'dart:math' as math;
import 'dart:typed_data';

import 'ocr_ccl.dart';

/// Splits abnormally wide connected blobs formed by touching characters using
/// vertical ink-projection valley analysis.
class OcrGlyphSplitter {
  const OcrGlyphSplitter._();

  /// Splits any touching-character blobs in [blobs] relative to
  /// [estimatedLineHeight], preserving naturally wide single glyphs such as
  /// `W`, `M`, `m`, `w`, `@`, and `%`.
  static List<OcrGlyphBlob> splitTouchingBlobs(
    List<OcrGlyphBlob> blobs, {
    required double estimatedLineHeight,
  }) {
    if (blobs.isEmpty || estimatedLineHeight < 8.0) return blobs;
    final output = <OcrGlyphBlob>[];
    for (final blob in blobs) {
      _splitRecursive(blob, estimatedLineHeight, output, depth: 0);
    }
    output.sort((OcrGlyphBlob a, OcrGlyphBlob b) => a.left.compareTo(b.left));
    return output;
  }

  static void _splitRecursive(
    OcrGlyphBlob blob,
    double lineHeight,
    List<OcrGlyphBlob> out, {
    required int depth,
  }) {
    // Only consider blobs noticeably wider than even wide letters (`W`/`M`).
    final tooWide =
        blob.width > lineHeight * 1.28 &&
        blob.aspectRatio > 1.32 &&
        blob.height >= lineHeight * 0.42;

    if (!tooWide || depth >= 4 || blob.width < 12) {
      out.add(blob);
      return;
    }

    // Compute vertical column ink projection.
    final colInk = Int32List(blob.width);
    for (var y = 0; y < blob.height; y++) {
      final row = y * blob.width;
      for (var x = 0; x < blob.width; x++) {
        colInk[x] += blob.mask[row + x];
      }
    }

    // Search inner region [22%..78%] for the cleanest narrow neck/valley.
    final startX = math.max(3, (blob.width * 0.22).round());
    final endX = math.min(blob.width - 4, (blob.width * 0.78).round());
    if (startX >= endX) {
      out.add(blob);
      return;
    }

    var bestX = -1;
    var bestScore = double.infinity;
    final center = blob.width * 0.5;
    final maxAllowedValley = math.max(2, (blob.height * 0.22).round());

    for (var x = startX; x <= endX; x++) {
      final ink = colInk[x];
      if (ink > maxAllowedValley) continue;
      // Favor narrow valleys that also sit between thicker neighboring strokes.
      final leftPeak = _localMax(colInk, math.max(0, x - 6), x - 1);
      final rightPeak = _localMax(
        colInk,
        x + 1,
        math.min(blob.width - 1, x + 6),
      );
      if (leftPeak < ink + 2 || rightPeak < ink + 2) continue;

      final distPenalty = ((x - center).abs() / blob.width) * 1.5;
      final score = ink.toDouble() + distPenalty;
      if (score < bestScore) {
        bestScore = score;
        bestX = x;
      }
    }

    if (bestX < 0) {
      out.add(blob);
      return;
    }

    final leftPart = _cropHorizontal(blob, 0, bestX);
    final rightPart = _cropHorizontal(blob, bestX + 1, blob.width);
    if (leftPart == null || rightPart == null) {
      out.add(blob);
      return;
    }

    _splitRecursive(leftPart, lineHeight, out, depth: depth + 1);
    _splitRecursive(rightPart, lineHeight, out, depth: depth + 1);
  }

  static int _localMax(Int32List arr, int from, int to) {
    var m = 0;
    for (var i = from; i <= to; i++) {
      if (arr[i] > m) m = arr[i];
    }
    return m;
  }

  static OcrGlyphBlob? _cropHorizontal(
    OcrGlyphBlob blob,
    int xStart,
    int xEnd,
  ) {
    if (xEnd <= xStart) return null;
    var minX = xEnd;
    var maxX = xStart - 1;
    var minY = blob.height;
    var maxY = -1;
    var count = 0;

    for (var y = 0; y < blob.height; y++) {
      final row = y * blob.width;
      for (var x = xStart; x < xEnd; x++) {
        if (blob.mask[row + x] != 0) {
          count++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (count < 2 || maxX < minX || maxY < minY) return null;

    final w = maxX - minX + 1;
    final h = maxY - minY + 1;
    final mask = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final srcRow = (minY + y) * blob.width + minX;
      mask.setRange(y * w, (y + 1) * w, blob.mask, srcRow);
    }

    return OcrGlyphBlob(
      left: blob.left + minX,
      top: blob.top + minY,
      width: w,
      height: h,
      pixelCount: count,
      mask: mask,
    );
  }
}
