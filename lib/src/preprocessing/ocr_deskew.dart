import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ocr_geometry.dart';

/// Estimates and corrects rotational document skew using horizontal
/// projection-profile variance maximization.
class OcrDeskew {
  const OcrDeskew._();

  /// Estimates the clockwise skew angle in degrees within
  /// `[-maxAngle, +maxAngle]` for a binary ink mask (`1` = ink, `0` = paper).
  ///
  /// Returns `0.0` when the image has insufficient foreground content or when
  /// rotation does not meaningfully sharpen horizontal text-line projections.
  static double estimateSkewAngle(
    Uint8List binary, {
    required int width,
    required int height,
    double maxAngle = 15.0,
  }) {
    if (width < 24 || height < 16 || maxAngle <= 0) return 0.0;

    // Collect downsampled ink coordinates for fast O(inkPixels) scoring.
    final stride = math.max(1, math.max(width, height) ~/ 360);
    final xs = <double>[];
    final ys = <double>[];
    final cx = width * 0.5;
    final cy = height * 0.5;

    for (var y = 0; y < height; y += stride) {
      final row = y * width;
      for (var x = 0; x < width; x += stride) {
        if (binary[row + x] != 0) {
          xs.add((x - cx) / stride);
          ys.add((y - cy) / stride);
        }
      }
    }

    if (xs.length < 25) return 0.0;

    final scaledH = (height / stride).ceil();
    final scaledW = (width / stride).ceil();
    final diag = math.sqrt(scaledW * scaledW + scaledH * scaledH).ceil() + 4;
    final bins = Int32List(diag);

    double scoreAngle(double deg) {
      bins.fillRange(0, bins.length, 0);
      final rad = deg * math.pi / 180.0;
      final sinA = math.sin(rad);
      final cosA = math.cos(rad);
      final offset = diag * 0.5;

      for (var i = 0; i < xs.length; i++) {
        // Rotating clockwise by -deg aligns text lines horizontally.
        final ry = (-xs[i] * sinA + ys[i] * cosA + offset).round();
        if (ry >= 0 && ry < diag) {
          bins[ry]++;
        }
      }

      // Maximize squared energy + gradient sharpness of horizontal projections.
      var energy = 0.0;
      var prev = 0;
      for (var i = 0; i < diag; i++) {
        final v = bins[i];
        final diff = v - prev;
        energy += (v * v) + (diff * diff) * 0.35;
        prev = v;
      }
      return energy;
    }

    final zeroScore = scoreAngle(0.0);
    if (zeroScore <= 0) return 0.0;

    // Coarse search (1.5 degree step).
    var bestAngle = 0.0;
    var bestScore = zeroScore;
    for (var a = -maxAngle; a <= maxAngle + 1e-6; a += 1.5) {
      final s = scoreAngle(a);
      if (s > bestScore) {
        bestScore = s;
        bestAngle = a;
      }
    }

    // Medium refinement (0.4 degree step).
    final medStart = math.max(-maxAngle, bestAngle - 1.5);
    final medEnd = math.min(maxAngle, bestAngle + 1.5);
    for (var a = medStart; a <= medEnd + 1e-6; a += 0.4) {
      final s = scoreAngle(a);
      if (s > bestScore) {
        bestScore = s;
        bestAngle = a;
      }
    }

    // Fine refinement (0.1 degree step).
    final fineStart = math.max(-maxAngle, bestAngle - 0.4);
    final fineEnd = math.min(maxAngle, bestAngle + 0.4);
    for (var a = fineStart; a <= fineEnd + 1e-6; a += 0.1) {
      final s = scoreAngle(a);
      if (s > bestScore) {
        bestScore = s;
        bestAngle = a;
      }
    }

    // Require both noticeable angle and clear improvement over 0 degrees to
    // avoid perturbing straight text lines.
    if (bestAngle.abs() < 0.45 || bestScore < zeroScore * 1.04) {
      return 0.0;
    }
    return bestAngle;
  }

  /// Maps a rectangle from the deskewed image coordinate space back into the
  /// original un-rotated image space.
  static OcrRect mapRectBackToSource(
    OcrRect rect, {
    required double appliedRotationDegrees,
    required double imageWidth,
    required double imageHeight,
  }) {
    if (appliedRotationDegrees.abs() < 1e-4) return rect;
    final rad = -appliedRotationDegrees * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final cx = imageWidth * 0.5;
    final cy = imageHeight * 0.5;

    final corners = <OcrPoint>[
      OcrPoint(rect.left, rect.top),
      OcrPoint(rect.right, rect.top),
      OcrPoint(rect.right, rect.bottom),
      OcrPoint(rect.left, rect.bottom),
    ];

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final c in corners) {
      final dx = c.x - cx;
      final dy = c.y - cy;
      final ox = dx * cosA - dy * sinA + cx;
      final oy = dx * sinA + dy * cosA + cy;
      if (ox < minX) minX = ox;
      if (oy < minY) minY = oy;
      if (ox > maxX) maxX = ox;
      if (oy > maxY) maxY = oy;
    }

    return OcrRect.fromLTRB(
      minX,
      minY,
      maxX,
      maxY,
    ).clampToBounds(imageWidth, imageHeight);
  }
}
