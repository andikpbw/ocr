import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ocr_image.dart';
import 'ocr_glyph_features.dart';

/// A labeled reference glyph prototype stored in the classifier bank.
class OcrGlyphPrototype {
  /// Creates an [OcrGlyphPrototype] for [character] with extracted [feature].
  const OcrGlyphPrototype({
    required this.character,
    required this.feature,
    required this.style,
    this.priorityBias = 0.0,
  });

  /// Target character symbol represented by this prototype.
  final String character;

  /// Extracted multi-cue visual & typographic feature descriptor.
  final OcrGlyphFeature feature;

  /// Style tag (e.g. `'sans'`, `'bold'`, `'serif'`, or calibrated font family).
  final String style;

  /// Small tie-breaking prior bonus for standard canonical glyphs.
  final double priorityBias;
}

/// Procedural sub-pixel analytical vector glyph atlas generating crisp,
/// multi-weight and multi-style prototypes for all printable ASCII characters
/// with zero binary assets or external dependencies.
class OcrVectorAtlas {
  OcrVectorAtlas._();

  static List<OcrGlyphPrototype>? _cached;

  /// Returns the cached universal multi-style prototype bank covering `A-Z`,
  /// `a-z`, `0-9`, and all standard printable ASCII punctuation.
  static List<OcrGlyphPrototype> get prototypes =>
      _cached ??= _buildPrototypes();

