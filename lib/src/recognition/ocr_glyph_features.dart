import 'dart:math' as math;
import 'dart:typed_data';

import '../segmentation/ocr_ccl.dart';

/// Compact multi-cue feature descriptor for a single character glyph.
///
/// Combines aspect-preserving Gaussian-smoothed normalized bitmaps (ZNCC +
/// cosine), 4x4 spatial zoning densities, 2x2x4 Sobel stroke orientation
/// histograms, topological interior hole count & vertical hole centroid,
/// horizontal/vertical stroke crossing profiles, and line-relative typographic
/// geometry.
class OcrGlyphFeature {
  /// Creates an [OcrGlyphFeature].
  const OcrGlyphFeature({
    required this.blurredZncc,
    required this.blurredCosine,
    required this.zoneGrid,
    required this.gradientHist,
    required this.holeCount,
    required this.holeCentroidY,
    required this.hCrossings,
    required this.vCrossings,
    required this.aspectRatio,
    required this.inkDensity,
    this.relHeight,
    this.relTop,
    this.relBottom,
  });

  /// Width of the normalized glyph feature grid.
  static const int gridWidth = 16;

  /// Height of the normalized glyph feature grid.
  static const int gridHeight = 20;

  /// Zero-mean L2-normalized Gaussian-smoothed 16x20 map (`320` floats).
  final Float32List blurredZncc;

  /// Positive L2-normalized Gaussian-smoothed 16x20 map (`320` floats).
  final Float32List blurredCosine;

  /// L2-normalized 4x4 spatial ink density vector (`16` floats).
  final Float32List zoneGrid;

  /// L2-normalized 2x2 quadrants x 4 stroke-orientation gradient histogram (`16`).
  final Float32List gradientHist;

  /// Number of enclosed interior white holes (`0`, `1`, or `2`).
  final int holeCount;

  /// Mean normalized Y coordinate (`[0.0, 1.0]`) of interior holes, or `-1.0`
  /// when [holeCount] is zero.
  final double holeCentroidY;

  /// Horizontal ink transition counts at 25%, 50%, and 75% glyph height.
  final Float32List hCrossings;

  /// Vertical ink transition counts at 25%, 50%, and 75% glyph width.
  final Float32List vCrossings;

  /// Width-to-height aspect ratio of the tight glyph bounding box.
  final double aspectRatio;

  /// Ink fill density (`inkPixels / bboxArea`).
  final double inkDensity;

  /// Glyph height normalized by the line's cap height (`1.0` = uppercase).
  final double? relHeight;

  /// Glyph top offset relative to line cap top, normalized by cap height.
  final double? relTop;

  /// Glyph bottom offset relative to line cap top, normalized by cap height
  /// (`1.0` = baseline, `~1.25` = descender).
  final double? relBottom;

  /// Extracts a complete [OcrGlyphFeature] from a binary glyph [mask] of size
  /// `[width] x [height]`.
  static OcrGlyphFeature extractFromMask(
    Uint8List mask, {
    required int width,
    required int height,
    double? relHeight,
    double? relTop,
    double? relBottom,
  }) {
    // 1. Aspect-preserving centered bilinear normalization into 16x20 grid
    // with 1-pixel border margin (inner 14x18 area).
    final norm = _normalizeAspectPreserving(mask, width, height);

    // 2. Separable 3x3 Gaussian smoothing for stroke-thickness & shift invariance.
    final smoothed = _gaussianBlur3x3(norm, gridWidth, gridHeight);

    // 3. Build ZNCC (zero-mean unit vector) and positive unit vector.
    final zncc = Float32List(smoothed.length);
    final cosine = Float32List(smoothed.length);
    var sum = 0.0;
    var sumSqPos = 0.0;
    for (var i = 0; i < smoothed.length; i++) {
      final v = smoothed[i];
      sum += v;
      sumSqPos += v * v;
    }
    final mean = sum / smoothed.length;
    var sumSqCentered = 0.0;
    for (var i = 0; i < smoothed.length; i++) {
      final d = smoothed[i] - mean;
      zncc[i] = d;
      sumSqCentered += d * d;
    }
    final invCentered = sumSqCentered > 1e-8
        ? 1.0 / math.sqrt(sumSqCentered)
        : 0.0;
    final invPos = sumSqPos > 1e-8 ? 1.0 / math.sqrt(sumSqPos) : 0.0;
    for (var i = 0; i < smoothed.length; i++) {
      zncc[i] *= invCentered;
      cosine[i] = smoothed[i] * invPos;
    }

    // 4. 4x4 spatial zoning density grid.
    final zones = _computeZoneGrid(norm);

    // 5. 2x2 x 4-orientation Sobel gradient histogram.
    final grads = _computeGradientHist(smoothed);

    // 6. Topological interior hole analysis on native resolution mask.
    final holes = _analyzeHoles(mask, width, height);

    // 7. Horizontal and vertical stroke crossings.
    final crossings = _computeCrossings(mask, width, height);

    // 8. Tight ink density & aspect ratio.
    var inkPixels = 0;
    for (var i = 0; i < mask.length; i++) {
      inkPixels += mask[i];
    }
    final area = math.max(1, width * height);

    return OcrGlyphFeature(
      blurredZncc: zncc,
      blurredCosine: cosine,
      zoneGrid: zones,
      gradientHist: grads,
      holeCount: holes.count,
      holeCentroidY: holes.centroidY,
      hCrossings: crossings.horizontal,
      vCrossings: crossings.vertical,
      aspectRatio: height > 0 ? width / height : 1.0,
      inkDensity: inkPixels / area,
      relHeight: relHeight,
      relTop: relTop,
      relBottom: relBottom,
    );
  }

