import 'package:flutter_ocr/flutter_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrEntityExtractor', () {
    test(
      'extracts emails, URLs, phones, dates, amounts, percentages, invoices, cards, hashtags, and key-values',
      () {
        const doc = '''
Invoice: INV-2026-0842
Date: 2026-11-20
Support: hello@humanize.id
Website: https://humanize.id
Phone: +62 812-3456-7890
Card: **** **** **** 4242
Discount: 15.5%
Total: \$1,249.50
Tag: #FlutterOCR
''';
        final lines = doc
            .trim()
            .split('\n')
            .asMap()
            .entries
            .map(
              (MapEntry<int, String> e) => OcrLine(
                text: e.value,
                boundingBox: OcrRect(
                  left: 0,
                  top: e.key * 30.0,
                  width: 300,
                  height: 24,
                ),
                confidence: 0.96,
                words: e.value
                    .split(' ')
                    .map(
                      (String w) => OcrWord(
                        text: w,
                        boundingBox: OcrRect(
                          left: 0,
                          top: e.key * 30.0,
                          width: 60,
                          height: 24,
                        ),
                        confidence: 0.96,
                        characters: const <OcrCharacter>[],
                      ),
                    )
                    .toList(growable: false),
              ),
            )
            .toList(growable: false);

        final words = lines
            .expand((OcrLine l) => l.words)
            .toList(growable: false);
        final entities = OcrEntityExtractor.extract(
          fullText: doc,
          words: words,
          lines: lines,
        );

        OcrEntity? firstOf(OcrEntityType t) {
          for (final e in entities) {
            if (e.type == t) return e;
          }
          return null;
        }

        expect(firstOf(OcrEntityType.invoiceNumber)?.value, 'INV-2026-0842');
        expect(firstOf(OcrEntityType.date)?.value, '2026-11-20');
        expect(firstOf(OcrEntityType.email)?.value, 'hello@humanize.id');
        expect(firstOf(OcrEntityType.url)?.value, 'https://humanize.id');
        expect(firstOf(OcrEntityType.phone)?.value, contains('812-3456-7890'));
        expect(firstOf(OcrEntityType.cardNumber)?.value, '**** **** **** 4242');
        expect(firstOf(OcrEntityType.percentage)?.value, '15.5%');
        expect(firstOf(OcrEntityType.amount)?.value, r'$1,249.50');
        expect(firstOf(OcrEntityType.hashtag)?.value, '#FlutterOCR');

        final kvs = entities
            .where((OcrEntity e) => e.type == OcrEntityType.keyValue)
            .toList();
        expect(
          kvs.any(
            (OcrEntity e) => e.label == 'Total' && e.value == r'$1,249.50',
          ),
          isTrue,
        );

        // JSON round-trip check.
        for (final entity in entities) {
          expect(OcrEntity.fromJson(entity.toJson()), equals(entity));
        }
      },
    );
  });
}
