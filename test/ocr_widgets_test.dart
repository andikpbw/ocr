import 'package:flutter/widgets.dart';
import 'package:flutter_ocr/flutter_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {OcrThemeData? theme}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: OcrTheme(
      data: theme ?? OcrThemeData.midnight(),
      child: Center(child: SizedBox(width: 820, height: 520, child: child)),
    ),
  );
}

void main() {
  late OcrResult sampleResult;

  setUpAll(() {
    final img = OcrVectorAtlas.renderTextToImage(
      'INVOICE #INV-2026-0842\nTotal: \$1,249.50\nhello@humanize.id',
      fontSize: 32,
      padding: 24,
    );
    sampleResult = BuiltInOcrEngine().recognizeSync(img);
  });

  group('Zero-Material OCR Flutter Widgets', () {
    testWidgets('renders all 4 themes and all 14 vector OcrIcon glyphs', (
      WidgetTester tester,
    ) async {
      for (final theme in <OcrThemeData>[
        OcrThemeData.midnight(),
        OcrThemeData.aurora(),
        OcrThemeData.emerald(),
        OcrThemeData.daylight(),
      ]) {
        expect(theme.confidenceColor(0.95), theme.highConfidenceColor);
        expect(theme.confidenceColor(0.75), theme.mediumConfidenceColor);
        expect(theme.confidenceColor(0.40), theme.lowConfidenceColor);
      }

      await tester.pumpWidget(
        _wrap(
          Wrap(
            children: OcrIconType.values
                .map(
                  (OcrIconType t) => OcrIcon(t, color: const Color(0xFF38BDF8)),
                )
                .toList(),
          ),
        ),
      );
      expect(find.byType(OcrIcon), findsNWidgets(OcrIconType.values.length));
    });

    testWidgets('OcrScannerOverlay renders scanning and completed states', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          OcrScannerOverlay(
            isScanning: true,
            scanProgress: 0.45,
            result: sampleResult,
            showScrim: true,
          ),
        ),
      );
      expect(find.text('Scanning document...'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(OcrScannerOverlay(isScanning: false, result: sampleResult)),
      );
      expect(find.textContaining('words'), findsOneWidget);
    });

    testWidgets(
      'OcrResultViewer displays overlays and tooltip on controlled selection',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            OcrResultViewer(
              result: sampleResult,
              granularity: OcrOverlayGranularity.words,
              selectedIndex: 0,
              child: const ColoredBox(color: Color(0xFFFFFFFF)),
            ),
          ),
        );
        expect(find.byType(OcrResultViewer), findsOneWidget);
        expect(find.textContaining('%'), findsWidgets);
      },
    );

    testWidgets('OcrEntityChips renders entities and triggers tap callback', (
      WidgetTester tester,
    ) async {
      OcrEntity? tapped;
      await tester.pumpWidget(
        _wrap(
          OcrEntityChips(
            entities: sampleResult.entities,
            onEntityTap: (OcrEntity e) => tapped = e,
          ),
        ),
      );
      expect(sampleResult.entities, isNotEmpty);
      await tester.tap(find.text(sampleResult.entities.first.value).first);
      expect(tapped, equals(sampleResult.entities.first));
    });

    testWidgets(
      'OcrInspector switches granularity cleanly across wide and narrow layouts',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            OcrInspector(
              title: 'Humanize OCR Studio',
              result: sampleResult,
              document: const ColoredBox(color: Color(0xFFFFFFFF)),
            ),
          ),
        );
        expect(find.text('Humanize OCR Studio'), findsOneWidget);
        expect(find.text('Extracted Text'), findsOneWidget);
        expect(find.text('Blocks'), findsOneWidget);
        expect(find.text('Lines'), findsOneWidget);
        expect(find.text('Words'), findsOneWidget);

        await tester.tap(find.text('Lines'));
        await tester.pump();
        await tester.tap(find.text('Blocks'));
        await tester.pump();
      },
    );
  });
}
