import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ocr_geometry.dart';

/// A connected foreground ink component extracted from a binary image.
class OcrGlyphBlob {
  /// Creates an [OcrGlyphBlob] with its exact pixel [mask].
  const OcrGlyphBlob({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.pixelCount,
    required this.mask,
  });

  /// Left coordinate in preprocessed image pixels.
  final int left;

  /// Top coordinate in preprocessed image pixels.
  final int top;

  /// Width of the tight bounding box in pixels.
  final int width;

  /// Height of the tight bounding box in pixels.
  final int height;

  /// Total foreground ink pixel count inside [mask].
  final int pixelCount;

  /// Tightly cropped binary mask (`width * height`), where `1` denotes ink
  /// belonging specifically to this component.
  final Uint8List mask;

  /// Right edge (`left + width`).
  int get right => left + width;

  /// Bottom edge (`top + height`).
  int get bottom => top + height;

  /// Horizontal center in pixels.
  double get centerX => left + width * 0.5;

  /// Vertical center in pixels.
  double get centerY => top + height * 0.5;

  /// Aspect ratio (`width / height`).
  double get aspectRatio => height > 0 ? width / height : 0.0;

  /// Ink fill density (`pixelCount / (width * height)`).
  double get density =>
      (width * height) > 0 ? pixelCount / (width * height) : 0;

  /// Bounding rectangle as an [OcrRect].
  OcrRect get rect => OcrRect(
    left: left.toDouble(),
    top: top.toDouble(),
    width: width.toDouble(),
    height: height.toDouble(),
  );

  /// Merges this blob with [other] into a single combined [OcrGlyphBlob].
  OcrGlyphBlob mergeWith(OcrGlyphBlob other) {
    final newLeft = math.min(left, other.left);
    final newTop = math.min(top, other.top);
    final newRight = math.max(right, other.right);
    final newBottom = math.max(bottom, other.bottom);
    final newW = newRight - newLeft;
    final newH = newBottom - newTop;
    final merged = Uint8List(newW * newH);
    var count = 0;

    void copyBlob(OcrGlyphBlob b) {
      final ox = b.left - newLeft;
      final oy = b.top - newTop;
      for (var y = 0; y < b.height; y++) {
        final srcRow = y * b.width;
        final dstRow = (oy + y) * newW + ox;
        for (var x = 0; x < b.width; x++) {
          if (b.mask[srcRow + x] != 0 && merged[dstRow + x] == 0) {
            merged[dstRow + x] = 1;
            count++;
          }
        }
      }
    }

    copyBlob(this);
    copyBlob(other);

    return OcrGlyphBlob(
      left: newLeft,
      top: newTop,
      width: newW,
      height: newH,
      pixelCount: count,
      mask: merged,
    );
  }
}

/// Fast two-pass Union-Find 8-connectivity Connected Component Labeling (CCL)
/// with noise filtering and multi-part glyph reattachment (`i`, `j`, `!`, `?`,
/// `:`, `;`, `=`, `%`, `"`).
class OcrCcl {
  const OcrCcl._();

