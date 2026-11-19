import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ocr_config.dart';
import '../models/ocr_geometry.dart';
import '../models/ocr_image.dart';
import 'ocr_deskew.dart';

/// Output of the image preprocessing stage ready for segmentation.
class PreprocessedImage {
  /// Creates a [PreprocessedImage].
  const PreprocessedImage({
    required this.binary,
    required this.grayscale,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.scaleX,
    required this.scaleY,
    required this.deskewAngle,
    required this.wasInverted,
    required this.usedAdaptiveThreshold,
    this.cropOffsetX = 0.0,
    this.cropOffsetY = 0.0,
  });

  /// Binary foreground mask (`1` = ink pixel, `0` = background pixel).
  final Uint8List binary;

  /// Normalized (polarity-corrected, contrast-enhanced) grayscale image.
  final Uint8List grayscale;

  /// Width of [binary] and [grayscale] in pixels.
  final int width;

  /// Height of [binary] and [grayscale] in pixels.
  final int height;

  /// Original source image width before ROI crop or scaling.
  final int sourceWidth;

  /// Original source image height before ROI crop or scaling.
  final int sourceHeight;

  /// Horizontal scale factor applied (`width / roiWidth`).
  final double scaleX;

  /// Vertical scale factor applied (`height / roiHeight`).
  final double scaleY;

  /// Rotation angle in degrees applied to straighten the document.
  final double deskewAngle;

  /// Whether dark-mode auto-inversion was applied.
  final bool wasInverted;

  /// Whether local adaptive thresholding was selected.
  final bool usedAdaptiveThreshold;

  /// Horizontal offset of the cropped region of interest in source pixels.
  final double cropOffsetX;

  /// Vertical offset of the cropped region of interest in source pixels.
  final double cropOffsetY;

  /// Maps a bounding rectangle from preprocessed space back into the original
  /// source image coordinate space.
  OcrRect mapRectToSource(OcrRect rect) {
    final unrotated = OcrDeskew.mapRectBackToSource(
      rect,
      appliedRotationDegrees: deskewAngle,
      imageWidth: width.toDouble(),
      imageHeight: height.toDouble(),
    );
    return OcrRect(
      left: unrotated.left / scaleX + cropOffsetX,
      top: unrotated.top / scaleY + cropOffsetY,
      width: unrotated.width / scaleX,
      height: unrotated.height / scaleY,
    ).clampToBounds(sourceWidth.toDouble(), sourceHeight.toDouble());
  }
}

/// Computer-vision preprocessing pipeline implementing contrast normalization,
/// dark-mode polarity detection, median denoising, Otsu / Sauvola / Bradley
/// binarization, despeckling, and automatic deskew correction.
class OcrPreprocessor {
  const OcrPreprocessor._();

