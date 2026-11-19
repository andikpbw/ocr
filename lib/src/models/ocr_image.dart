import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'ocr_geometry.dart';

/// Immutable grayscale image representation consumed by the OCR pipeline.
///
/// Supports zero-dependency creation from raw RGBA/BGRA/grayscale buffers,
/// camera YUV420 planes, uncompressed BMP bytes, Flutter [ui.Image] objects,
/// and any platform-encoded image bytes (PNG, JPEG, WebP, GIF, BMP).
@immutable
class OcrImage {
  /// Creates an [OcrImage] directly from an 8-bit [grayscale] luminance buffer.
  OcrImage.fromGrayscale(
    Uint8List grayscale, {
    required this.width,
    required this.height,
  }) : assert(width > 0, 'width must be positive'),
       assert(height > 0, 'height must be positive'),
       assert(
         grayscale.length == width * height,
         'grayscale buffer length (${grayscale.length}) must equal '
         'width * height (${width * height})',
       ),
       grayscale = Uint8List.fromList(grayscale);

  /// Creates an [OcrImage] from an RGBA8888 pixel buffer using Rec. 709
  /// perceptual luminance weights and white compositing for transparent pixels.
  factory OcrImage.fromRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'Image dimensions must be positive: ${width}x$height',
      );
    }
    final expected = width * height * 4;
    if (rgba.length < expected) {
      throw ArgumentError(
        'RGBA buffer length (${rgba.length}) is smaller than $expected.',
      );
    }
    final gray = Uint8List(width * height);
    for (var i = 0, p = 0; i < gray.length; i++, p += 4) {
      final r = rgba[p];
      final g = rgba[p + 1];
      final b = rgba[p + 2];
      final a = rgba[p + 3];
      var luma = (54 * r + 183 * g + 19 * b) >> 8;
      if (a < 255) {
        luma = (luma * a + 255 * (255 - a)) ~/ 255;
      }
      gray[i] = luma;
    }
    return OcrImage._internal(gray, width: width, height: height);
  }

  /// Creates an [OcrImage] from a BGRA8888 pixel buffer (standard on iOS and
  /// macOS camera streams).
  factory OcrImage.fromBgra(
    Uint8List bgra, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'Image dimensions must be positive: ${width}x$height',
      );
    }
    final expected = width * height * 4;
    if (bgra.length < expected) {
      throw ArgumentError(
        'BGRA buffer length (${bgra.length}) is smaller than $expected.',
      );
    }
    final gray = Uint8List(width * height);
    for (var i = 0, p = 0; i < gray.length; i++, p += 4) {
      final b = bgra[p];
      final g = bgra[p + 1];
      final r = bgra[p + 2];
      final a = bgra[p + 3];
      var luma = (54 * r + 183 * g + 19 * b) >> 8;
      if (a < 255) {
        luma = (luma * a + 255 * (255 - a)) ~/ 255;
      }
      gray[i] = luma;
    }
    return OcrImage._internal(gray, width: width, height: height);
  }

  /// Creates an [OcrImage] directly from the luminance (`Y`) plane of a
  /// YUV420 camera frame without color conversion overhead.
  factory OcrImage.fromYuv420({
    required Uint8List yPlane,
    required int width,
    required int height,
    int? bytesPerRow,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'Image dimensions must be positive: ${width}x$height',
      );
    }
    final stride = bytesPerRow ?? width;
    if (stride < width) {
      throw ArgumentError('bytesPerRow ($stride) must be >= width ($width).');
    }
    if (yPlane.length < stride * (height - 1) + width) {
      throw ArgumentError('Y plane buffer is smaller than image dimensions.');
    }
    if (stride == width && yPlane.length == width * height) {
      return OcrImage.fromGrayscale(yPlane, width: width, height: height);
    }
    final gray = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final srcOffset = y * stride;
      final dstOffset = y * width;
      gray.setRange(dstOffset, dstOffset + width, yPlane, srcOffset);
    }
    return OcrImage._internal(gray, width: width, height: height);
  }

  /// Decodes an uncompressed Windows BMP (8-bit, 24-bit, or 32-bit) image in
  /// pure Dart with zero external dependencies.
  factory OcrImage.fromBmp(Uint8List bytes) {
    if (bytes.length < 54 || bytes[0] != 0x42 || bytes[1] != 0x4D) {
      throw const FormatException('Invalid BMP header signature.');
    }
    final data = ByteData.sublistView(bytes);
    final pixelOffset = data.getUint32(10, Endian.little);
    final rawWidth = data.getInt32(18, Endian.little);
    final rawHeight = data.getInt32(22, Endian.little);
    final bitsPerPixel = data.getUint16(28, Endian.little);
    final compression = data.getUint32(30, Endian.little);

    if (compression != 0) {
      throw FormatException(
        'Unsupported BMP compression mode: $compression (expected uncompressed).',
      );
    }
    if (rawWidth <= 0 || rawHeight == 0) {
      throw FormatException('Invalid BMP dimensions: ${rawWidth}x$rawHeight.');
    }
    final width = rawWidth;
    final topDown = rawHeight < 0;
    final height = rawHeight.abs();
    final gray = Uint8List(width * height);

    if (bitsPerPixel == 24 || bitsPerPixel == 32) {
      final bytesPerPixel = bitsPerPixel ~/ 8;
      final rowStride = ((width * bytesPerPixel + 3) ~/ 4) * 4;
      for (var y = 0; y < height; y++) {
        final srcY = topDown ? y : (height - 1 - y);
        final rowStart = pixelOffset + srcY * rowStride;
        final dstRow = y * width;
        for (var x = 0; x < width; x++) {
          final p = rowStart + x * bytesPerPixel;
          final b = bytes[p];
          final g = bytes[p + 1];
          final r = bytes[p + 2];
          gray[dstRow + x] = (54 * r + 183 * g + 19 * b) >> 8;
        }
      }
    } else if (bitsPerPixel == 8) {
      final dibSize = data.getUint32(14, Endian.little);
      final paletteOffset = 14 + dibSize;
      final rowStride = ((width + 3) ~/ 4) * 4;
      for (var y = 0; y < height; y++) {
        final srcY = topDown ? y : (height - 1 - y);
        final rowStart = pixelOffset + srcY * rowStride;
        final dstRow = y * width;
        for (var x = 0; x < width; x++) {
          final idx = bytes[rowStart + x];
          final pal = paletteOffset + idx * 4;
          final b = bytes[pal];
          final g = bytes[pal + 1];
          final r = bytes[pal + 2];
          gray[dstRow + x] = (54 * r + 183 * g + 19 * b) >> 8;
        }
      }
    } else {
      throw FormatException('Unsupported BMP bit depth: $bitsPerPixel.');
    }

    return OcrImage._internal(gray, width: width, height: height);
  }

  /// Creates an [OcrImage] filled with a uniform luminance value (default
  /// white `255`). Useful for synthetic canvas rendering and unit tests.
  factory OcrImage.filled({
    required int width,
    required int height,
    int luminance = 255,
  }) {
    final gray = Uint8List(width * height)
      ..fillRange(0, width * height, luminance);
    return OcrImage._internal(gray, width: width, height: height);
  }

  const OcrImage._internal(
    this.grayscale, {
    required this.width,
    required this.height,
  });

  /// Decodes encoded image bytes (PNG, JPEG, WebP, GIF, or BMP) into an
  /// [OcrImage] using Flutter's built-in codec (with a pure-Dart BMP fast path).
  static Future<OcrImage> fromBytes(Uint8List bytes) async {
    if (bytes.length >= 54 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      try {
        return OcrImage.fromBmp(bytes);
      } on FormatException {
        // Fall through to Flutter's codec for compressed or exotic BMPs.
      }
    }
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        return await fromUiImage(frame.image);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// Converts a Flutter [ui.Image] into an [OcrImage].
  static Future<OcrImage> fromUiImage(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw StateError('Failed to extract RGBA pixel data from ui.Image.');
    }
    return OcrImage.fromRgba(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
      width: image.width,
      height: image.height,
    );
  }

  /// The image width in pixels.
  final int width;

  /// The image height in pixels.
  final int height;

  /// Row-major 8-bit grayscale luminance buffer (`0` = black, `255` = white).
  final Uint8List grayscale;

  /// Total pixel count (`width * height`).
  int get pixelCount => width * height;

  /// Returns the luminance value at ([x], [y]), clamped to valid bounds.
  int luminanceAt(int x, int y) {
    final cx = x.clamp(0, width - 1);
    final cy = y.clamp(0, height - 1);
    return grayscale[cy * width + cx];
  }

  /// Crops a rectangular [region] from this image, clamping to image bounds.
  OcrImage crop(OcrRect region) {
    final x0 = region.left.floor().clamp(0, width - 1);
    final y0 = region.top.floor().clamp(0, height - 1);
    final x1 = region.right.ceil().clamp(x0 + 1, width);
    final y1 = region.bottom.ceil().clamp(y0 + 1, height);
    final cw = x1 - x0;
    final ch = y1 - y0;
    final out = Uint8List(cw * ch);
    for (var y = 0; y < ch; y++) {
      final srcRow = (y0 + y) * width + x0;
      out.setRange(y * cw, (y + 1) * cw, grayscale, srcRow);
    }
    return OcrImage._internal(out, width: cw, height: ch);
  }

  /// Resizes this image to ([newWidth], [newHeight]) using bilinear
  /// interpolation.
  OcrImage resize({required int newWidth, required int newHeight}) {
    if (newWidth <= 0 || newHeight <= 0) {
      throw ArgumentError(
        'Target dimensions must be positive: ${newWidth}x$newHeight',
      );
    }
    if (newWidth == width && newHeight == height) return this;
    final out = Uint8List(newWidth * newHeight);
    final scaleX = width / newWidth;
    final scaleY = height / newHeight;

    for (var y = 0; y < newHeight; y++) {
      final srcY = (y + 0.5) * scaleY - 0.5;
      final y0 = srcY.floor().clamp(0, height - 1);
      final y1 = (y0 + 1).clamp(0, height - 1);
      final fy = (srcY - y0).clamp(0.0, 1.0);
      final row0 = y0 * width;
      final row1 = y1 * width;
      final outRow = y * newWidth;

      for (var x = 0; x < newWidth; x++) {
        final srcX = (x + 0.5) * scaleX - 0.5;
        final x0 = srcX.floor().clamp(0, width - 1);
        final x1 = (x0 + 1).clamp(0, width - 1);
        final fx = (srcX - x0).clamp(0.0, 1.0);

        final v00 = grayscale[row0 + x0];
        final v10 = grayscale[row0 + x1];
        final v01 = grayscale[row1 + x0];
        final v11 = grayscale[row1 + x1];

        final top = v00 + (v10 - v00) * fx;
        final bottom = v01 + (v11 - v01) * fx;
        out[outRow + x] = (top + (bottom - top) * fy).round().clamp(0, 255);
      }
    }
    return OcrImage._internal(out, width: newWidth, height: newHeight);
  }

  /// Rotates this image clockwise by [degrees] around its center using
  /// bilinear interpolation, filling out-of-bounds pixels with
  /// [backgroundLuminance].
  OcrImage rotateDegrees(double degrees, {int backgroundLuminance = 255}) {
    if (degrees.abs() < 1e-4) return this;
    final radians = degrees * math.pi / 180.0;
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    final cx = width * 0.5;
    final cy = height * 0.5;
    final out = Uint8List(width * height);

    for (var y = 0; y < height; y++) {
      final dy = y - cy;
      final rowOffset = y * width;
      for (var x = 0; x < width; x++) {
        final dx = x - cx;
        final srcX = dx * cosA + dy * sinA + cx;
        final srcY = -dx * sinA + dy * cosA + cy;
        if (srcX < 0 || srcX >= width - 1 || srcY < 0 || srcY >= height - 1) {
          out[rowOffset + x] = backgroundLuminance;
          continue;
        }
        final x0 = srcX.floor();
        final y0 = srcY.floor();
        final fx = srcX - x0;
        final fy = srcY - y0;
        final row0 = y0 * width;
        final row1 = (y0 + 1) * width;
        final top =
            grayscale[row0 + x0] +
            (grayscale[row0 + x0 + 1] - grayscale[row0 + x0]) * fx;
        final bottom =
            grayscale[row1 + x0] +
            (grayscale[row1 + x0 + 1] - grayscale[row1 + x0]) * fx;
        out[rowOffset + x] = (top + (bottom - top) * fy).round().clamp(0, 255);
      }
    }
    return OcrImage._internal(out, width: width, height: height);
  }

  /// Exports this grayscale image as an RGBA8888 pixel buffer.
  Uint8List toRgbaBytes() {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0, p = 0; i < grayscale.length; i++, p += 4) {
      final v = grayscale[i];
      rgba[p] = v;
      rgba[p + 1] = v;
      rgba[p + 2] = v;
      rgba[p + 3] = 255;
    }
    return rgba;
  }

  /// Encodes this grayscale image as an uncompressed 24-bit BMP file in pure
  /// Dart (compatible with Flutter's `Image.memory` and standard image viewers).
  Uint8List toBmpBytes() {
    final rowStride = ((width * 3 + 3) ~/ 4) * 4;
    final pixelDataSize = rowStride * height;
    final fileSize = 54 + pixelDataSize;
    final out = Uint8List(fileSize);
    final header = ByteData.sublistView(out);

    // File header (14 bytes).
    out[0] = 0x42; // 'B'
    out[1] = 0x4D; // 'M'
    header.setUint32(2, fileSize, Endian.little);
    header.setUint32(10, 54, Endian.little);

    // DIB BITMAPINFOHEADER (40 bytes).
    header.setUint32(14, 40, Endian.little);
    header.setInt32(18, width, Endian.little);
    header.setInt32(22, height, Endian.little);
    header.setUint16(26, 1, Endian.little);
    header.setUint16(28, 24, Endian.little);
    header.setUint32(34, pixelDataSize, Endian.little);

    for (var y = 0; y < height; y++) {
      final srcRow = (height - 1 - y) * width;
      final dstRow = 54 + y * rowStride;
      for (var x = 0; x < width; x++) {
        final v = grayscale[srcRow + x];
        final p = dstRow + x * 3;
        out[p] = v;
        out[p + 1] = v;
        out[p + 2] = v;
      }
    }
    return out;
  }
}