  /// Convenience wrapper extracting features directly from an [OcrGlyphBlob]
  /// positioned within a text line defined by [capTop] and [capHeight].
  static OcrGlyphFeature extractFromBlob(
    OcrGlyphBlob blob, {
    double? capTop,
    double? capHeight,
  }) {
    double? relHeight;
    double? relTop;
    double? relBottom;
    if (capTop != null && capHeight != null && capHeight > 1.0) {
      relHeight = blob.height / capHeight;
      relTop = (blob.top - capTop) / capHeight;
      relBottom = (blob.bottom - capTop) / capHeight;
    }
    return extractFromMask(
      blob.mask,
      width: blob.width,
      height: blob.height,
      relHeight: relHeight,
      relTop: relTop,
      relBottom: relBottom,
    );
  }

  /// Returns a copy with updated line-relative typography measurements.
  OcrGlyphFeature withLineGeometry({
    required double relHeight,
    required double relTop,
    required double relBottom,
  }) {
    return OcrGlyphFeature(
      blurredZncc: blurredZncc,
      blurredCosine: blurredCosine,
      zoneGrid: zoneGrid,
      gradientHist: gradientHist,
      holeCount: holeCount,
      holeCentroidY: holeCentroidY,
      hCrossings: hCrossings,
      vCrossings: vCrossings,
      aspectRatio: aspectRatio,
      inkDensity: inkDensity,
      relHeight: relHeight,
      relTop: relTop,
      relBottom: relBottom,
    );
  }

  static Float32List _normalizeAspectPreserving(
    Uint8List mask,
    int srcW,
    int srcH,
  ) {
    final out = Float32List(gridWidth * gridHeight);
    if (srcW <= 0 || srcH <= 0) return out;

    const innerW = gridWidth - 2; // 14
    const innerH = gridHeight - 2; // 18
    final scale = math.min(innerW / srcW, innerH / srcH);
    final dstW = math.max(1.0, srcW * scale);
    final dstH = math.max(1.0, srcH * scale);
    final offsetX = (gridWidth - dstW) * 0.5;
    final offsetY = (gridHeight - dstH) * 0.5;

    // Area-averaged box sampling when downscaling, bilinear when upscaling.
    final invScale = 1.0 / scale;
    for (var y = 0; y < gridHeight; y++) {
      final sy0 = (y - offsetY) * invScale;
      final sy1 = (y + 1 - offsetY) * invScale;
      if (sy1 <= 0 || sy0 >= srcH) continue;
      final outRow = y * gridWidth;

      for (var x = 0; x < gridWidth; x++) {
        final sx0 = (x - offsetX) * invScale;
        final sx1 = (x + 1 - offsetX) * invScale;
        if (sx1 <= 0 || sx0 >= srcW) continue;

        if (invScale > 1.05) {
          // Box area average for sharp downscaling without losing thin strokes.
          final ix0 = math.max(0, sx0.floor());
          final ix1 = math.min(srcW - 1, sx1.ceil() - 1);
          final iy0 = math.max(0, sy0.floor());
          final iy1 = math.min(srcH - 1, sy1.ceil() - 1);
          var sum = 0.0;
          var weight = 0.0;
          for (var py = iy0; py <= iy1; py++) {
            final wy = math.min(sy1, py + 1.0) - math.max(sy0, py.toDouble());
            if (wy <= 0) continue;
            final srcRow = py * srcW;
            for (var px = ix0; px <= ix1; px++) {
              final wx = math.min(sx1, px + 1.0) - math.max(sx0, px.toDouble());
              if (wx <= 0) continue;
              final w = wx * wy;
              sum += mask[srcRow + px] * w;
              weight += w;
            }
          }
          out[outRow + x] = weight > 0 ? sum / weight : 0.0;
        } else {
          // Bilinear interpolation for smooth upscaling.
          final cx = (sx0 + sx1) * 0.5 - 0.5;
          final cy = (sy0 + sy1) * 0.5 - 0.5;
          final x0 = cx.floor().clamp(0, srcW - 1);
          final y0 = cy.floor().clamp(0, srcH - 1);
          final x1 = (x0 + 1).clamp(0, srcW - 1);
          final y1 = (y0 + 1).clamp(0, srcH - 1);
          final fx = (cx - x0).clamp(0.0, 1.0);
          final fy = (cy - y0).clamp(0.0, 1.0);

          final v00 = mask[y0 * srcW + x0].toDouble();
          final v10 = mask[y0 * srcW + x1].toDouble();
          final v01 = mask[y1 * srcW + x0].toDouble();
          final v11 = mask[y1 * srcW + x1].toDouble();
          final top = v00 + (v10 - v00) * fx;
          final bot = v01 + (v11 - v01) * fx;
          out[outRow + x] = top + (bot - top) * fy;
        }
      }
    }
    return out;
  }