  /// Executes the configured preprocessing pipeline on [source].
  static PreprocessedImage process(
    OcrImage source, {
    OcrPreprocessConfig config = const OcrPreprocessConfig(),
    OcrRect? regionOfInterest,
  }) {
    var working = source;
    var cropOffsetX = 0.0;
    var cropOffsetY = 0.0;

    if (regionOfInterest != null && !regionOfInterest.isEmpty) {
      cropOffsetX = regionOfInterest.left
          .floor()
          .clamp(0, source.width - 1)
          .toDouble();
      cropOffsetY = regionOfInterest.top
          .floor()
          .clamp(0, source.height - 1)
          .toDouble();
      working = source.crop(regionOfInterest);
    }

    final roiW = working.width;
    final roiH = working.height;

    // 1. Resolution normalization (downscale huge photos or upscale tiny crops).
    final maxDim = math.max(working.width, working.height);
    if (maxDim > config.maxImageDimension) {
      final ratio = config.maxImageDimension / maxDim;
      working = working.resize(
        newWidth: math.max(1, (working.width * ratio).round()),
        newHeight: math.max(1, (working.height * ratio).round()),
      );
    } else if (config.upscaleSmallImages &&
        working.height < config.minTargetHeight &&
        working.width >= 4 &&
        working.height >= 4) {
      final factor = (config.minTargetHeight / working.height).clamp(1.0, 3.0);
      working = working.resize(
        newWidth: (working.width * factor).round(),
        newHeight: (working.height * factor).round(),
      );
    }

    final w = working.width;
    final h = working.height;
    final scaleX = w / roiW;
    final scaleY = h / roiH;

    var gray = Uint8List.fromList(working.grayscale);

    // Early exit for blank / uniform images (prevents amplifying flat noise).
    var minLuma = 255;
    var maxLuma = 0;
    for (var i = 0; i < gray.length; i++) {
      final v = gray[i];
      if (v < minLuma) minLuma = v;
      if (v > maxLuma) maxLuma = v;
    }
    if (maxLuma - minLuma < 16) {
      return PreprocessedImage(
        binary: Uint8List(w * h),
        grayscale: gray,
        width: w,
        height: h,
        sourceWidth: source.width,
        sourceHeight: source.height,
        scaleX: scaleX,
        scaleY: scaleY,
        deskewAngle: 0.0,
        wasInverted: false,
        usedAdaptiveThreshold: false,
        cropOffsetX: cropOffsetX,
        cropOffsetY: cropOffsetY,
      );
    }

    // 2. Optional 3x3 median filter for salt-and-pepper noise reduction.
    if (config.denoise && w >= 3 && h >= 3) {
      gray = _medianFilter3x3(gray, w, h);
    }

    // 3. Automatic dark-mode polarity detection (light text on dark canvas).
    var wasInverted = false;
    if (config.autoInvertDarkMode && _isDarkModeBackground(gray, w, h)) {
      wasInverted = true;
      for (var i = 0; i < gray.length; i++) {
        gray[i] = 255 - gray[i];
      }
    }

    // 4. Optional percentile contrast stretch (2nd to 98th percentile).
    if (config.contrastStretch) {
      gray = _stretchContrast(gray);
    }

    // 5. Binarization.
    final binResult = _binarize(gray, w, h, config);
    var binary = binResult.binary;
    final usedAdaptive = binResult.usedAdaptive;

    // 6. Optional automatic deskewing (rotates grayscale for crisp edges).
    var deskewAngle = 0.0;
    if (config.autoDeskew && w >= 32 && h >= 20) {
      final skew = OcrDeskew.estimateSkewAngle(
        binary,
        width: w,
        height: h,
        maxAngle: config.maxDeskewAngle,
      );
      if (skew.abs() >= 0.45) {
        deskewAngle = -skew;
        final rotated = OcrImage.fromGrayscale(
          gray,
          width: w,
          height: h,
        ).rotateDegrees(deskewAngle);
        gray = Uint8List.fromList(rotated.grayscale);
        binary = _binarize(gray, w, h, config).binary;
      }
    }

    // 7. Optional isolated single-pixel despeckle.
    if (config.despeckle && w >= 3 && h >= 3) {
      binary = _despeckleIsolatedPixels(binary, w, h);
    }

    return PreprocessedImage(
      binary: binary,
      grayscale: gray,
      width: w,
      height: h,
      sourceWidth: source.width,
      sourceHeight: source.height,
      scaleX: scaleX,
      scaleY: scaleY,
      deskewAngle: deskewAngle,
      wasInverted: wasInverted,
      usedAdaptiveThreshold: usedAdaptive,
      cropOffsetX: cropOffsetX,
      cropOffsetY: cropOffsetY,
    );
  }

