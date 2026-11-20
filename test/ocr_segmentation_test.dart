import 'dart:typed_data';

import 'package:flutter_ocr/flutter_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrCcl & OcrLayoutAnalyzer', () {
    test(
      'extracts connected components and merges multi-part glyphs (i, j, !, ?, :, =)',
      () {
        final img = OcrVectorAtlas.renderTextToImage(
          'Hi! is it? a:b = 10%',
          fontSize: 36,
          padding: 24,
        );
        final pre = OcrPreprocessor.process(
          img,
          config: const OcrPreprocessConfig(autoDeskew: false),
        );
        final blobs = OcrCcl.extractComponents(
          pre.binary,
          width: pre.width,
          height: pre.height,
        );
        final blocks = OcrLayoutAnalyzer.segment(
          blobs,
          mode: OcrPageSegmentationMode.auto,
        );

        expect(blocks.length, 1);
        expect(blocks.first.lines.length, 1);
        final words = blocks.first.lines.first.words;
        // Words: "Hi!", "is", "it?", "a:b", "=", "10%" -> 6 words
        expect(words.length, 6);
        expect(words[0].glyphs.length, 3); // H, i, !
        expect(words[1].glyphs.length, 2); // i, s
        expect(words[2].glyphs.length, 3); // i, t, ?
        expect(words[3].glyphs.length, 3); // a, :, b
        expect(words[4].glyphs.length, 1); // =
        expect(words[5].glyphs.length, 3); // 1, 0, %
      },
    );

    test('segments multi-line and multi-paragraph blocks in reading order', () {
      final img = OcrVectorAtlas.renderTextToImage(
        'Line One\nLine Two\n\n\nParagraph Two',
        fontSize: 30,
        padding: 24,
      );
      final pre = OcrPreprocessor.process(
        img,
        config: const OcrPreprocessConfig(autoDeskew: false),
      );
      final blobs = OcrCcl.extractComponents(
        pre.binary,
        width: pre.width,
        height: pre.height,
      );
      final blocks = OcrLayoutAnalyzer.segment(
        blobs,
        mode: OcrPageSegmentationMode.auto,
      );

      expect(blocks.length, 2);
      expect(blocks[0].lines.length, 2);
      expect(blocks[1].lines.length, 1);
      expect(blocks[0].boundingBox.bottom, lessThan(blocks[1].boundingBox.top));
    });

    test('splits touching glyphs along vertical projection valleys', () {
      // Construct two solid 12x28 bars bridged by a thin 1px pixel bridge at middle.
      const w = 44;
      const h = 28;
      final mask = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < 18; x++) {
          mask[y * w + x] = 1;
        }
        for (var x = 26; x < 44; x++) {
          mask[y * w + x] = 1;
        }
      }
      // 1-pixel touching bridge between the two blobs.
      for (var x = 18; x < 26; x++) {
        mask[14 * w + x] = 1;
      }

      final blob = OcrGlyphBlob(
        left: 10,
        top: 10,
        width: w,
        height: h,
        pixelCount: mask.fold<int>(0, (int s, int v) => s + v),
        mask: mask,
      );
      final split = OcrGlyphSplitter.splitTouchingBlobs(<OcrGlyphBlob>[
        blob,
      ], estimatedLineHeight: 28);
      expect(split.length, 2);
      expect(split[0].right, lessThan(split[1].left));
    });
  });
}
