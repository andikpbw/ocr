import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/ocr_config.dart';
import 'ocr_glyph_features.dart';
import 'ocr_vector_atlas.dart';

/// Dynamically rasterizes platform and custom Flutter fonts via `dart:ui`'s
/// [ui.ParagraphBuilder] to add exact font prototypes to the classifier bank.
///
/// Automatically detects headless test environments using the synthetic Ahem
/// block font and skips calibration safely so unit tests stay deterministic.
class OcrFontCalibrator {
  OcrFontCalibrator._();

  static const String _asciiChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      'abcdefghijklmnopqrstuvwxyz'
      '0123456789'
      '.,:;!?-_+=/\\|()[]{}<>\'"`@#\$%^&*~';

  static const String _extendedLatinExtra =
      'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ'
      'àáâãäåæçèéêëìíîïñòóôõöøùúûüýß€£¥';

  static final Map<String, List<OcrGlyphPrototype>> _cache =
      <String, List<OcrGlyphPrototype>>{};

  /// Clears all cached platform font prototypes.
  static void clearCache() => _cache.clear();

  /// Calibrates prototypes for the requested [fontFamilies] and [script].
  ///
  /// When [fontFamilies] is empty, calibrates against the platform default
  /// sans-serif, serif, and monospace families (both regular and bold weights).
  static Future<List<OcrGlyphPrototype>> calibrate({
    List<String> fontFamilies = const <String>[],
    OcrScript script = OcrScript.ascii,
  }) async {
    final families = fontFamilies.isNotEmpty
        ? fontFamilies
        : const <String>['sans-serif', 'serif', 'monospace'];
    final charset = script == OcrScript.extendedLatin
        ? '$_asciiChars$_extendedLatinExtra'
        : _asciiChars;

    final key = '${families.join("|")}:${script.name}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final prototypes = <OcrGlyphPrototype>[];
    for (final family in families) {
      for (final weight in const <ui.FontWeight>[
        ui.FontWeight.w400,
        ui.FontWeight.w600,
      ]) {
        try {
          final familyProtos = await _rasterizeFontSheet(
            family: family,
            weight: weight,
            charset: charset,
          );
          prototypes.addAll(familyProtos);
        } catch (_) {
          // Graceful fallback if platform font rasterization is unavailable.
        }
      }
    }

    _cache[key] = prototypes;
    return prototypes;
  }

  static Future<List<OcrGlyphPrototype>> _rasterizeFontSheet({
    required String family,
    required ui.FontWeight weight,
    required String charset,
  }) async {
    const fontSize = 40.0;
    const cellW = 64;
    const cellH = 68;
    const cols = 16;

    // Prepend reference 'H', 'O', 'I' probes at indices 0, 1, 2 to measure
    // exact font cap metrics and reject Ahem solid-block fallback fonts.
    final chars = <String>['H', 'O', 'I', ...charset.split('')];
    final rows = (chars.length + cols - 1) ~/ cols;
    const sheetW = cols * cellW;
    final sheetH = rows * cellH;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, sheetW.toDouble(), sheetH.toDouble()),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, sheetW.toDouble(), sheetH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    for (var i = 0; i < chars.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final pb =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
            ..pushStyle(
              ui.TextStyle(
                color: const ui.Color(0xFF000000),
                fontSize: fontSize,
                fontFamily: family == 'sans-serif' ? null : family,
                fontWeight: weight,
              ),
            )
            ..addText(chars[i]);
      final paragraph = pb.build()
        ..layout(const ui.ParagraphConstraints(width: cellW - 4.0));
      canvas.drawParagraph(
        paragraph,
        ui.Offset(col * cellW + 2.0, row * cellH + 8.0),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(sheetW, sheetH);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    image.dispose();

    if (byteData == null) return const <OcrGlyphPrototype>[];
    final rgba = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    _CellMask? extractCell(int index) {
      final col = index % cols;
      final row = index ~/ cols;
      final x0 = col * cellW;
      final y0 = row * cellH;

      var minX = cellW;
      var maxX = -1;
      var minY = cellH;
      var maxY = -1;

      for (var y = 0; y < cellH; y++) {
        final imgRow = (y0 + y) * sheetW;
        for (var x = 0; x < cellW; x++) {
          final p = (imgRow + x0 + x) * 4;
          final luma =
              (54 * rgba[p] + 183 * rgba[p + 1] + 19 * rgba[p + 2]) >> 8;
          if (luma < 150) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      if (maxX < minX || maxY < minY) return null;

      final w = maxX - minX + 1;
      final h = maxY - minY + 1;
      final mask = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        final imgRow = (y0 + minY + y) * sheetW;
        final dstRow = y * w;
        for (var x = 0; x < w; x++) {
          final p = (imgRow + x0 + minX + x) * 4;
          final luma =
              (54 * rgba[p] + 183 * rgba[p + 1] + 19 * rgba[p + 2]) >> 8;
          mask[dstRow + x] = luma < 150 ? 1 : 0;
        }
      }
      return _CellMask(mask: mask, width: w, height: h, minY: minY, maxY: maxY);
    }

    // Validate probes H, O, I to reject Ahem / missing fonts.
    final probeH = extractCell(0);
    final probeO = extractCell(1);
    final probeI = extractCell(2);
    if (probeH == null || probeO == null || probeI == null) {
      return const <OcrGlyphPrototype>[];
    }

    final featO = OcrGlyphFeature.extractFromMask(
      probeO.mask,
      width: probeO.width,
      height: probeO.height,
    );
    final featI = OcrGlyphFeature.extractFromMask(
      probeI.mask,
      width: probeI.width,
      height: probeI.height,
    );

    // Real fonts render 'O' with an interior hole and 'I' narrower than square.
    if (featO.holeCount < 1 || featI.aspectRatio > 0.78) {
      return const <OcrGlyphPrototype>[];
    }

    final capTop = probeH.minY.toDouble();
    final capH = math.max(8.0, (probeH.maxY - probeH.minY + 1).toDouble());
    final weightTag = weight == ui.FontWeight.w600 ? 'bold' : 'regular';
    final styleTag = 'font_${family}_$weightTag';

    final out = <OcrGlyphPrototype>[];
    for (var i = 3; i < chars.length; i++) {
      final cell = extractCell(i);
      if (cell == null) continue;
      final feature = OcrGlyphFeature.extractFromMask(
        cell.mask,
        width: cell.width,
        height: cell.height,
        relHeight: cell.height / capH,
        relTop: (cell.minY - capTop) / capH,
        relBottom: (cell.maxY + 1 - capTop) / capH,
      );
      out.add(
        OcrGlyphPrototype(
          character: chars[i],
          feature: feature,
          style: styleTag,
          priorityBias: 0.014,
        ),
      );
    }
    return out;
  }
}

class _CellMask {
  const _CellMask({
    required this.mask,
    required this.width,
    required this.height,
    required this.minY,
    required this.maxY,
  });

  final Uint8List mask;
  final int width;
  final int height;
  final int minY;
  final int maxY;
}