  /// Computes Otsu's optimal global threshold maximizing inter-class variance.
  static int computeOtsuThreshold(Uint8List gray) {
    final hist = Int32List(256);
    for (var i = 0; i < gray.length; i++) {
      hist[gray[i]]++;
    }
    final total = gray.length;
    var sumAll = 0.0;
    for (var t = 0; t < 256; t++) {
      sumAll += t * hist[t];
    }

    var sumBg = 0.0;
    var weightBg = 0;
    var maxVariance = -1.0;
    var threshold = 128;

    for (var t = 0; t < 256; t++) {
      weightBg += hist[t];
      if (weightBg == 0) continue;
      final weightFg = total - weightBg;
      if (weightFg == 0) break;

      sumBg += t * hist[t];
      final meanBg = sumBg / weightBg;
      final meanFg = (sumAll - sumBg) / weightFg;
      final diff = meanBg - meanFg;
      final variance = weightBg * weightFg * diff * diff;
      if (variance > maxVariance) {
        maxVariance = variance;
        threshold = t;
      }
    }
    return threshold;
  }

  /// Applies Sauvola local adaptive thresholding in `O(W * H)` time via
  /// summed-area tables (integral images of luminance and squared luminance).
  static Uint8List binarizeSauvola(
    Uint8List gray, {
    required int width,
    required int height,
    int windowSize = 25,
    double k = 0.28,
    double dynamicRange = 128.0,
  }) {
    final integral = Int64List((width + 1) * (height + 1));
    final integralSq = Int64List((width + 1) * (height + 1));
    final stride = width + 1;

    for (var y = 0; y < height; y++) {
      var rowSum = 0;
      var rowSqSum = 0;
      final srcRow = y * width;
      final dstRow = (y + 1) * stride;
      final prevRow = y * stride;
      for (var x = 0; x < width; x++) {
        final v = gray[srcRow + x];
        rowSum += v;
        rowSqSum += v * v;
        integral[dstRow + x + 1] = integral[prevRow + x + 1] + rowSum;
        integralSq[dstRow + x + 1] = integralSq[prevRow + x + 1] + rowSqSum;
      }
    }

    final half = windowSize ~/ 2;
    final out = Uint8List(width * height);

    for (var y = 0; y < height; y++) {
      final y0 = math.max(0, y - half);
      final y1 = math.min(height - 1, y + half);
      final row0 = y0 * stride;
      final row1 = (y1 + 1) * stride;
      final outRow = y * width;

      for (var x = 0; x < width; x++) {
        final x0 = math.max(0, x - half);
        final x1 = math.min(width - 1, x + half);
        final area = (x1 - x0 + 1) * (y1 - y0 + 1);

        final sum =
            integral[row1 + x1 + 1] -
            integral[row0 + x1 + 1] -
            integral[row1 + x0] +
            integral[row0 + x0];
        final sumSq =
            integralSq[row1 + x1 + 1] -
            integralSq[row0 + x1 + 1] -
            integralSq[row1 + x0] +
            integralSq[row0 + x0];

        final mean = sum / area;
        final variance = math.max(0.0, (sumSq / area) - (mean * mean));
        final stdDev = math.sqrt(variance);

        // Guard flat background patches against thresholding micro-noise.
        if (stdDev < 5.0) {
          out[outRow + x] = 0;
        } else {
          final threshold = mean * (1.0 + k * ((stdDev / dynamicRange) - 1.0));
          out[outRow + x] = gray[outRow + x] < threshold ? 1 : 0;
        }
      }
    }
    return out;
  }

  /// Applies Bradley-Roth local adaptive mean thresholding in `O(W * H)` time.
  static Uint8List binarizeBradley(
    Uint8List gray, {
    required int width,
    required int height,
    int windowSize = 25,
    double thresholdPercent = 12.0,
  }) {
    final integral = Int64List((width + 1) * (height + 1));
    final stride = width + 1;

    for (var y = 0; y < height; y++) {
      var rowSum = 0;
      final srcRow = y * width;
      final dstRow = (y + 1) * stride;
      final prevRow = y * stride;
      for (var x = 0; x < width; x++) {
        rowSum += gray[srcRow + x];
        integral[dstRow + x + 1] = integral[prevRow + x + 1] + rowSum;
      }
    }

    final half = windowSize ~/ 2;
    final factor = (100.0 - thresholdPercent) / 100.0;
    final out = Uint8List(width * height);

    for (var y = 0; y < height; y++) {
      final y0 = math.max(0, y - half);
      final y1 = math.min(height - 1, y + half);
      final row0 = y0 * stride;
      final row1 = (y1 + 1) * stride;
      final outRow = y * width;

      for (var x = 0; x < width; x++) {
        final x0 = math.max(0, x - half);
        final x1 = math.min(width - 1, x + half);
        final area = (x1 - x0 + 1) * (y1 - y0 + 1);
        final sum =
            integral[row1 + x1 + 1] -
            integral[row0 + x1 + 1] -
            integral[row1 + x0] +
            integral[row0 + x0];
        final mean = sum / area;
        out[outRow + x] = gray[outRow + x] < mean * factor ? 1 : 0;
      }
    }
    return out;
  }

