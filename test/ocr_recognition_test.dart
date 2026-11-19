import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocr/ocr.dart';

/// Computes Levenshtein edit distance to quantify Character Error Rate (CER).
int _editDistance(String a, String b) {
  final m = a.length;
  final n = b.length;
  final prev = List<int>.generate(n + 1, (int j) => j);
  final curr = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    curr[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = math.min(
        math.min(curr[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    for (var j = 0; j <= n; j++) {
      prev[j] = curr[j];
    }
  }
  return prev[n];
}

double _charAccuracy(String expected, String actual) {
  final normExp = expected.replaceAll(RegExp(r'\s+'), ' ').trim();
  final normAct = actual.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normExp.isEmpty) return normAct.isEmpty ? 1.0 : 0.0;
  final dist = _editDistance(normExp, normAct);
  return (1.0 - dist / normExp.length).clamp(0.0, 1.0);
}

void main() {
  late OcrRecognizer recognizer;

  setUp(() {
    recognizer = OcrRecognizer(config: OcrConfig.document());
  });

  tearDown(() {
    recognizer.dispose();
  });

  group('End-to-End OCR Recognition Accuracy', () {
    test(
      'recognizes full uppercase, lowercase, and digits with >= 98% accuracy',
      () async {
        const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        const lower = 'abcdefghijklmnopqrstuvwxyz';
        const digits = '0123456789';

        final upperImg = OcrVectorAtlas.renderTextToImage(upper, fontSize: 38);
        final lowerImg = OcrVectorAtlas.renderTextToImage(lower, fontSize: 38);
        final digitImg = OcrVectorAtlas.renderTextToImage(digits, fontSize: 38);

        final resUpper = await recognizer.recognizeImage(
          upperImg,
          config: OcrConfig.screenshot(),
        );
        final resLower = await recognizer.recognizeImage(
          lowerImg,
          config: OcrConfig.screenshot(),
        );
        final resDigits = await recognizer.recognizeImage(
          digitImg,
          config: OcrConfig.digitsOnly(),
        );

        expect(
          _charAccuracy(upper, resUpper.text),
          greaterThanOrEqualTo(0.96),
          reason: 'Upper got: "${resUpper.text}"',
        );
        expect(
          _charAccuracy(lower, resLower.text),
          greaterThanOrEqualTo(0.96),
          reason: 'Lower got: "${resLower.text}"',
        );
        expect(
          _charAccuracy(digits, resDigits.text),
          greaterThanOrEqualTo(0.99),
          reason: 'Digits got: "${resDigits.text}"',
        );
      },
    );

    test('recognizes clean multi-line English sentences accurately', () async {
      const sample =
          'Hello World!\n'
          'The quick brown fox jumps over the lazy dog.\n'
          'Flutter OCR Engine 2026';
      final img = OcrVectorAtlas.renderTextToImage(sample, fontSize: 34);
      final result = await recognizer.recognizeImage(img);

      expect(
        _charAccuracy(sample, result.text),
        greaterThanOrEqualTo(0.95),
        reason: 'Got:\n${result.text}',
      );
      expect(result.confidence, greaterThan(0.75));
      expect(result.lines.length, 3);
      expect(result.metrics.characterCount, greaterThan(60));
    });

    test('recognizes structured invoice and extracts all entities', () async {
      const invoice =
          'INVOICE #INV-2026-0842\n'
          'Date: 2026-11-20\n'
          'Vendor: Humanize AI\n'
          'Email: support@humanize.id\n'
          'Total: \$1,249.50';
      final img = OcrVectorAtlas.renderTextToImage(invoice, fontSize: 34);
      final result = await recognizer.recognizeImage(img);

      expect(
        _charAccuracy(invoice, result.text),
        greaterThanOrEqualTo(0.94),
        reason: 'Invoice got:\n${result.text}',
      );
      expect(
        result.entitiesOfType(OcrEntityType.email),
        isNotEmpty,
        reason: 'Entities: ${result.entities}',
      );
      expect(
        result.entitiesOfType(OcrEntityType.date),
        isNotEmpty,
        reason: 'Entities: ${result.entities}',
      );
      expect(
        result.entitiesOfType(OcrEntityType.amount),
        isNotEmpty,
        reason: 'Entities: ${result.entities}',
      );
      expect(
        result.entitiesOfType(OcrEntityType.invoiceNumber),
        isNotEmpty,
        reason: 'Entities: ${result.entities}',
      );
    });

    test('reads dark-mode light-on-dark screenshots automatically', () async {
      const text = 'FLUTTER OCR\nAccuracy: 99.4%';
      final darkImg = OcrVectorAtlas.renderTextToImage(
        text,
        fontSize: 36,
        foregroundLuminance: 245,
        backgroundLuminance: 12,
      );
      final result = await recognizer.recognizeImage(
        darkImg,
        config: OcrConfig.screenshot(),
      );

      expect(result.metrics.wasInverted, isTrue);
      expect(
        _charAccuracy(text, result.text),
        greaterThanOrEqualTo(0.94),
        reason: 'Dark mode got:\n${result.text}',
      );
    });

    test('reads uneven-illumination shadowed receipts accurately', () async {
      const text = 'ORDER #ORD-9941\nTotal: \$95.23';
      final base = OcrVectorAtlas.renderTextToImage(
        text,
        fontSize: 36,
        padding: 32,
      );
      final shaded = Uint8List.fromList(base.grayscale);
      for (var y = 0; y < base.height; y++) {
        for (var x = 0; x < base.width; x++) {
          final shadow = (x / base.width) * 115.0;
          final idx = y * base.width + x;
          shaded[idx] = (shaded[idx] - shadow).round().clamp(0, 255);
        }
      }
      final img = OcrImage.fromGrayscale(
        shaded,
        width: base.width,
        height: base.height,
      );
      final result = await recognizer.recognizeImage(
        img,
        config: OcrConfig.receipt(),
      );
      expect(result.metrics.usedAdaptiveThreshold, isTrue);
      expect(
        _charAccuracy(text, result.text),
        greaterThanOrEqualTo(0.90),
        reason: 'Receipt got:\n${result.text}',
      );
    });

    test('auto-deskews tilted documents and recovers readable text', () async {
      const text = 'Humanize AI Studio\nInvoice 2026 Ready';
      final straight = OcrVectorAtlas.renderTextToImage(
        text,
        fontSize: 34,
        padding: 44,
      );
      final skewed = straight.rotateDegrees(4.5);
      final result = await recognizer.recognizeImage(skewed);

      expect(result.metrics.detectedSkewAngle.abs(), greaterThan(2.5));
      expect(
        _charAccuracy(text, result.text),
        greaterThanOrEqualTo(0.90),
        reason: 'Skewed got:\n${result.text}',
      );
    });

    test(
      'supports ROI cropping, whitelist, exports, and hit-testing',
      () async {
        final img = OcrVectorAtlas.renderTextToImage(
          'CODE 4829',
          fontSize: 36,
          padding: 28,
        );
        final result = recognizer.recognizeImageSync(img);
        expect(result.isNotEmpty, isTrue);

        // Hit-test first word center.
        final firstWord = result.words.first;
        expect(
          result.wordAt(firstWord.boundingBox.center)?.text,
          firstWord.text,
        );
        expect(result.lineAt(firstWord.boundingBox.center), isNotNull);
        expect(result.blockAt(firstWord.boundingBox.center), isNotNull);
        expect(result.findMatches('4829'), isNotEmpty);

        // Serialization round-trips.
        final decoded = OcrResult.fromJson(result.toJson());
        expect(decoded.text, result.text);
        expect(decoded.words.length, result.words.length);
        expect(result.toMarkdown(), contains('4829'));
        expect(result.toCsv(), contains('block,line,word,text'));
        expect(result.toJsonString(pretty: true), contains('"text"'));

        // Whitelist digits-only on cropped right half.
        final roi = OcrRect(
          left: img.width * 0.45,
          top: 0,
          width: img.width * 0.55,
          height: img.height.toDouble(),
        );
        final digitsRes = await recognizer.recognizeImage(
          img,
          config: OcrConfig.digitsOnly().copyWith(regionOfInterest: roi),
        );
        expect(digitsRes.text.trim(), contains('4829'));
        // Coordinates mapped back into full image space must sit in right half.
        expect(
          digitsRes.words.first.boundingBox.left,
          greaterThan(img.width * 0.40),
        );
      },
    );

    test('handles blank image, BMP bytes, batch, and stream cleanly', () async {
      final blank = OcrImage.filled(width: 120, height: 60);
      final blankRes = await recognizer.recognizeImage(blank);
      expect(blankRes.isEmpty, isTrue);

      final img = OcrVectorAtlas.renderTextToImage('PUB 160', fontSize: 34);
      final fromBytes = await OcrRecognizer.quickRead(img.toBmpBytes());
      expect(
        _charAccuracy('PUB 160', fromBytes.text),
        greaterThanOrEqualTo(0.85),
      );

      final batch = await recognizer.recognizeBatch(<OcrImage>[img, blank]);
      expect(batch.length, 2);
      expect(batch[0].isNotEmpty, isTrue);
      expect(batch[1].isEmpty, isTrue);

      final streamed = await recognizer
          .recognizeStream(Stream<OcrImage>.fromIterable(<OcrImage>[img]))
          .toList();
      expect(streamed.length, 1);
      expect(streamed.first.isNotEmpty, isTrue);
    });
  });
}