  /// Renders a string [text] onto a clean synthetic [OcrImage] using this
  /// atlas's analytical anti-aliased stroke renderer. Useful for calibration,
  /// visualization, and deterministic headless testing.
  static OcrImage renderTextToImage(
    String text, {
    double fontSize = 36.0,
    double strokeWeight = 0.105,
    int padding = 24,
    int foregroundLuminance = 15,
    int backgroundLuminance = 250,
    double lineSpacing = 1.55,
    double letterSpacing = 0.18,
  }) {
    final lines = text.split('\n');
    final capH = fontSize;
    final lineStep = (capH * lineSpacing).round();
    final strokePx = math.max(1.6, capH * strokeWeight);

    // Measure required canvas dimensions.
    var maxLineW = 0.0;
    for (final line in lines) {
      var x = 0.0;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == ' ') {
          x += capH * 0.46;
        } else {
          final spec = _glyphSpecs[ch];
          final w = (spec?.widthRatio ?? 0.56) * capH;
          x += w + capH * letterSpacing;
        }
      }
      if (x > maxLineW) maxLineW = x;
    }

    final imgW = math.max(32, maxLineW.ceil() + padding * 2);
    final imgH = math.max(
      32,
      (lines.length - 1) * lineStep + (capH * 1.4).ceil() + padding * 2,
    );

    final coverage = Float32List(imgW * imgH);
    final canvas = _SubpixelCanvas(coverage, imgW, imgH);

    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      var cursorX = padding.toDouble();
      final capTop = padding + li * lineStep.toDouble();
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == ' ') {
          cursorX += capH * 0.46;
          continue;
        }
        final spec = _glyphSpecs[ch];
        if (spec == null) {
          cursorX += capH * 0.46;
          continue;
        }
        final glyphW = spec.widthRatio * capH;
        spec.draw(canvas, cursorX, capTop, glyphW, capH, strokePx);
        cursorX += glyphW + capH * letterSpacing;
      }
    }

    final gray = Uint8List(imgW * imgH);
    final diff = foregroundLuminance - backgroundLuminance;
    for (var i = 0; i < gray.length; i++) {
      final alpha = coverage[i].clamp(0.0, 1.0);
      gray[i] = (backgroundLuminance + diff * alpha).round().clamp(0, 255);
    }

    return OcrImage.fromGrayscale(gray, width: imgW, height: imgH);
  }

  static List<OcrGlyphPrototype> _buildPrototypes() {
    final result = <OcrGlyphPrototype>[];

    // Primary stroke weights spanning light UI, regular sans, and bold headers.
    const weights = <(String, double, double)>[
      ('sans_regular', 0.105, 0.008),
      ('sans_bold', 0.155, 0.004),
      ('sans_light', 0.072, 0.002),
    ];

    for (final (style, weight, bias) in weights) {
      final refMetrics = _measureCapReference(weight);
      for (final entry in _glyphSpecs.entries) {
        final proto = _rasterizePrototype(
          entry.key,
          entry.value,
          style: style,
          strokeWeight: weight,
          refCapTop: refMetrics.$1,
          refCapHeight: refMetrics.$2,
          priorityBias: bias,
        );
        if (proto != null) result.add(proto);
      }
    }

    // Alternate typographic forms across serif, geometric, and monospace fonts.
    final regRef = _measureCapReference(0.105);
    final boldRef = _measureCapReference(0.150);
    for (final entry in _variantSpecs.entries) {
      final ch = entry.key;
      for (final variant in entry.value) {
        final protoReg = _rasterizePrototype(
          ch,
          variant.spec,
          style: variant.style,
          strokeWeight: 0.105,
          refCapTop: regRef.$1,
          refCapHeight: regRef.$2,
          priorityBias: 0.005,
        );
        if (protoReg != null) result.add(protoReg);
        final protoBold = _rasterizePrototype(
          ch,
          variant.spec,
          style: '${variant.style}_bold',
          strokeWeight: 0.150,
          refCapTop: boldRef.$1,
          refCapHeight: boldRef.$2,
          priorityBias: 0.003,
        );
        if (protoBold != null) result.add(protoBold);
      }
    }

    return result;
  }

  static (double, double) _measureCapReference(double strokeWeight) {
    const canvasW = 64;
    const canvasH = 72;
    const capTop = 12.0;
    const capH = 38.0;
    final specH = _glyphSpecs['H']!;
    final glyphW = specH.widthRatio * capH;
    final originX = (canvasW - glyphW) * 0.5;
    final coverage = Float32List(canvasW * canvasH);
    specH.draw(
      _SubpixelCanvas(coverage, canvasW, canvasH),
      originX,
      capTop,
      glyphW,
      capH,
      capH * strokeWeight,
    );
    var minY = canvasH;
    var maxY = -1;
    for (var y = 0; y < canvasH; y++) {
      final row = y * canvasW;
      for (var x = 0; x < canvasW; x++) {
        if (coverage[row + x] >= 0.42) {
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxY < minY) return (capTop, capH);
    return (minY.toDouble(), (maxY - minY + 1).toDouble());
  }

  static OcrGlyphPrototype? _rasterizePrototype(
    String character,
    _GlyphSpec spec, {
    required String style,
    required double strokeWeight,
    required double refCapTop,
    required double refCapHeight,
    double priorityBias = 0.0,
  }) {
    const canvasW = 64;
    const canvasH = 72;
    const capTop = 12.0;
    const capH = 38.0;
    final glyphW = spec.widthRatio * capH;
    final originX = (canvasW - glyphW) * 0.5;
    final strokePx = capH * strokeWeight;

    final coverage = Float32List(canvasW * canvasH);
    final canvas = _SubpixelCanvas(coverage, canvasW, canvasH);
    spec.draw(canvas, originX, capTop, glyphW, capH, strokePx);

    // Threshold into tight binary mask.
    var minX = canvasW;
    var maxX = -1;
    var minY = canvasH;
    var maxY = -1;
    for (var y = 0; y < canvasH; y++) {
      final row = y * canvasW;
      for (var x = 0; x < canvasW; x++) {
        if (coverage[row + x] >= 0.42) {
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
      final srcRow = (minY + y) * canvasW + minX;
      final dstRow = y * w;
      for (var x = 0; x < w; x++) {
        mask[dstRow + x] = coverage[srcRow + x] >= 0.42 ? 1 : 0;
      }
    }

    final feature = OcrGlyphFeature.extractFromMask(
      mask,
      width: w,
      height: h,
      relHeight: h / refCapHeight,
      relTop: (minY - refCapTop) / refCapHeight,
      relBottom: (maxY + 1 - refCapTop) / refCapHeight,
    );

    return OcrGlyphPrototype(
      character: character,
      feature: feature,
      style: style,
      priorityBias: priorityBias,
    );
  }

  // -------------------------------------------------------------------------
  // Typographic coordinate system:
  //   u in [0.0 .. 1.0] spans [x0 .. x0 + w]
  //   v = 0.00 -> capTop / ascender
  //   v = 0.28 -> x-height top (lowercase body)
  //   v = 1.00 -> baseline
  //   v = 1.26 -> descender bottom
  // -------------------------------------------------------------------------

  static final Map<String, _GlyphSpec> _glyphSpecs = <String, _GlyphSpec>{
    // ========================== UPPERCASE A-Z ==============================
    'A': _GlyphSpec(0.68, (c, x, y, w, h, s) {
      c.seg(x + w * 0.50, y, x, y + h, s);
      c.seg(x + w * 0.50, y, x + w, y + h, s);
      c.seg(x + w * 0.18, y + h * 0.67, x + w * 0.82, y + h * 0.67, s);
    }),
    'B': _GlyphSpec(0.64, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x, y, x + w * 0.56, y, s);
      c.arc(
        x + w * 0.56,
        y + h * 0.24,
        w * 0.36,
        h * 0.24,
        -math.pi / 2,
        math.pi / 2,
        s,
      );
      c.seg(x, y + h * 0.48, x + w * 0.60, y + h * 0.48, s);
      c.arc(
        x + w * 0.60,
        y + h * 0.74,
        w * 0.40,
        h * 0.26,
        -math.pi / 2,
        math.pi / 2,
        s,
      );
      c.seg(x, y + h, x + w * 0.60, y + h, s);
    }),
    'C': _GlyphSpec(0.66, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.54,
        y + h * 0.50,
        w * 0.50,
        h * 0.50,
        0.52,
        math.pi * 2 - 0.52,
        s,
      );
    }),
    'D': _GlyphSpec(0.68, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x, y, x + w * 0.46, y, s);
      c.seg(x, y + h, x + w * 0.46, y + h, s);
      c.arc(
        x + w * 0.46,
        y + h * 0.50,
        w * 0.54,
        h * 0.50,
        -math.pi / 2,
        math.pi / 2,
        s,
      );
    }),
    'E': _GlyphSpec(0.58, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x, y, x + w, y, s);
      c.seg(x, y + h * 0.49, x + w * 0.86, y + h * 0.49, s);
      c.seg(x, y + h, x + w, y + h, s);
    }),
    'F': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x, y, x + w, y, s);
      c.seg(x, y + h * 0.49, x + w * 0.84, y + h * 0.49, s);
    }),
    'G': _GlyphSpec(0.70, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.52,
        y + h * 0.50,
        w * 0.50,
        h * 0.50,
        0.15,
        math.pi * 2 - 0.52,
        s,
      );
      c.seg(x + w * 0.54, y + h * 0.54, x + w, y + h * 0.54, s);
      c.seg(x + w, y + h * 0.54, x + w, y + h * 0.96, s);
    }),
    'H': _GlyphSpec(0.66, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x + w, y, x + w, y + h, s);
      c.seg(x, y + h * 0.49, x + w, y + h * 0.49, s);
    }),
    'I': _GlyphSpec(0.16, (c, x, y, w, h, s) {
      c.seg(x + w * 0.5, y, x + w * 0.5, y + h, s);
    }),
    'J': _GlyphSpec(0.50, (c, x, y, w, h, s) {
      c.seg(x + w * 0.82, y, x + w * 0.82, y + h * 0.72, s);
      c.arc(
        x + w * 0.42,
        y + h * 0.72,
        w * 0.40,
        h * 0.28,
        0.0,
        math.pi * 0.92,
        s,
      );
    }),
    'K': _GlyphSpec(0.64, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x + w, y, x + w * 0.06, y + h * 0.56, s);
      c.seg(x + w * 0.34, y + h * 0.40, x + w, y + h, s);
    }),
    'L': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x, y + h, x + w, y + h, s);
    }),
    'M': _GlyphSpec(0.82, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x, y, x + w * 0.50, y + h * 0.82, s);
      c.seg(x + w * 0.50, y + h * 0.82, x + w, y, s);
      c.seg(x + w, y, x + w, y + h, s);
    }),
    'N': _GlyphSpec(0.68, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x, y, x + w, y + h, s);
      c.seg(x + w, y, x + w, y + h, s);
    }),
    'O': _GlyphSpec(0.72, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.50,
        w * 0.50,
        h * 0.50,
        0.0,
        math.pi * 2,
        s,
      );
    }),
    'P': _GlyphSpec(0.62, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x, y, x + w * 0.56, y, s);
      c.seg(x, y + h * 0.54, x + w * 0.56, y + h * 0.54, s);
      c.arc(
        x + w * 0.56,
        y + h * 0.27,
        w * 0.44,
        h * 0.27,
        -math.pi / 2,
        math.pi / 2,
        s,
      );
    }),
    'Q': _GlyphSpec(0.74, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.48,
        y + h * 0.48,
        w * 0.46,
        h * 0.48,
        0.0,
        math.pi * 2,
        s,
      );
      c.seg(x + w * 0.56, y + h * 0.72, x + w * 0.98, y + h * 1.06, s);
    }),
    'R': _GlyphSpec(0.64, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h, s);
      c.seg(x, y, x + w * 0.56, y, s);
      c.seg(x, y + h * 0.52, x + w * 0.56, y + h * 0.52, s);
      c.arc(
        x + w * 0.56,
        y + h * 0.26,
        w * 0.42,
        h * 0.26,
        -math.pi / 2,
        math.pi / 2,
        s,
      );
      c.seg(x + w * 0.54, y + h * 0.52, x + w * 0.96, y + h, s);
    }),
    'S': _GlyphSpec(0.60, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.25,
        w * 0.45,
        h * 0.25,
        math.pi * 0.55,
        math.pi * 1.92,
        s,
      );
      c.quad(
        x + w * 0.20,
        y + h * 0.46,
        x + w * 0.50,
        y + h * 0.50,
        x + w * 0.80,
        y + h * 0.55,
        s,
      );
      c.arc(
        x + w * 0.50,
        y + h * 0.74,
        w * 0.48,
        h * 0.26,
        -math.pi * 0.45,
        math.pi * 0.94,
        s,
      );
    }),
    'T': _GlyphSpec(0.62, (c, x, y, w, h, s) {
      c.seg(x, y, x + w, y, s);
      c.seg(x + w * 0.50, y, x + w * 0.50, y + h, s);
    }),
    'U': _GlyphSpec(0.66, (c, x, y, w, h, s) {
      c.seg(x, y, x, y + h * 0.66, s);
      c.seg(x + w, y, x + w, y + h * 0.66, s);
      c.arc(x + w * 0.50, y + h * 0.66, w * 0.50, h * 0.34, 0.0, math.pi, s);
    }),
    'V': _GlyphSpec(0.68, (c, x, y, w, h, s) {
      c.seg(x, y, x + w * 0.50, y + h, s);
      c.seg(x + w, y, x + w * 0.50, y + h, s);
    }),
    'W': _GlyphSpec(0.92, (c, x, y, w, h, s) {
      c.seg(x, y, x + w * 0.24, y + h, s);
      c.seg(x + w * 0.24, y + h, x + w * 0.50, y + h * 0.16, s);
      c.seg(x + w * 0.50, y + h * 0.16, x + w * 0.76, y + h, s);
      c.seg(x + w * 0.76, y + h, x + w, y, s);
    }),
    'X': _GlyphSpec(0.64, (c, x, y, w, h, s) {
      c.seg(x, y, x + w, y + h, s);
      c.seg(x + w, y, x, y + h, s);
    }),
    'Y': _GlyphSpec(0.64, (c, x, y, w, h, s) {
      c.seg(x, y, x + w * 0.50, y + h * 0.52, s);
      c.seg(x + w, y, x + w * 0.50, y + h * 0.52, s);
      c.seg(x + w * 0.50, y + h * 0.52, x + w * 0.50, y + h, s);
    }),
    'Z': _GlyphSpec(0.60, (c, x, y, w, h, s) {
      c.seg(x, y, x + w, y, s);
      c.seg(x + w, y, x, y + h, s);
      c.seg(x, y + h, x + w, y + h, s);
    }),

    // ========================== LOWERCASE a-z ==============================
    'a': _GlyphSpec(0.54, (c, x, y, w, h, s) {
      // Standard double-storey sans `a` (Roboto/Arial/Helvetica).
      c.arc(
        x + w * 0.50,
        y + h * 0.45,
        w * 0.44,
        h * 0.17,
        math.pi * 1.15,
        math.pi * 2.0,
        s,
      );
      c.seg(x + w * 0.94, y + h * 0.45, x + w * 0.94, y + h, s);
      c.quad(
        x + w * 0.94,
        y + h * 0.60,
        x + w * 0.35,
        y + h * 0.58,
        x + w * 0.06,
        y + h * 0.76,
        s,
      );
      c.arc(
        x + w * 0.44,
        y + h * 0.82,
        w * 0.38,
        h * 0.18,
        math.pi * 0.08,
        math.pi * 1.18,
        s,
      );
      c.seg(x + w * 0.82, y + h * 0.85, x + w * 0.94, y + h * 0.74, s);
    }),
    'b': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x + w * 0.06, y, x + w * 0.06, y + h, s);
      c.arc(
        x + w * 0.50,
        y + h * 0.64,
        w * 0.44,
        h * 0.36,
        0.0,
        math.pi * 2,
        s,
      );
    }),
    'c': _GlyphSpec(0.52, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.54,
        y + h * 0.64,
        w * 0.48,
        h * 0.36,
        0.55,
        math.pi * 2 - 0.55,
        s,
      );
    }),
    'd': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x + w * 0.94, y, x + w * 0.94, y + h, s);
      c.arc(
        x + w * 0.50,
        y + h * 0.64,
        w * 0.44,
        h * 0.36,
        0.0,
        math.pi * 2,
        s,
      );
    }),
    'e': _GlyphSpec(0.54, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.64,
        w * 0.48,
        h * 0.36,
        0.42,
        math.pi * 2.0,
        s,
      );
      c.seg(x + w * 0.04, y + h * 0.62, x + w * 0.98, y + h * 0.62, s);
    }),
    'f': _GlyphSpec(0.36, (c, x, y, w, h, s) {
      c.seg(x + w * 0.38, y + h * 0.16, x + w * 0.38, y + h, s);
      c.arc(
        x + w * 0.70,
        y + h * 0.16,
        w * 0.32,
        h * 0.16,
        math.pi,
        math.pi * 1.65,
        s,
      );
      c.seg(x, y + h * 0.32, x + w * 0.86, y + h * 0.32, s);
    }),
    'g': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.48,
        y + h * 0.64,
        w * 0.44,
        h * 0.35,
        0.0,
        math.pi * 2,
        s,
      );
      c.seg(x + w * 0.92, y + h * 0.30, x + w * 0.92, y + h * 1.04, s);
      c.arc(
        x + w * 0.50,
        y + h * 1.04,
        w * 0.42,
        h * 0.24,
        0.0,
        math.pi * 0.92,
        s,
      );
    }),
    'h': _GlyphSpec(0.54, (c, x, y, w, h, s) {
      c.seg(x + w * 0.06, y, x + w * 0.06, y + h, s);
      c.arc(
        x + w * 0.50,
        y + h * 0.54,
        w * 0.44,
        h * 0.26,
        math.pi,
        math.pi * 2,
        s,
      );
      c.seg(x + w * 0.94, y + h * 0.54, x + w * 0.94, y + h, s);
    }),
    'i': _GlyphSpec(0.18, (c, x, y, w, h, s) {
      c.dot(x + w * 0.50, y + h * 0.07, s * 0.68);
      c.seg(x + w * 0.50, y + h * 0.29, x + w * 0.50, y + h, s);
    }),
    'j': _GlyphSpec(0.28, (c, x, y, w, h, s) {
      c.dot(x + w * 0.68, y + h * 0.07, s * 0.68);
      c.seg(x + w * 0.68, y + h * 0.29, x + w * 0.68, y + h * 1.06, s);
      c.arc(
        x + w * 0.34,
        y + h * 1.06,
        w * 0.34,
        h * 0.22,
        0.0,
        math.pi * 0.85,
        s,
      );
    }),
    'k': _GlyphSpec(0.52, (c, x, y, w, h, s) {
      c.seg(x + w * 0.06, y, x + w * 0.06, y + h, s);
      c.seg(x + w * 0.92, y + h * 0.29, x + w * 0.08, y + h * 0.68, s);
      c.seg(x + w * 0.34, y + h * 0.56, x + w * 0.96, y + h, s);
    }),
    'l': _GlyphSpec(0.16, (c, x, y, w, h, s) {
      c.seg(x + w * 0.50, y, x + w * 0.50, y + h, s);
    }),
    'm': _GlyphSpec(0.84, (c, x, y, w, h, s) {
      c.seg(x + w * 0.04, y + h * 0.28, x + w * 0.04, y + h, s);
      c.arc(
        x + w * 0.27,
        y + h * 0.52,
        w * 0.23,
        h * 0.24,
        math.pi,
        math.pi * 2,
        s,
      );
      c.seg(x + w * 0.50, y + h * 0.52, x + w * 0.50, y + h, s);
      c.arc(
        x + w * 0.73,
        y + h * 0.52,
        w * 0.23,
        h * 0.24,
        math.pi,
        math.pi * 2,
        s,
      );
      c.seg(x + w * 0.96, y + h * 0.52, x + w * 0.96, y + h, s);
    }),
    'n': _GlyphSpec(0.54, (c, x, y, w, h, s) {
      c.seg(x + w * 0.06, y + h * 0.28, x + w * 0.06, y + h, s);
      c.arc(
        x + w * 0.50,
        y + h * 0.54,
        w * 0.44,
        h * 0.26,
        math.pi,
        math.pi * 2,
        s,
      );
      c.seg(x + w * 0.94, y + h * 0.54, x + w * 0.94, y + h, s);
    }),
    'o': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.64,
        w * 0.48,
        h * 0.36,
        0.0,
        math.pi * 2,
        s,
      );
    }),
    'p': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x + w * 0.06, y + h * 0.28, x + w * 0.06, y + h * 1.28, s);
      c.arc(
        x + w * 0.50,
        y + h * 0.64,
        w * 0.44,
        h * 0.36,
        0.0,
        math.pi * 2,
        s,
      );
    }),
    'q': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x + w * 0.94, y + h * 0.28, x + w * 0.94, y + h * 1.28, s);
      c.arc(
        x + w * 0.50,
        y + h * 0.64,
        w * 0.44,
        h * 0.36,
        0.0,
        math.pi * 2,
        s,
      );
    }),
    'r': _GlyphSpec(0.36, (c, x, y, w, h, s) {
      c.seg(x + w * 0.16, y + h * 0.28, x + w * 0.16, y + h, s);
      c.arc(
        x + w * 0.72,
        y + h * 0.50,
        w * 0.56,
        h * 0.22,
        math.pi,
        math.pi * 1.58,
        s,
      );
    }),
    's': _GlyphSpec(0.48, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.46,
        w * 0.42,
        h * 0.18,
        math.pi * 0.58,
        math.pi * 1.90,
        s,
      );
      c.quad(
        x + w * 0.20,
        y + h * 0.61,
        x + w * 0.50,
        y + h * 0.64,
        x + w * 0.80,
        y + h * 0.68,
        s,
      );
      c.arc(
        x + w * 0.50,
        y + h * 0.81,
        w * 0.46,
        h * 0.19,
        -math.pi * 0.42,
        math.pi * 0.92,
        s,
      );
    }),
    't': _GlyphSpec(0.36, (c, x, y, w, h, s) {
      c.seg(x + w * 0.42, y + h * 0.10, x + w * 0.42, y + h * 0.84, s);
      c.arc(
        x + w * 0.72,
        y + h * 0.84,
        w * 0.30,
        h * 0.16,
        math.pi * 0.52,
        math.pi,
        s,
      );
      c.seg(x, y + h * 0.30, x + w * 0.90, y + h * 0.30, s);
    }),
    'u': _GlyphSpec(0.54, (c, x, y, w, h, s) {
      c.seg(x + w * 0.06, y + h * 0.28, x + w * 0.06, y + h * 0.74, s);
      c.arc(x + w * 0.50, y + h * 0.74, w * 0.44, h * 0.26, 0.0, math.pi, s);
      c.seg(x + w * 0.94, y + h * 0.28, x + w * 0.94, y + h, s);
    }),
    'v': _GlyphSpec(0.52, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.28, x + w * 0.50, y + h, s);
      c.seg(x + w, y + h * 0.28, x + w * 0.50, y + h, s);
    }),
    'w': _GlyphSpec(0.76, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.28, x + w * 0.24, y + h, s);
      c.seg(x + w * 0.24, y + h, x + w * 0.50, y + h * 0.38, s);
      c.seg(x + w * 0.50, y + h * 0.38, x + w * 0.76, y + h, s);
      c.seg(x + w * 0.76, y + h, x + w, y + h * 0.28, s);
    }),
    'x': _GlyphSpec(0.50, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.28, x + w, y + h, s);
      c.seg(x + w, y + h * 0.28, x, y + h, s);
    }),
    'y': _GlyphSpec(0.52, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.28, x + w * 0.48, y + h * 0.96, s);
      c.seg(x + w, y + h * 0.28, x + w * 0.28, y + h * 1.28, s);
    }),
    'z': _GlyphSpec(0.48, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.28, x + w, y + h * 0.28, s);
      c.seg(x + w, y + h * 0.28, x, y + h, s);
      c.seg(x, y + h, x + w, y + h, s);
    }),

    // ========================== DIGITS 0-9 =================================
    '0': _GlyphSpec(0.58, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.50,
        w * 0.46,
        h * 0.50,
        0.0,
        math.pi * 2,
        s,
      );
    }),
    '1': _GlyphSpec(0.42, (c, x, y, w, h, s) {
      c.seg(x + w * 0.62, y, x + w * 0.62, y + h, s);
      c.seg(x + w * 0.14, y + h * 0.20, x + w * 0.62, y, s);
    }),
    '2': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.27,
        w * 0.44,
        h * 0.27,
        math.pi * 1.05,
        math.pi * 2.15,
        s,
      );
      c.quad(
        x + w * 0.92,
        y + h * 0.36,
        x + w * 0.60,
        y + h * 0.64,
        x,
        y + h,
        s,
      );
      c.seg(x, y + h, x + w, y + h, s);
    }),
    '3': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.48,
        y + h * 0.24,
        w * 0.44,
        h * 0.24,
        math.pi * 1.12,
        math.pi * 2.52,
        s,
      );
      c.arc(
        x + w * 0.48,
        y + h * 0.74,
        w * 0.48,
        h * 0.26,
        -math.pi * 0.50,
        math.pi * 0.90,
        s,
      );
    }),
    '4': _GlyphSpec(0.60, (c, x, y, w, h, s) {
      c.seg(x + w * 0.72, y, x + w * 0.72, y + h, s);
      c.seg(x + w * 0.72, y, x, y + h * 0.68, s);
      c.seg(x, y + h * 0.68, x + w, y + h * 0.68, s);
    }),
    '5': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x + w * 0.90, y, x + w * 0.12, y, s);
      c.seg(x + w * 0.12, y, x + w * 0.08, y + h * 0.46, s);
      c.arc(
        x + w * 0.48,
        y + h * 0.70,
        w * 0.48,
        h * 0.30,
        -math.pi * 0.72,
        math.pi * 0.90,
        s,
      );
    }),
    '6': _GlyphSpec(0.58, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.70,
        w * 0.46,
        h * 0.30,
        0.0,
        math.pi * 2,
        s,
      );
      c.quad(
        x + w * 0.04,
        y + h * 0.70,
        x + w * 0.08,
        y + h * 0.08,
        x + w * 0.80,
        y + h * 0.03,
        s,
      );
    }),
    '7': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x, y, x + w, y, s);
      c.quad(x + w, y, x + w * 0.48, y + h * 0.46, x + w * 0.24, y + h, s);
    }),
    '8': _GlyphSpec(0.58, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.24,
        w * 0.40,
        h * 0.24,
        0.0,
        math.pi * 2,
        s,
      );
      c.arc(
        x + w * 0.50,
        y + h * 0.74,
        w * 0.46,
        h * 0.26,
        0.0,
        math.pi * 2,
        s,
      );
    }),
    '9': _GlyphSpec(0.58, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.30,
        w * 0.46,
        h * 0.30,
        0.0,
        math.pi * 2,
        s,
      );
      c.quad(
        x + w * 0.96,
        y + h * 0.30,
        x + w * 0.92,
        y + h * 0.92,
        x + w * 0.20,
        y + h * 0.97,
        s,
      );
    }),

    // ======================== PUNCTUATION & SYMBOLS ========================
    '.': _GlyphSpec(0.18, (c, x, y, w, h, s) {
      c.dot(x + w * 0.50, y + h * 0.92, s * 0.85);
    }),
    ',': _GlyphSpec(0.20, (c, x, y, w, h, s) {
      c.dot(x + w * 0.56, y + h * 0.92, s * 0.78);
      c.quad(
        x + w * 0.62,
        y + h * 0.94,
        x + w * 0.58,
        y + h * 1.12,
        x + w * 0.24,
        y + h * 1.22,
        s * 0.75,
      );
    }),
    ':': _GlyphSpec(0.18, (c, x, y, w, h, s) {
      c.dot(x + w * 0.50, y + h * 0.38, s * 0.82);
      c.dot(x + w * 0.50, y + h * 0.92, s * 0.82);
    }),
    ';': _GlyphSpec(0.20, (c, x, y, w, h, s) {
      c.dot(x + w * 0.56, y + h * 0.38, s * 0.80);
      c.dot(x + w * 0.56, y + h * 0.92, s * 0.78);
      c.quad(
        x + w * 0.62,
        y + h * 0.94,
        x + w * 0.58,
        y + h * 1.12,
        x + w * 0.24,
        y + h * 1.22,
        s * 0.75,
      );
    }),
    '!': _GlyphSpec(0.20, (c, x, y, w, h, s) {
      c.seg(x + w * 0.50, y, x + w * 0.50, y + h * 0.68, s);
      c.dot(x + w * 0.50, y + h * 0.93, s * 0.78);
    }),
    '?': _GlyphSpec(0.52, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.24,
        w * 0.44,
        h * 0.24,
        math.pi * 1.05,
        math.pi * 2.35,
        s,
      );
      c.quad(
        x + w * 0.86,
        y + h * 0.40,
        x + w * 0.50,
        y + h * 0.52,
        x + w * 0.50,
        y + h * 0.70,
        s,
      );
      c.dot(x + w * 0.50, y + h * 0.93, s * 0.78);
    }),
    '-': _GlyphSpec(0.38, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.56, x + w, y + h * 0.56, s);
    }),
    '_': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x, y + h * 1.12, x + w, y + h * 1.12, s);
    }),
    '+': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.54, x + w, y + h * 0.54, s);
      c.seg(x + w * 0.50, y + h * 0.22, x + w * 0.50, y + h * 0.86, s);
    }),
    '=': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.38, x + w, y + h * 0.38, s);
      c.seg(x, y + h * 0.68, x + w, y + h * 0.68, s);
    }),
    '/': _GlyphSpec(0.42, (c, x, y, w, h, s) {
      c.seg(x + w, y - h * 0.04, x, y + h * 1.06, s);
    }),
    '\\': _GlyphSpec(0.42, (c, x, y, w, h, s) {
      c.seg(x, y - h * 0.04, x + w, y + h * 1.06, s);
    }),
    '|': _GlyphSpec(0.16, (c, x, y, w, h, s) {
      c.seg(x + w * 0.50, y - h * 0.06, x + w * 0.50, y + h * 1.16, s);
    }),
    '(': _GlyphSpec(0.30, (c, x, y, w, h, s) {
      c.quad(x + w, y - h * 0.06, x, y + h * 0.52, x + w, y + h * 1.12, s);
    }),
    ')': _GlyphSpec(0.30, (c, x, y, w, h, s) {
      c.quad(x, y - h * 0.06, x + w, y + h * 0.52, x, y + h * 1.12, s);
    }),
    '[': _GlyphSpec(0.30, (c, x, y, w, h, s) {
      c.seg(x + w, y - h * 0.04, x + w * 0.20, y - h * 0.04, s);
      c.seg(x + w * 0.20, y - h * 0.04, x + w * 0.20, y + h * 1.10, s);
      c.seg(x + w * 0.20, y + h * 1.10, x + w, y + h * 1.10, s);
    }),
    ']': _GlyphSpec(0.30, (c, x, y, w, h, s) {
      c.seg(x, y - h * 0.04, x + w * 0.80, y - h * 0.04, s);
      c.seg(x + w * 0.80, y - h * 0.04, x + w * 0.80, y + h * 1.10, s);
      c.seg(x + w * 0.80, y + h * 1.10, x, y + h * 1.10, s);
    }),
    '{': _GlyphSpec(0.36, (c, x, y, w, h, s) {
      c.quad(
        x + w,
        y - h * 0.04,
        x + w * 0.42,
        y,
        x + w * 0.46,
        y + h * 0.34,
        s,
      );
      c.quad(
        x + w * 0.46,
        y + h * 0.34,
        x + w * 0.46,
        y + h * 0.52,
        x,
        y + h * 0.52,
        s,
      );
      c.quad(
        x,
        y + h * 0.52,
        x + w * 0.46,
        y + h * 0.52,
        x + w * 0.46,
        y + h * 0.72,
        s,
      );
      c.quad(
        x + w * 0.46,
        y + h * 0.72,
        x + w * 0.42,
        y + h * 1.08,
        x + w,
        y + h * 1.10,
        s,
      );
    }),
    '}': _GlyphSpec(0.36, (c, x, y, w, h, s) {
      c.quad(x, y - h * 0.04, x + w * 0.58, y, x + w * 0.54, y + h * 0.34, s);
      c.quad(
        x + w * 0.54,
        y + h * 0.34,
        x + w * 0.54,
        y + h * 0.52,
        x + w,
        y + h * 0.52,
        s,
      );
      c.quad(
        x + w,
        y + h * 0.52,
        x + w * 0.54,
        y + h * 0.52,
        x + w * 0.54,
        y + h * 0.72,
        s,
      );
      c.quad(
        x + w * 0.54,
        y + h * 0.72,
        x + w * 0.58,
        y + h * 1.08,
        x,
        y + h * 1.10,
        s,
      );
    }),
    '<': _GlyphSpec(0.52, (c, x, y, w, h, s) {
      c.seg(x + w, y + h * 0.24, x, y + h * 0.56, s);
      c.seg(x, y + h * 0.56, x + w, y + h * 0.88, s);
    }),
    '>': _GlyphSpec(0.52, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.24, x + w, y + h * 0.56, s);
      c.seg(x + w, y + h * 0.56, x, y + h * 0.88, s);
    }),
    '\'': _GlyphSpec(0.16, (c, x, y, w, h, s) {
      c.seg(x + w * 0.50, y, x + w * 0.50, y + h * 0.26, s);
    }),
    '"': _GlyphSpec(0.36, (c, x, y, w, h, s) {
      c.seg(x + w * 0.25, y, x + w * 0.25, y + h * 0.26, s);
      c.seg(x + w * 0.75, y, x + w * 0.75, y + h * 0.26, s);
    }),
    '`': _GlyphSpec(0.24, (c, x, y, w, h, s) {
      c.seg(x + w * 0.20, y, x + w * 0.80, y + h * 0.22, s);
    }),
    '@': _GlyphSpec(0.86, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.52,
        w * 0.48,
        h * 0.50,
        0.55,
        math.pi * 2.15,
        s,
      );
      c.arc(
        x + w * 0.50,
        y + h * 0.52,
        w * 0.22,
        h * 0.22,
        0.0,
        math.pi * 2,
        s,
      );
      c.seg(x + w * 0.72, y + h * 0.30, x + w * 0.72, y + h * 0.72, s);
      c.arc(x + w * 0.84, y + h * 0.62, w * 0.14, h * 0.14, 0.0, math.pi, s);
    }),
    '#': _GlyphSpec(0.64, (c, x, y, w, h, s) {
      c.seg(x + w * 0.34, y, x + w * 0.20, y + h, s);
      c.seg(x + w * 0.78, y, x + w * 0.64, y + h, s);
      c.seg(x + w * 0.06, y + h * 0.34, x + w * 0.96, y + h * 0.34, s);
      c.seg(x, y + h * 0.68, x + w * 0.90, y + h * 0.68, s);
    }),
    r'$': _GlyphSpec(0.58, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.50,
        y + h * 0.28,
        w * 0.42,
        h * 0.22,
        math.pi * 0.55,
        math.pi * 1.92,
        s,
      );
      c.quad(
        x + w * 0.20,
        y + h * 0.47,
        x + w * 0.50,
        y + h * 0.51,
        x + w * 0.80,
        y + h * 0.55,
        s,
      );
      c.arc(
        x + w * 0.50,
        y + h * 0.73,
        w * 0.45,
        h * 0.24,
        -math.pi * 0.45,
        math.pi * 0.92,
        s,
      );
      c.seg(x + w * 0.50, y - h * 0.08, x + w * 0.50, y + h * 1.12, s * 0.88);
    }),
    '%': _GlyphSpec(0.76, (c, x, y, w, h, s) {
      c.seg(x + w * 0.82, y, x + w * 0.18, y + h, s);
      c.arc(
        x + w * 0.22,
        y + h * 0.22,
        w * 0.18,
        h * 0.20,
        0.0,
        math.pi * 2,
        s * 0.88,
      );
      c.arc(
        x + w * 0.78,
        y + h * 0.78,
        w * 0.18,
        h * 0.20,
        0.0,
        math.pi * 2,
        s * 0.88,
      );
    }),
    '^': _GlyphSpec(0.46, (c, x, y, w, h, s) {
      c.seg(x, y + h * 0.40, x + w * 0.50, y, s);
      c.seg(x + w * 0.50, y, x + w, y + h * 0.40, s);
    }),
    '&': _GlyphSpec(0.66, (c, x, y, w, h, s) {
      c.arc(
        x + w * 0.44,
        y + h * 0.22,
        w * 0.24,
        h * 0.20,
        0.0,
        math.pi * 2,
        s,
      );
      c.arc(
        x + w * 0.40,
        y + h * 0.74,
        w * 0.36,
        h * 0.26,
        0.2,
        math.pi * 1.75,
        s,
      );
      c.seg(x + w * 0.24, y + h * 0.36, x + w * 0.94, y + h, s);
      c.seg(x + w * 0.92, y + h * 0.56, x + w * 0.56, y + h, s);
    }),
    '*': _GlyphSpec(0.44, (c, x, y, w, h, s) {
      final cx = x + w * 0.50;
      final cy = y + h * 0.22;
      final r = w * 0.46;
      for (var k = 0; k < 3; k++) {
        final a = k * math.pi / 3;
        c.seg(
          cx - math.cos(a) * r,
          cy - math.sin(a) * r,
          cx + math.cos(a) * r,
          cy + math.sin(a) * r,
          s * 0.82,
        );
      }
    }),
    '~': _GlyphSpec(0.56, (c, x, y, w, h, s) {
      c.quad(
        x,
        y + h * 0.58,
        x + w * 0.25,
        y + h * 0.38,
        x + w * 0.50,
        y + h * 0.54,
        s,
      );
      c.quad(
        x + w * 0.50,
        y + h * 0.54,
        x + w * 0.75,
        y + h * 0.70,
        x + w,
        y + h * 0.50,
        s,
      );
    }),
  };

  // Multi-font stylistic variants (geometric, serif, monospace, handwritten-clean).
  static final Map<String, List<_GlyphVariant>> _variantSpecs =
      <String, List<_GlyphVariant>>{
        'a': <_GlyphVariant>[
          _GlyphVariant(
            'geometric_single_storey',
            _GlyphSpec(0.54, (c, x, y, w, h, s) {
              c.arc(
                x + w * 0.48,
                y + h * 0.64,
                w * 0.44,
                h * 0.36,
                0.0,
                math.pi * 2,
                s,
              );
              c.seg(x + w * 0.92, y + h * 0.28, x + w * 0.92, y + h, s);
            }),
          ),
        ],
        '1': <_GlyphVariant>[
          _GlyphVariant(
            'serif_base',
            _GlyphSpec(0.48, (c, x, y, w, h, s) {
              c.seg(x + w * 0.54, y, x + w * 0.54, y + h, s);
              c.seg(x + w * 0.14, y + h * 0.22, x + w * 0.54, y, s);
              c.seg(x + w * 0.12, y + h, x + w * 0.96, y + h, s);
            }),
          ),
          _GlyphVariant(
            'plain_stem',
            _GlyphSpec(0.24, (c, x, y, w, h, s) {
              c.seg(x + w * 0.58, y, x + w * 0.58, y + h, s);
              c.seg(x + w * 0.22, y + h * 0.14, x + w * 0.58, y, s);
            }),
          ),
        ],
        'I': <_GlyphVariant>[
          _GlyphVariant(
            'serif_bars',
            _GlyphSpec(0.42, (c, x, y, w, h, s) {
              c.seg(x + w * 0.50, y, x + w * 0.50, y + h, s);
              c.seg(x + w * 0.06, y, x + w * 0.94, y, s);
              c.seg(x + w * 0.06, y + h, x + w * 0.94, y + h, s);
            }),
          ),
        ],
        'J': <_GlyphVariant>[
          _GlyphVariant(
            'top_bar',
            _GlyphSpec(0.54, (c, x, y, w, h, s) {
              c.seg(x + w * 0.24, y, x + w * 0.96, y, s);
              c.seg(x + w * 0.72, y, x + w * 0.72, y + h * 0.72, s);
              c.arc(
                x + w * 0.38,
                y + h * 0.72,
                w * 0.34,
                h * 0.28,
                0.0,
                math.pi * 0.92,
                s,
              );
            }),
          ),
        ],
        '0': <_GlyphVariant>[
          _GlyphVariant(
            'mono_slashed',
            _GlyphSpec(0.58, (c, x, y, w, h, s) {
              c.arc(
                x + w * 0.50,
                y + h * 0.50,
                w * 0.46,
                h * 0.50,
                0.0,
                math.pi * 2,
                s,
              );
              c.seg(
                x + w * 0.80,
                y + h * 0.18,
                x + w * 0.20,
                y + h * 0.82,
                s * 0.75,
              );
            }),
          ),
        ],
        '4': <_GlyphVariant>[
          _GlyphVariant(
            'open_top',
            _GlyphSpec(0.58, (c, x, y, w, h, s) {
              c.seg(x + w * 0.12, y, x + w * 0.06, y + h * 0.64, s);
              c.seg(x + w * 0.06, y + h * 0.64, x + w, y + h * 0.64, s);
              c.seg(x + w * 0.74, y, x + w * 0.74, y + h, s);
            }),
          ),
        ],
        '7': <_GlyphVariant>[
          _GlyphVariant(
            'straight_diag',
            _GlyphSpec(0.56, (c, x, y, w, h, s) {
              c.seg(x, y, x + w, y, s);
              c.seg(x + w, y, x + w * 0.22, y + h, s);
            }),
          ),
        ],
        'l': <_GlyphVariant>[
          _GlyphVariant(
            'curved_tail',
            _GlyphSpec(0.28, (c, x, y, w, h, s) {
              c.seg(x + w * 0.36, y, x + w * 0.36, y + h * 0.84, s);
              c.arc(
                x + w * 0.68,
                y + h * 0.84,
                w * 0.32,
                h * 0.16,
                math.pi * 0.5,
                math.pi,
                s,
              );
            }),
          ),
        ],
        't': <_GlyphVariant>[
          _GlyphVariant(
            'straight_bottom',
            _GlyphSpec(0.36, (c, x, y, w, h, s) {
              c.seg(x + w * 0.48, y + h * 0.10, x + w * 0.48, y + h, s);
              c.seg(x, y + h * 0.30, x + w, y + h * 0.30, s);
            }),
          ),
        ],
        'y': <_GlyphVariant>[
          _GlyphVariant(
            'curved_descender',
            _GlyphSpec(0.52, (c, x, y, w, h, s) {
              c.seg(x, y + h * 0.28, x + w * 0.48, y + h * 0.94, s);
              c.seg(x + w, y + h * 0.28, x + w * 0.42, y + h * 1.12, s);
              c.quad(
                x + w * 0.42,
                y + h * 1.12,
                x + w * 0.30,
                y + h * 1.28,
                x + w * 0.08,
                y + h * 1.26,
                s,
              );
            }),
          ),
        ],
        '6': <_GlyphVariant>[
          _GlyphVariant(
            'straight_neck',
            _GlyphSpec(0.58, (c, x, y, w, h, s) {
              c.arc(
                x + w * 0.50,
                y + h * 0.70,
                w * 0.46,
                h * 0.30,
                0.0,
                math.pi * 2,
                s,
              );
              c.seg(x + w * 0.10, y + h * 0.58, x + w * 0.60, y, s);
            }),
          ),
        ],
        '9': <_GlyphVariant>[
          _GlyphVariant(
            'straight_tail',
            _GlyphSpec(0.58, (c, x, y, w, h, s) {
              c.arc(
                x + w * 0.50,
                y + h * 0.30,
                w * 0.46,
                h * 0.30,
                0.0,
                math.pi * 2,
                s,
              );
              c.seg(x + w * 0.90, y + h * 0.42, x + w * 0.40, y + h, s);
            }),
          ),
        ],
        'H': <_GlyphVariant>[
          _GlyphVariant(
            'serif_slab',
            _GlyphSpec(0.72, (c, x, y, w, h, s) {
              c.seg(x + w * 0.14, y, x + w * 0.14, y + h, s);
              c.seg(x + w * 0.86, y, x + w * 0.86, y + h, s);
              c.seg(x + w * 0.14, y + h * 0.49, x + w * 0.86, y + h * 0.49, s);
              c.seg(x, y, x + w * 0.30, y, s * 0.8);
              c.seg(x + w * 0.70, y, x + w, y, s * 0.8);
              c.seg(x, y + h, x + w * 0.30, y + h, s * 0.8);
              c.seg(x + w * 0.70, y + h, x + w, y + h, s * 0.8);
            }),
          ),
        ],
        'i': <_GlyphVariant>[
          _GlyphVariant(
            'serif_i',
            _GlyphSpec(0.42, (c, x, y, w, h, s) {
              c.dot(x + w * 0.52, y + h * 0.08, s * 0.65);
              c.seg(x + w * 0.52, y + h * 0.29, x + w * 0.52, y + h, s);
              c.seg(
                x + w * 0.18,
                y + h * 0.29,
                x + w * 0.52,
                y + h * 0.29,
                s * 0.8,
              );
              c.seg(x + w * 0.08, y + h, x + w * 0.96, y + h, s * 0.8);
            }),
          ),
        ],
        'j': <_GlyphVariant>[
          _GlyphVariant(
            'serif_j',
            _GlyphSpec(0.38, (c, x, y, w, h, s) {
              c.dot(x + w * 0.68, y + h * 0.08, s * 0.65);
              c.seg(
                x + w * 0.34,
                y + h * 0.29,
                x + w * 0.68,
                y + h * 0.29,
                s * 0.8,
              );
              c.seg(x + w * 0.68, y + h * 0.29, x + w * 0.68, y + h * 1.08, s);
              c.arc(
                x + w * 0.36,
                y + h * 1.08,
                w * 0.32,
                h * 0.20,
                0.0,
                math.pi * 0.88,
                s,
              );
            }),
          ),
        ],
        'f': <_GlyphVariant>[
          _GlyphVariant(
            'serif_f',
            _GlyphSpec(0.48, (c, x, y, w, h, s) {
              c.seg(x + w * 0.42, y + h * 0.15, x + w * 0.42, y + h, s);
              c.arc(
                x + w * 0.72,
                y + h * 0.15,
                w * 0.30,
                h * 0.15,
                math.pi,
                math.pi * 1.72,
                s,
              );
              c.seg(x + w * 0.08, y + h * 0.32, x + w * 0.84, y + h * 0.32, s);
              c.seg(x + w * 0.10, y + h, x + w * 0.80, y + h, s * 0.8);
            }),
          ),
        ],
        'r': <_GlyphVariant>[
          _GlyphVariant(
            'serif_r',
            _GlyphSpec(0.48, (c, x, y, w, h, s) {
              c.seg(x + w * 0.28, y + h * 0.28, x + w * 0.28, y + h, s);
              c.arc(
                x + w * 0.70,
                y + h * 0.48,
                w * 0.42,
                h * 0.20,
                math.pi,
                math.pi * 1.65,
                s,
              );
              c.seg(x + w * 0.06, y + h, x + w * 0.64, y + h, s * 0.8);
            }),
          ),
        ],
        'u': <_GlyphVariant>[
          _GlyphVariant(
            'serif_u',
            _GlyphSpec(0.60, (c, x, y, w, h, s) {
              c.seg(x + w * 0.12, y + h * 0.28, x + w * 0.12, y + h * 0.74, s);
              c.arc(
                x + w * 0.48,
                y + h * 0.74,
                w * 0.36,
                h * 0.26,
                0.0,
                math.pi,
                s,
              );
              c.seg(x + w * 0.84, y + h * 0.28, x + w * 0.84, y + h, s);
              c.seg(x, y + h * 0.28, x + w * 0.20, y + h * 0.28, s * 0.75);
              c.seg(x + w * 0.76, y + h, x + w, y + h, s * 0.75);
            }),
          ),
        ],
        'g': <_GlyphVariant>[
          _GlyphVariant(
            'double_storey_serif',
            _GlyphSpec(0.56, (c, x, y, w, h, s) {
              c.arc(
                x + w * 0.46,
                y + h * 0.48,
                w * 0.34,
                h * 0.20,
                0.0,
                math.pi * 2,
                s,
              );
              c.seg(
                x + w * 0.74,
                y + h * 0.30,
                x + w * 0.96,
                y + h * 0.26,
                s * 0.8,
              );
              c.quad(
                x + w * 0.22,
                y + h * 0.66,
                x + w * 0.10,
                y + h * 0.80,
                x + w * 0.24,
                y + h * 0.88,
                s,
              );
              c.arc(
                x + w * 0.50,
                y + h * 1.04,
                w * 0.42,
                h * 0.22,
                0.0,
                math.pi * 2,
                s,
              );
            }),
          ),
        ],
      };
}