  static _BinarizeResult _binarize(
    Uint8List gray,
    int w,
    int h,
    OcrPreprocessConfig config,
  ) {
    final method = config.binarization == OcrBinarizationMethod.auto
        ? (_hasUnevenIllumination(gray, w, h)
              ? OcrBinarizationMethod.sauvola
              : OcrBinarizationMethod.otsu)
        : config.binarization;

    switch (method) {
      case OcrBinarizationMethod.sauvola:
        return _BinarizeResult(
          binarizeSauvola(
            gray,
            width: w,
            height: h,
            windowSize: config.sauvolaWindowSize,
            k: config.sauvolaK,
          ),
          usedAdaptive: true,
        );
      case OcrBinarizationMethod.bradley:
        return _BinarizeResult(
          binarizeBradley(
            gray,
            width: w,
            height: h,
            windowSize: config.bradleyWindowSize,
            thresholdPercent: config.bradleyThresholdPercent,
          ),
          usedAdaptive: true,
        );
      case OcrBinarizationMethod.otsu:
      case OcrBinarizationMethod.auto:
        final threshold = computeOtsuThreshold(gray);
        final out = Uint8List(gray.length);
        for (var i = 0; i < gray.length; i++) {
          out[i] = gray[i] <= threshold ? 1 : 0;
        }
        return _BinarizeResult(out, usedAdaptive: false);
    }
  }

  static bool _isDarkModeBackground(Uint8List gray, int w, int h) {
    // Sample perimeter pixels + overall median to reliably detect dark canvases.
    final borderSamples = <int>[];
    final stepX = math.max(1, w ~/ 64);
    final stepY = math.max(1, h ~/ 64);

    for (var x = 0; x < w; x += stepX) {
      borderSamples.add(gray[x]);
      borderSamples.add(gray[(h - 1) * w + x]);
    }
    for (var y = 0; y < h; y += stepY) {
      borderSamples.add(gray[y * w]);
      borderSamples.add(gray[y * w + (w - 1)]);
    }
    borderSamples.sort();
    final borderMedian = borderSamples[borderSamples.length ~/ 2];
    if (borderMedian >= 120) return false;

    // Confirm that bright foreground pixels actually exist above border level.
    final hist = Int32List(256);
    for (var i = 0; i < gray.length; i++) {
      hist[gray[i]]++;
    }
    var brightCount = 0;
    final brightCutoff = math.min(240, borderMedian + 45);
    for (var v = brightCutoff; v < 256; v++) {
      brightCount += hist[v];
    }
    return brightCount > 0 && brightCount < (gray.length * 0.6);
  }