  static Float32List _gaussianBlur3x3(Float32List src, int w, int h) {
    final tmp = Float32List(src.length);
    final dst = Float32List(src.length);

    // Horizontal pass [0.22, 0.56, 0.22].
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final left = x > 0 ? src[row + x - 1] : 0.0;
        final mid = src[row + x];
        final right = x + 1 < w ? src[row + x + 1] : 0.0;
        tmp[row + x] = left * 0.22 + mid * 0.56 + right * 0.22;
      }
    }

    // Vertical pass [0.22, 0.56, 0.22].
    for (var y = 0; y < h; y++) {
      final row = y * w;
      final rowUp = (y - 1) * w;
      final rowDn = (y + 1) * w;
      for (var x = 0; x < w; x++) {
        final up = y > 0 ? tmp[rowUp + x] : 0.0;
        final mid = tmp[row + x];
        final dn = y + 1 < h ? tmp[rowDn + x] : 0.0;
        dst[row + x] = up * 0.22 + mid * 0.56 + dn * 0.22;
      }
    }
    return dst;
  }

  static Float32List _computeZoneGrid(Float32List norm) {
    final zones = Float32List(16);
    const cellW = gridWidth ~/ 4; // 4
    const cellH = gridHeight ~/ 4; // 5
    var sumSq = 0.0;

    for (var zy = 0; zy < 4; zy++) {
      for (var zx = 0; zx < 4; zx++) {
        var acc = 0.0;
        for (var y = zy * cellH; y < (zy + 1) * cellH; y++) {
          final row = y * gridWidth;
          for (var x = zx * cellW; x < (zx + 1) * cellW; x++) {
            acc += norm[row + x];
          }
        }
        final avg = acc / (cellW * cellH);
        zones[zy * 4 + zx] = avg;
        sumSq += avg * avg;
      }
    }
    if (sumSq > 1e-8) {
      final inv = 1.0 / math.sqrt(sumSq);
      for (var i = 0; i < 16; i++) {
        zones[i] *= inv;
      }
    }
    return zones;
  }

  static Float32List _computeGradientHist(Float32List smoothed) {
    final hist = Float32List(16);
    const halfW = gridWidth ~/ 2;
    const halfH = gridHeight ~/ 2;

    for (var y = 1; y < gridHeight - 1; y++) {
      final rUp = (y - 1) * gridWidth;
      final rMid = y * gridWidth;
      final rDn = (y + 1) * gridWidth;
      final qy = y < halfH ? 0 : 1;

      for (var x = 1; x < gridWidth - 1; x++) {
        final gx =
            (smoothed[rUp + x + 1] +
                2 * smoothed[rMid + x + 1] +
                smoothed[rDn + x + 1]) -
            (smoothed[rUp + x - 1] +
                2 * smoothed[rMid + x - 1] +
                smoothed[rDn + x - 1]);
        final gy =
            (smoothed[rDn + x - 1] +
                2 * smoothed[rDn + x] +
                smoothed[rDn + x + 1]) -
            (smoothed[rUp + x - 1] +
                2 * smoothed[rUp + x] +
                smoothed[rUp + x + 1]);

        final mag = math.sqrt(gx * gx + gy * gy);
        if (mag < 1e-4) continue;

        // Quantize unsigned orientation [0, pi) into 4 directional bins.
        var angle = math.atan2(gy, gx);
        if (angle < 0) angle += math.pi;
        final bin = ((angle * 4.0 / math.pi).floor()) & 3;
        final qx = x < halfW ? 0 : 1;
        hist[(qy * 2 + qx) * 4 + bin] += mag;
      }
    }

    var sumSq = 0.0;
    for (var i = 0; i < 16; i++) {
      sumSq += hist[i] * hist[i];
    }
    if (sumSq > 1e-8) {
      final inv = 1.0 / math.sqrt(sumSq);
      for (var i = 0; i < 16; i++) {
        hist[i] *= inv;
      }
    }
    return hist;
  }

  static _HoleStats _analyzeHoles(Uint8List mask, int w, int h) {
    if (w < 3 || h < 3) return const _HoleStats(0, -1.0);
    // Add 1-pixel background border so exterior white pixels connect cleanly.
    final pw = w + 2;
    final ph = h + 2;
    final visited = Uint8List(pw * ph);

    bool isInk(int px, int py) {
      if (px == 0 || py == 0 || px == pw - 1 || py == ph - 1) return false;
      return mask[(py - 1) * w + (px - 1)] != 0;
    }

    final queue = Int32List(pw * ph);

    int floodFill(
      int startX,
      int startY, {
      required bool trackY,
      required List<double> yAcc,
    }) {
      var head = 0;
      var tail = 0;
      final startIdx = startY * pw + startX;
      visited[startIdx] = 1;
      queue[tail++] = startIdx;
      var count = 0;
      var ySum = 0.0;

      while (head < tail) {
        final idx = queue[head++];
        final x = idx % pw;
        final y = idx ~/ pw;
        count++;
        if (trackY) ySum += (y - 1);

        // 4-connectivity for background ensures closed 8-connected ink loops
        // stay topologically sealed.
        if (x > 0) {
          final n = idx - 1;
          if (visited[n] == 0 && !isInk(x - 1, y)) {
            visited[n] = 1;
            queue[tail++] = n;
          }
        }
        if (x + 1 < pw) {
          final n = idx + 1;
          if (visited[n] == 0 && !isInk(x + 1, y)) {
            visited[n] = 1;
            queue[tail++] = n;
          }
        }
        if (y > 0) {
          final n = idx - pw;
          if (visited[n] == 0 && !isInk(x, y - 1)) {
            visited[n] = 1;
            queue[tail++] = n;
          }
        }
        if (y + 1 < ph) {
          final n = idx + pw;
          if (visited[n] == 0 && !isInk(x, y + 1)) {
            visited[n] = 1;
            queue[tail++] = n;
          }
        }
      }
      if (trackY && count > 0) {
        yAcc.add(ySum / count);
      }
      return count;
    }

    // Mark exterior background starting at padded corner (0, 0).
    floodFill(0, 0, trackY: false, yAcc: const <double>[]);

    // Any remaining unvisited background component is an enclosed hole.
    final minHoleArea = math.max(2, (w * h * 0.015).round());
    var holeCount = 0;
    var weightedY = 0.0;
    var totalHoleArea = 0;

    for (var py = 1; py < ph - 1; py++) {
      for (var px = 1; px < pw - 1; px++) {
        final idx = py * pw + px;
        if (visited[idx] != 0 || isInk(px, py)) continue;
        final yHolder = <double>[];
        final area = floodFill(px, py, trackY: true, yAcc: yHolder);
        if (area >= minHoleArea) {
          holeCount++;
          weightedY += yHolder.first * area;
          totalHoleArea += area;
        }
      }
    }

    if (holeCount == 0 || totalHoleArea == 0) {
      return const _HoleStats(0, -1.0);
    }
    final normCentroidY = (weightedY / totalHoleArea) / math.max(1, h - 1);
    return _HoleStats(math.min(holeCount, 2), normCentroidY.clamp(0.0, 1.0));
  }

  static _CrossingStats _computeCrossings(Uint8List mask, int w, int h) {
    final hCross = Float32List(3);
    final vCross = Float32List(3);
    const fracs = <double>[0.25, 0.50, 0.75];

    for (var i = 0; i < 3; i++) {
      final y = ((h - 1) * fracs[i]).round().clamp(0, h - 1);
      final row = y * w;
      var transitions = 0;
      var prev = 0;
      for (var x = 0; x < w; x++) {
        final cur = mask[row + x];
        if (cur == 1 && prev == 0) transitions++;
        prev = cur;
      }
      hCross[i] = transitions.toDouble();

      final x = ((w - 1) * fracs[i]).round().clamp(0, w - 1);
      transitions = 0;
      prev = 0;
      for (var py = 0; py < h; py++) {
        final cur = mask[py * w + x];
        if (cur == 1 && prev == 0) transitions++;
        prev = cur;
      }
      vCross[i] = transitions.toDouble();
    }

    return _CrossingStats(hCross, vCross);
  }
}

class _HoleStats {
  const _HoleStats(this.count, this.centroidY);
  final int count;
  final double centroidY;
}

class _CrossingStats {
  const _CrossingStats(this.horizontal, this.vertical);
  final Float32List horizontal;
  final Float32List vertical;
}