  /// Extracts all text-candidate connected components from [binary].
  static List<OcrGlyphBlob> extractComponents(
    Uint8List binary, {
    required int width,
    required int height,
  }) {
    final total = width * height;
    if (total == 0) return const <OcrGlyphBlob>[];

    final labels = Int32List(total);
    // Disjoint-set parent array (1-indexed labels; 0 = background).
    var parent = Int32List(math.max(256, total ~/ 8));
    var nextLabel = 1;

    int findRoot(int x) {
      var r = x;
      while (parent[r] != r) {
        r = parent[r];
      }
      var curr = x;
      while (curr != r) {
        final next = parent[curr];
        parent[curr] = r;
        curr = next;
      }
      return r;
    }

    void unionLabels(int a, int b) {
      final ra = findRoot(a);
      final rb = findRoot(b);
      if (ra == rb) return;
      if (ra < rb) {
        parent[rb] = ra;
      } else {
        parent[ra] = rb;
      }
    }

    // Pass 1: assign provisional labels & record equivalences (8-connectivity).
    for (var y = 0; y < height; y++) {
      final row = y * width;
      final prevRow = (y - 1) * width;
      for (var x = 0; x < width; x++) {
        if (binary[row + x] == 0) continue;

        var minNeighbor = 0;
        // Check 4 already-visited 8-neighbors: W, NW, N, NE.
        final nW = x > 0 ? labels[row + x - 1] : 0;
        final nNW = (y > 0 && x > 0) ? labels[prevRow + x - 1] : 0;
        final nN = y > 0 ? labels[prevRow + x] : 0;
        final nNE = (y > 0 && x + 1 < width) ? labels[prevRow + x + 1] : 0;

        if (nW != 0) minNeighbor = nW;
        if (nNW != 0 && (minNeighbor == 0 || nNW < minNeighbor)) {
          minNeighbor = nNW;
        }
        if (nN != 0 && (minNeighbor == 0 || nN < minNeighbor)) {
          minNeighbor = nN;
        }
        if (nNE != 0 && (minNeighbor == 0 || nNE < minNeighbor)) {
          minNeighbor = nNE;
        }

        if (minNeighbor == 0) {
          if (nextLabel >= parent.length) {
            final grown = Int32List(parent.length * 2);
            grown.setRange(0, parent.length, parent);
            parent = grown;
          }
          parent[nextLabel] = nextLabel;
          labels[row + x] = nextLabel;
          nextLabel++;
        } else {
          final root = findRoot(minNeighbor);
          labels[row + x] = root;
          if (nW != 0) unionLabels(root, nW);
          if (nNW != 0) unionLabels(root, nNW);
          if (nN != 0) unionLabels(root, nN);
          if (nNE != 0) unionLabels(root, nNE);
        }
      }
    }

    if (nextLabel == 1) return const <OcrGlyphBlob>[];

    // Flatten roots & compact IDs to dense range [1..numComponents].
    final remap = Int32List(nextLabel);
    var numComponents = 0;
    for (var i = 1; i < nextLabel; i++) {
      final root = findRoot(i);
      if (remap[root] == 0) {
        numComponents++;
        remap[root] = numComponents;
      }
      remap[i] = remap[root];
    }

    // Pass 2: compute tight bounding boxes & pixel counts.
    final minX = Int32List(numComponents + 1)
      ..fillRange(0, numComponents + 1, width);
    final minY = Int32List(numComponents + 1)
      ..fillRange(0, numComponents + 1, height);
    final maxX = Int32List(numComponents + 1)
      ..fillRange(0, numComponents + 1, -1);
    final maxY = Int32List(numComponents + 1)
      ..fillRange(0, numComponents + 1, -1);
    final counts = Int32List(numComponents + 1);

    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final raw = labels[row + x];
        if (raw == 0) continue;
        final id = remap[raw];
        labels[row + x] = id;
        counts[id]++;
        if (x < minX[id]) minX[id] = x;
        if (x > maxX[id]) maxX[id] = x;
        if (y < minY[id]) minY[id] = y;
        if (y > maxY[id]) maxY[id] = y;
      }
    }

    // Identify valid text-like components (filter frames, divider lines, 1px noise).
    final keep = Uint8List(numComponents + 1);
    final minPixels = (width * height > 20000) ? 2 : 1;

    for (var id = 1; id <= numComponents; id++) {
      final c = counts[id];
      if (c < minPixels) continue;
      final bw = maxX[id] - minX[id] + 1;
      final bh = maxY[id] - minY[id] + 1;

      // Reject giant borders/frames encompassing most of the page.
      if (bw > width * 0.85 && bh > height * 0.85) continue;
      // Reject long thin horizontal rules / table borders.
      if (bw > width * 0.60 && bh <= 4 && bw > bh * 14) continue;
      // Reject long thin vertical rules / borders.
      if (bh > height * 0.65 && bw <= 4 && bh > bw * 14) continue;

      keep[id] = 1;
    }

    // Allocate exact masks for kept components.
    final masks = List<Uint8List?>.filled(numComponents + 1, null);
    for (var id = 1; id <= numComponents; id++) {
      if (keep[id] == 0) continue;
      final bw = maxX[id] - minX[id] + 1;
      final bh = maxY[id] - minY[id] + 1;
      masks[id] = Uint8List(bw * bh);
    }

    // Fill per-component masks in a single linear scan.
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final id = labels[row + x];
        if (id == 0 || keep[id] == 0) continue;
        final bw = maxX[id] - minX[id] + 1;
        masks[id]![(y - minY[id]) * bw + (x - minX[id])] = 1;
      }
    }

    final result = <OcrGlyphBlob>[];
    for (var id = 1; id <= numComponents; id++) {
      final mask = masks[id];
      if (mask == null) continue;
      result.add(
        OcrGlyphBlob(
          left: minX[id],
          top: minY[id],
          width: maxX[id] - minX[id] + 1,
          height: maxY[id] - minY[id] + 1,
          pixelCount: counts[id],
          mask: mask,
        ),
      );
    }
    return result;
  }

  /// Reattaches vertically or tightly aligned multi-part glyphs (`i`, `j`, `!`,
  /// `?`, `:`, `;`, `=`, `%`, `"`) within a single segmented text line.
  static List<OcrGlyphBlob> mergeLineMultiPartGlyphs(
    List<OcrGlyphBlob> lineBlobs, {
    required double estimatedLineHeight,
  }) {
    if (lineBlobs.length < 2) return lineBlobs;

    final sorted = List<OcrGlyphBlob>.from(lineBlobs)
      ..sort((OcrGlyphBlob a, OcrGlyphBlob b) => a.left.compareTo(b.left));
    final consumed = List<bool>.filled(sorted.length, false);
    final merged = <OcrGlyphBlob>[];

    for (var i = 0; i < sorted.length; i++) {
      if (consumed[i]) continue;
      var current = sorted[i];
      consumed[i] = true;

      // Check nearby blobs horizontally overlapping or nearly aligned.
      var didMerge = true;
      while (didMerge) {
        didMerge = false;
        for (var j = 0; j < sorted.length; j++) {
          if (consumed[j]) continue;
          final other = sorted[j];
          if (_shouldMergePair(current, other, estimatedLineHeight)) {
            current = current.mergeWith(other);
            consumed[j] = true;
            didMerge = true;
          }
        }
      }
      merged.add(current);
    }

    // Second pass: merge `%` (small top-left loop + slash + small bottom-right loop).
    if (merged.length >= 3) {
      merged.sort((OcrGlyphBlob a, OcrGlyphBlob b) => a.left.compareTo(b.left));
      final pctOut = <OcrGlyphBlob>[];
      var idx = 0;
      while (idx < merged.length) {
        if (idx + 2 < merged.length &&
            _isPercentTriplet(
              merged[idx],
              merged[idx + 1],
              merged[idx + 2],
              estimatedLineHeight,
            )) {
          pctOut.add(
            merged[idx].mergeWith(merged[idx + 1]).mergeWith(merged[idx + 2]),
          );
          idx += 3;
        } else {
          pctOut.add(merged[idx]);
          idx++;
        }
      }
      return pctOut;
    }

    merged.sort((OcrGlyphBlob a, OcrGlyphBlob b) => a.left.compareTo(b.left));
    return merged;
  }

  static bool _shouldMergePair(
    OcrGlyphBlob a,
    OcrGlyphBlob b,
    double lineHeight,
  ) {
    final top = a.centerY <= b.centerY ? a : b;
    final bot = identical(top, a) ? b : a;

    // Horizontal overlap or tight horizontal center alignment.
    final overlapX =
        math.min(top.right, bot.right) - math.max(top.left, bot.left);
    final minW = math.min(top.width, bot.width);
    final maxW = math.max(top.width, bot.width);
    final centerDx = (top.centerX - bot.centerX).abs();

    final vGap = bot.top - top.bottom;
    final combinedH =
        math.max(top.bottom, bot.bottom) - math.min(top.top, bot.top);

    // Case 1: Vertical stack (i, j, !, ?, :, ;, =).
    final verticallySeparated = vGap >= -2 && vGap <= lineHeight * 0.68;
    // Also allow dot to sit over the right side of a curved stem such as `j`.
    final topWithinBotSpan =
        top.left >= bot.left - 2 && top.right <= bot.right + 2;
    final botWithinTopSpan =
        bot.left >= top.left - 2 && bot.right <= top.right + 2;
    final horizontallyAligned =
        overlapX >= math.max(1, minW * 0.25) ||
        centerDx <= math.max(3.0, maxW * 0.58) ||
        topWithinBotSpan ||
        botWithinTopSpan;

    if (verticallySeparated &&
        horizontallyAligned &&
        combinedH <= lineHeight * 1.50) {
      // `i` / `j` / diacritic: small top dot above taller stem.
      if (vGap <= lineHeight * 0.46 &&
          top.height <= lineHeight * 0.38 &&
          top.width <= lineHeight * 0.45 &&
          bot.height >= lineHeight * 0.35 &&
          bot.width <= lineHeight * 0.72) {
        return true;
      }

      // `!` / `?`: taller upper mark above small bottom dot.
      if (vGap <= lineHeight * 0.46 &&
          bot.height <= lineHeight * 0.34 &&
          bot.width <= lineHeight * 0.40 &&
          top.height >= lineHeight * 0.35 &&
          top.width <= lineHeight * 0.72) {
        return true;
      }

      // `:` / `;`: two small vertically stacked dots/comma.
      if (top.height <= lineHeight * 0.36 &&
          bot.height <= lineHeight * 0.48 &&
          top.width <= lineHeight * 0.38 &&
          bot.width <= lineHeight * 0.40 &&
          centerDx <= math.max(3.0, maxW * 0.65)) {
        return true;
      }

      // `=`: two flat horizontal bars stacked directly above each other.
      if (vGap <= lineHeight * 0.44 &&
          top.height <= lineHeight * 0.26 &&
          bot.height <= lineHeight * 0.26 &&
          top.width >= top.height * 1.6 &&
          bot.width >= bot.height * 1.6 &&
          overlapX >= minW * 0.55) {
        return true;
      }
    }

    // Case 2: Double quotation mark `"` (two tiny upper ticks side by side).
    final hGap = math.max(a.left, b.left) - math.min(a.right, b.right);
    if (hGap >= 0 &&
        hGap <= math.max(3.0, lineHeight * 0.22) &&
        a.height <= lineHeight * 0.42 &&
        b.height <= lineHeight * 0.42 &&
        a.width <= lineHeight * 0.26 &&
        b.width <= lineHeight * 0.26 &&
        (a.top - b.top).abs() <= lineHeight * 0.12 &&
        (a.bottom - b.bottom).abs() <= lineHeight * 0.14 &&
        a.height >= a.width * 1.15 &&
        b.height >= b.width * 1.15) {
      return true;
    }

    return false;
  }

  static bool _isPercentTriplet(
    OcrGlyphBlob a,
    OcrGlyphBlob b,
    OcrGlyphBlob c,
    double lineHeight,
  ) {
    // Identify which of the 3 neighboring blobs is the tall diagonal slash `/`
    // (because slash.left may sit to the left of the upper-left circle in bold fonts).
    final triple = <OcrGlyphBlob>[a, b, c]
      ..sort((OcrGlyphBlob x, OcrGlyphBlob y) => y.height.compareTo(x.height));
    final slash = triple[0];
    final dotA = triple[1];
    final dotB = triple[2];

    if (slash.height < lineHeight * 0.55) return false;
    if (dotA.height > lineHeight * 0.68 || dotB.height > lineHeight * 0.68) {
      return false;
    }
    if (dotA.width > lineHeight * 0.68 || dotB.width > lineHeight * 0.68) {
      return false;
    }

    final upperDot = dotA.centerY <= dotB.centerY ? dotA : dotB;
    final lowerDot = identical(upperDot, dotA) ? dotB : dotA;

    // Upper circle must sit above & left of lower circle, flanking the slash.
    if (upperDot.centerY >= slash.centerY ||
        lowerDot.centerY <= slash.centerY ||
        upperDot.centerX >= lowerDot.centerX) {
      return false;
    }

    final minLeft = math.min(
      slash.left,
      math.min(upperDot.left, lowerDot.left),
    );
    final maxRight = math.max(
      slash.right,
      math.max(upperDot.right, lowerDot.right),
    );
    final gap1 = slash.left - upperDot.right;
    final gap2 = lowerDot.left - slash.right;
    if (gap1 > lineHeight * 0.30 || gap2 > lineHeight * 0.30) return false;

    return (maxRight - minLeft) <= lineHeight * 1.75;
  }
}