  static bool _hasUnevenIllumination(Uint8List gray, int w, int h) {
    if (w < 40 || h < 40) return false;
    const grid = 4;
    final tileW = w ~/ grid;
    final tileH = h ~/ grid;
    var minBg = 255.0;
    var maxBg = 0.0;

    for (var ty = 0; ty < grid; ty++) {
      for (var tx = 0; tx < grid; tx++) {
        // Estimate tile background as the 85th percentile luminance.
        final hist = Int32List(256);
        var count = 0;
        final yStart = ty * tileH;
        final yEnd = ty == grid - 1 ? h : (ty + 1) * tileH;
        final xStart = tx * tileW;
        final xEnd = tx == grid - 1 ? w : (tx + 1) * tileW;

        for (var y = yStart; y < yEnd; y += 2) {
          final row = y * w;
          for (var x = xStart; x < xEnd; x += 2) {
            hist[gray[row + x]]++;
            count++;
          }
        }
        final target = (count * 0.85).round();
        var acc = 0;
        var p85 = 255;
        for (var v = 0; v < 256; v++) {
          acc += hist[v];
          if (acc >= target) {
            p85 = v;
            break;
          }
        }
        if (p85 < minBg) minBg = p85.toDouble();
        if (p85 > maxBg) maxBg = p85.toDouble();
      }
    }
    return (maxBg - minBg) > 38.0;
  }

  static Uint8List _stretchContrast(Uint8List gray) {
    final hist = Int32List(256);
    for (var i = 0; i < gray.length; i++) {
      hist[gray[i]]++;
    }
    final total = gray.length;
    final lowTarget = (total * 0.01).round();
    final highTarget = (total * 0.99).round();

    var acc = 0;
    var pLow = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= lowTarget) {
        pLow = v;
        break;
      }
    }
    acc = 0;
    var pHigh = 255;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= highTarget) {
        pHigh = v;
        break;
      }
    }
    final span = pHigh - pLow;
    if (span < 20 || (pLow <= 5 && pHigh >= 250)) {
      return gray;
    }

    final lut = Uint8List(256);
    final invSpan = 255.0 / span;
    for (var v = 0; v < 256; v++) {
      lut[v] = ((v - pLow) * invSpan).round().clamp(0, 255);
    }
    final out = Uint8List(gray.length);
    for (var i = 0; i < gray.length; i++) {
      out[i] = lut[gray[i]];
    }
    return out;
  }

  static Uint8List _medianFilter3x3(Uint8List gray, int w, int h) {
    final out = Uint8List.fromList(gray);
    final win = Int32List(9);
    for (var y = 1; y < h - 1; y++) {
      final rowPrev = (y - 1) * w;
      final rowCurr = y * w;
      final rowNext = (y + 1) * w;
      for (var x = 1; x < w - 1; x++) {
        win[0] = gray[rowPrev + x - 1];
        win[1] = gray[rowPrev + x];
        win[2] = gray[rowPrev + x + 1];
        win[3] = gray[rowCurr + x - 1];
        win[4] = gray[rowCurr + x];
        win[5] = gray[rowCurr + x + 1];
        win[6] = gray[rowNext + x - 1];
        win[7] = gray[rowNext + x];
        win[8] = gray[rowNext + x + 1];
        // Insertion sort 9 elements in place.
        for (var i = 1; i < 9; i++) {
          final key = win[i];
          var j = i - 1;
          while (j >= 0 && win[j] > key) {
            win[j + 1] = win[j];
            j--;
          }
          win[j + 1] = key;
        }
        out[rowCurr + x] = win[4];
      }
    }
    return out;
  }

  static Uint8List _despeckleIsolatedPixels(Uint8List binary, int w, int h) {
    final out = Uint8List.fromList(binary);
    for (var y = 1; y < h - 1; y++) {
      final rowPrev = (y - 1) * w;
      final rowCurr = y * w;
      final rowNext = (y + 1) * w;
      for (var x = 1; x < w - 1; x++) {
        if (binary[rowCurr + x] == 0) continue;
        final neighbors =
            binary[rowPrev + x - 1] +
            binary[rowPrev + x] +
            binary[rowPrev + x + 1] +
            binary[rowCurr + x - 1] +
            binary[rowCurr + x + 1] +
            binary[rowNext + x - 1] +
            binary[rowNext + x] +
            binary[rowNext + x + 1];
        if (neighbors == 0) {
          out[rowCurr + x] = 0;
        }
      }
    }
    return out;
  }
}

class _BinarizeResult {
  const _BinarizeResult(this.binary, {required this.usedAdaptive});
  final Uint8List binary;
  final bool usedAdaptive;
}
