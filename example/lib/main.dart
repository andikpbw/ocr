import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_ocr/flutter_ocr.dart';

void main() {
  runApp(const OcrExampleApp());
}

/// Interactive Flutter OCR Studio example built purely with
/// `package:flutter/widgets.dart` and `package:flutter_ocr/flutter_ocr.dart`.
class OcrExampleApp extends StatelessWidget {
  /// Creates the [OcrExampleApp].
  const OcrExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'OCR Studio',
      color: const Color(0xFF070D1B),
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
            settings: settings,
            pageBuilder:
                (
                  BuildContext context,
                  Animation<double> animation,
                  Animation<double> secondaryAnimation,
                ) => builder(context),
          ),
      home: const OcrDemoPage(),
    );
  }
}

/// Interactive OCR demonstration page supporting live scanning, sample
/// switching, and all four built-in themes.
class OcrDemoPage extends StatefulWidget {
  /// Creates an [OcrDemoPage].
  const OcrDemoPage({super.key});

  @override
  State<OcrDemoPage> createState() => _OcrDemoPageState();
}

class _OcrDemoPageState extends State<OcrDemoPage> {
  final OcrRecognizer _recognizer = OcrRecognizer(config: OcrConfig.document());

  final List<OcrThemeData> _themes = <OcrThemeData>[
    OcrThemeData.midnight(),
    OcrThemeData.aurora(),
    OcrThemeData.emerald(),
    OcrThemeData.daylight(),
  ];

  final List<_SampleDocument> _samples = const <_SampleDocument>[
    _SampleDocument(
      title: 'Invoice',
      darkBackground: false,
      text:
          'INVOICE #INV-2026-0842\n'
          'Date: 2026-11-20\n'
          'Vendor: Humanize AI\n'
          'Email: support@humanize.id\n'
          'Total: \$1,249.50',
    ),
    _SampleDocument(
      title: 'Dark UI',
      darkBackground: true,
      text:
          'FLUTTER OCR ENGINE\n'
          'Accuracy: 99.4%\n'
          'Web: https://humanize.id\n'
          'Status: ONLINE 2026',
    ),
    _SampleDocument(
      title: 'Receipt',
      darkBackground: false,
      text:
          'ORDER #ORD-9941\n'
          'Items: 3x Cloud Pro\n'
          'Subtotal: \$89.00\n'
          'Total: \$95.23',
    ),
  ];

  int _themeIndex = 0;
  int _sampleIndex = 0;
  bool _isScanning = false;
  Uint8List? _previewBmp;
  OcrResult? _result;

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  Future<void> _runScan() async {
    final sample = _samples[_sampleIndex];
    final image = OcrVectorAtlas.renderTextToImage(
      sample.text,
      fontSize: 32,
      padding: 28,
      foregroundLuminance: sample.darkBackground ? 242 : 18,
      backgroundLuminance: sample.darkBackground ? 16 : 250,
    );
    final bmp = image.toBmpBytes();

    setState(() {
      _previewBmp = bmp;
      _isScanning = true;
    });

    final result = await _recognizer.recognizeImage(
      image,
      config: sample.darkBackground
          ? OcrConfig.screenshot()
          : OcrConfig.document(),
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themes[_themeIndex];
    return ColoredBox(
      color: theme.surfaceColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildToolbar(theme),
              const SizedBox(height: 12),
              Expanded(
                child: OcrInspector(
                  title: 'OCR Studio — ${_samples[_sampleIndex].title}',
                  theme: theme,
                  isScanning: _isScanning,
                  result: _result,
                  document: _previewBmp != null
                      ? Image.memory(
                          _previewBmp!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(OcrThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(_samples.length, (int i) {
            final active = i == _sampleIndex;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () {
                  setState(() => _sampleIndex = i);
                  _runScan();
                },
                child: _pill(theme, label: _samples[i].title, active: active),
              ),
            );
          }),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(_themes.length, (int i) {
            final active = i == _themeIndex;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => setState(() => _themeIndex = i),
                child: _pill(theme, label: _themes[i].name, active: active),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _pill(
    OcrThemeData theme, {
    required String label,
    required bool active,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active
            ? theme.accentColor.withValues(alpha: 0.20)
            : theme.panelColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? theme.accentColor : theme.borderColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: active ? theme.accentColor : theme.mutedTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _SampleDocument {
  const _SampleDocument({
    required this.title,
    required this.text,
    required this.darkBackground,
  });

  final String title;
  final String text;
  final bool darkBackground;
}