typedef _GlyphDrawer =
    void Function(
      _SubpixelCanvas canvas,
      double x,
      double y,
      double w,
      double h,
      double stroke,
    );

class _GlyphSpec {
  const _GlyphSpec(this.widthRatio, this.draw);
  final double widthRatio;
  final _GlyphDrawer draw;
}

class _GlyphVariant {
  const _GlyphVariant(this.style, this.spec);
  final String style;
  final _GlyphSpec spec;
}

/// Anti-aliased sub-pixel distance-field stroke rasterizer in pure Dart.
class _SubpixelCanvas {
  const _SubpixelCanvas(this.buffer, this.width, this.height);

  final Float32List buffer;
  final int width;
  final int height;

  void dot(double cx, double cy, double radius) {
    final rPad = radius + 1.2;
    final x0 = math.max(0, (cx - rPad).floor());
    final x1 = math.min(width - 1, (cx + rPad).ceil());
    final y0 = math.max(0, (cy - rPad).floor());
    final y1 = math.min(height - 1, (cy + rPad).ceil());

    for (var y = y0; y <= y1; y++) {
      final dy = (y + 0.5) - cy;
      final row = y * width;
      for (var x = x0; x <= x1; x++) {
        final dx = (x + 0.5) - cx;
        final dist = math.sqrt(dx * dx + dy * dy);
        final alpha = (radius + 0.5 - dist).clamp(0.0, 1.0);
        if (alpha > buffer[row + x]) buffer[row + x] = alpha;
      }
    }
  }

