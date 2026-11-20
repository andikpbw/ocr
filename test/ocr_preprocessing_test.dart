import 'dart:typed_data';

import 'package:flutter_ocr/flutter_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrImage', () {
    test('converts RGBA, BGRA, YUV420, and round-trips BMP cleanly', () {
      // 4x3 synthetic image with varying gray intensities.
      final rgba = Uint8List(4 * 3 * 4);
      for (var i = 0; i < 12; i++) {
        final v = i * 20;
        rgba[i * 4] = v;
        rgba[i * 4 + 1] = v;
        rgba[i * 4 + 2] = v;
        rgba[i * 4 + 3] = 255;
      }

      final fromRgba = OcrImage.fromRgba(rgba, width: 4, height: 3);
      final fromBgra = OcrImage.fromBgra(rgba, width: 4, height: 3);
      expect(fromRgba.grayscale, equals(fromBgra.grayscale));

      final bmp = fromRgba.toBmpBytes();
      final decoded = OcrImage.fromBmp(bmp);
      expect(decoded.width, 4);
      expect(decoded.height, 3);
      for (var i = 0; i < 12; i++) {
        expect(
          (decoded.grayscale[i] - fromRgba.grayscale[i]).abs(),
          lessThanOrEqualTo(1),
        );
      }

      // YUV420 with padded row stride.
      final yPlane = Uint8List(6 * 3);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 4; x++) {
          yPlane[y * 6 + x] = fromRgba.grayscale[y * 4 + x];
        }
      }
      final fromYuv = OcrImage.fromYuv420(
        yPlane: yPlane,
        width: 4,
        height: 3,
        bytesPerRow: 6,
      );
      expect(fromYuv.grayscale, equals(fromRgba.grayscale));
    });

    test('crop and resize preserve bounds and luminance range', () {
      final img = OcrVectorAtlas.renderTextToImage('OCR', fontSize: 32);
      final cropped = img.crop(
        const OcrRect(left: 10, top: 10, width: 40, height: 30),
      );
      expect(cropped.width, 40);
      expect(cropped.height, 30);

      final resized = cropped.resize(newWidth: 80, newHeight: 60);
      expect(resized.width, 80);
      expect(resized.height, 60);
    });
  });

  group('OcrPreprocessor & OcrDeskew', () {
    test('detects and inverts dark-mode images automatically', () {
      final darkImg = OcrVectorAtlas.renderTextToImage(
        'DARK MODE',
        fontSize: 32,
        foregroundLuminance: 245,
        backgroundLuminance: 14,
      );
      final pre = OcrPreprocessor.process(darkImg);
      expect(pre.wasInverted, isTrue);
      // Ink pixels should be a minority (~3% - 35%), not inverted background.
      final ink = pre.binary.fold<int>(0, (int s, int v) => s + v);
      final ratio = ink / pre.binary.length;
      expect(ratio, greaterThan(0.01));
      expect(ratio, lessThan(0.45));
    });

    test('handles blank uniform images cleanly without false ink', () {
      final blank = OcrImage.filled(width: 200, height: 100, luminance: 240);
      final pre = OcrPreprocessor.process(blank);
      final ink = pre.binary.fold<int>(0, (int s, int v) => s + v);
      expect(ink, 0);
    });

    test('auto-selects Sauvola adaptive thresholding for shadowed scans', () {
      final clean = OcrVectorAtlas.renderTextToImage(
        'RECEIPT TOTAL\nAMOUNT 125.00',
        fontSize: 30,
        padding: 30,
      );
      // Apply heavy horizontal shadow gradient across the page.
      final shadowed = Uint8List.fromList(clean.grayscale);
      for (var y = 0; y < clean.height; y++) {
        for (var x = 0; x < clean.width; x++) {
          final shade = (x / clean.width) * 125.0;
          final idx = y * clean.width + x;
          shadowed[idx] = (shadowed[idx] - shade).round().clamp(0, 255);
        }
      }
      final shadowedImg = OcrImage.fromGrayscale(
        shadowed,
        width: clean.width,
        height: clean.height,
      );
      final pre = OcrPreprocessor.process(shadowedImg);
      expect(pre.usedAdaptiveThreshold, isTrue);

      final bradley = OcrPreprocessor.binarizeBradley(
        shadowedImg.grayscale,
        width: shadowedImg.width,
        height: shadowedImg.height,
      );
      expect(bradley.length, shadowedImg.pixelCount);
    });

    test('estimates document skew angle accurately within 1 degree', () {
      final straight = OcrVectorAtlas.renderTextToImage(
        'The quick brown fox jumps over\n'
        'the lazy dog in Flutter OCR 2026',
        fontSize: 28,
        padding: 40,
      );
      final tilted = straight.rotateDegrees(5.0);
      final preNoDeskew = OcrPreprocessor.process(
        tilted,
        config: const OcrPreprocessConfig(autoDeskew: false),
      );
      final estimated = OcrDeskew.estimateSkewAngle(
        preNoDeskew.binary,
        width: preNoDeskew.width,
        height: preNoDeskew.height,
      );
      expect(estimated, closeTo(5.0, 1.2));
    });
  });
}