  void seg(double x1, double y1, double x2, double y2, double stroke) {
    final radius = stroke * 0.5;
    final rPad = radius + 1.2;
    final minX = math.max(0, (math.min(x1, x2) - rPad).floor());
    final maxX = math.min(width - 1, (math.max(x1, x2) + rPad).ceil());
    final minY = math.max(0, (math.min(y1, y2) - rPad).floor());
    final maxY = math.min(height - 1, (math.max(y1, y2) + rPad).ceil());

    final vx = x2 - x1;
    final vy = y2 - y1;
    final lenSq = vx * vx + vy * vy;

    for (var y = minY; y <= maxY; y++) {
      final py = y + 0.5;
      final row = y * width;
      for (var x = minX; x <= maxX; x++) {
        final px = x + 0.5;
        final t = lenSq > 1e-6
            ? (((px - x1) * vx + (py - y1) * vy) / lenSq).clamp(0.0, 1.0)
            : 0.0;
        final dx = px - (x1 + t * vx);
        final dy = py - (y1 + t * vy);
        final dist = math.sqrt(dx * dx + dy * dy);
        final alpha = (radius + 0.5 - dist).clamp(0.0, 1.0);
        if (alpha > buffer[row + x]) buffer[row + x] = alpha;
      }
    }
  }

  void quad(
    double x0,
    double y0,
    double cx,
    double cy,
    double x1,
    double y1,
    double stroke,
  ) {
    const steps = 14;
    var px = x0;
    var py = y0;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final u = 1.0 - t;
      final nx = u * u * x0 + 2 * u * t * cx + t * t * x1;
      final ny = u * u * y0 + 2 * u * t * cy + t * t * y1;
      seg(px, py, nx, ny, stroke);
      px = nx;
      py = ny;
    }
  }

  void arc(
    double cx,
    double cy,
    double rx,
    double ry,
    double startAngle,
    double endAngle,
    double stroke,
  ) {
    final span = (endAngle - startAngle).abs();
    final steps = math.max(8, (span * 8.0).ceil());
    var px = cx + math.cos(startAngle) * rx;
    var py = cy + math.sin(startAngle) * ry;
    for (var i = 1; i <= steps; i++) {
      final a = startAngle + (endAngle - startAngle) * (i / steps);
      final nx = cx + math.cos(a) * rx;
      final ny = cy + math.sin(a) * ry;
      seg(px, py, nx, ny, stroke);
      px = nx;
      py = ny;
    }
  }
}
