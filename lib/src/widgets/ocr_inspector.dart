import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/ocr_entity.dart';
import '../models/ocr_result.dart';
import 'ocr_entity_chips.dart';
import 'ocr_icons.dart';
import 'ocr_result_viewer.dart';
import 'ocr_scanner_overlay.dart';
import 'ocr_theme.dart';

/// All-in-one modern OCR Studio widget combining an interactive annotated
/// document viewer, live laser scanner overlay, granularity switcher,
/// telemetry metrics header, structured entity chips, and copyable text output.
///
/// Built 100% on `package:flutter/widgets.dart` (zero Material / Cupertino
/// dependencies).
class OcrInspector extends StatefulWidget {
  /// Creates an [OcrInspector].
  const OcrInspector({
    required this.document,
    this.result,
    this.isScanning = false,
    this.scanProgress,
    this.title = 'OCR Studio',
    this.initialGranularity = OcrOverlayGranularity.words,
    this.selectedRegionIndex,
    this.onEntityTap,
    this.theme,
    super.key,
  });

  /// Source document preview widget (e.g., `Image.memory(...)`).
  final Widget document;

  /// Latest [OcrResult], or `null` while awaiting recognition.
  final OcrResult? result;

  /// Displays the animated [OcrScannerOverlay] laser beam while `true`.
  final bool isScanning;

  /// Optional deterministic scan beam progress in `[0.0, 1.0]`.
  final double? scanProgress;

  /// Header title shown in the inspector toolbar.
  final String title;

  /// Initial bounding-box granularity.
  final OcrOverlayGranularity initialGranularity;

  /// Optional controlled selected region index inside [OcrResultViewer].
  final int? selectedRegionIndex;

  /// Callback fired when a user taps an extracted entity chip.
  final ValueChanged<OcrEntity>? onEntityTap;

  /// Optional theme override; defaults to [OcrTheme.of].
  final OcrThemeData? theme;

  @override
  State<OcrInspector> createState() => _OcrInspectorState();
}

class _OcrInspectorState extends State<OcrInspector> {
  late OcrOverlayGranularity _granularity;
  bool _copiedAll = false;

  @override
  void initState() {
    super.initState();
    _granularity = widget.initialGranularity;
  }

  @override
  void didUpdateWidget(OcrInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGranularity != widget.initialGranularity) {
      _granularity = widget.initialGranularity;
    }
    if (oldWidget.result != widget.result) {
      _copiedAll = false;
    }
  }

  Future<void> _copyFullText() async {
    final text = widget.result?.text ?? '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copiedAll = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? OcrTheme.of(context);
    final res = widget.result;

    return OcrTheme(
      data: theme,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surfaceColor,
          borderRadius: BorderRadius.circular(theme.borderRadius + 4),
          border: Border.all(color: theme.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(theme, res),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints box) {
                    final wide = box.maxWidth >= 620;
                    final viewer = _buildViewerCard(theme, res);
                    final details = _buildDetailsPanel(theme, res);
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(flex: 6, child: viewer),
                          const SizedBox(width: 12),
                          Expanded(flex: 5, child: details),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(flex: 6, child: viewer),
                        const SizedBox(height: 10),
                        Expanded(flex: 5, child: details),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(OcrThemeData theme, OcrResult? res) {
    final confPct = res != null
        ? (res.confidence * 100).toStringAsFixed(1)
        : '--';
    final confColor = res != null
        ? theme.confidenceColor(res.confidence)
        : theme.mutedTextColor;
    final ms = res?.metrics.processingTime.inMilliseconds;

    return Row(
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[theme.accentColor, theme.secondaryAccentColor],
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: OcrIcon(
              OcrIconType.scan,
              color: Color(0xFFFFFFFF),
              size: 15,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: theme.fontFamily,
                  decoration: TextDecoration.none,
                ),
              ),
              Text(
                widget.isScanning
                    ? 'Analyzing typography & layout...'
                    : res != null
                    ? '${res.blocks.length} ${res.blocks.length == 1 ? 'block' : 'blocks'} • '
                          '${res.lines.length} ${res.lines.length == 1 ? 'line' : 'lines'} • '
                          '${res.words.length} ${res.words.length == 1 ? 'word' : 'words'}'
                    : 'Zero-dependency offline OCR engine',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.mutedTextColor,
                  fontSize: 11,
                  fontFamily: theme.fontFamily,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
        if (ms != null) ...<Widget>[
          _metricPill(theme, '${ms}ms', theme.accentColor),
          const SizedBox(width: 6),
        ],
        _metricPill(theme, '$confPct%', confColor),
      ],
    );
  }

  Widget _metricPill(OcrThemeData theme, String label, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: theme.fontFamily,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _buildViewerCard(OcrThemeData theme, OcrResult? res) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panelColor,
        borderRadius: BorderRadius.circular(theme.borderRadius),
        border: Border.all(color: theme.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            OcrResultViewer(
              result: widget.isScanning ? null : res,
              granularity: _granularity,
              selectedIndex: widget.selectedRegionIndex,
              enableZoom: false,
              theme: theme,
              child: widget.document,
            ),
            if (widget.isScanning || widget.scanProgress != null)
              OcrScannerOverlay(
                isScanning: widget.isScanning,
                scanProgress: widget.scanProgress,
                showLiveBoxes: false,
                viewfinderInsets: const EdgeInsets.all(12),
                theme: theme,
              ),
            Positioned(top: 10, right: 10, child: _buildGranularityBar(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildGranularityBar(OcrThemeData theme) {
    const items = <(OcrOverlayGranularity, String)>[
      (OcrOverlayGranularity.blocks, 'Blocks'),
      (OcrOverlayGranularity.lines, 'Lines'),
      (OcrOverlayGranularity.words, 'Words'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panelColor.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: items
              .map(((OcrOverlayGranularity, String) pair) {
                final (mode, label) = pair;
                final active = _granularity == mode;
                return GestureDetector(
                  onTap: () => setState(() => _granularity = mode),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: active
                          ? theme.accentColor.withValues(alpha: 0.22)
                          : const Color(0x00000000),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: active
                              ? theme.accentColor
                              : theme.mutedTextColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: theme.fontFamily,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildDetailsPanel(OcrThemeData theme, OcrResult? res) {
    final entities = res?.entities ?? const <OcrEntity>[];
    final recognizedText = res?.text ?? '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panelColor,
        borderRadius: BorderRadius.circular(theme.borderRadius),
        border: Border.all(color: theme.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                OcrIcon(
                  OcrIconType.document,
                  color: theme.accentColor,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Extracted Text',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: theme.fontFamily,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: recognizedText.isNotEmpty ? _copyFullText : null,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.accentColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          OcrIcon(
                            _copiedAll ? OcrIconType.check : OcrIconType.copy,
                            color: _copiedAll
                                ? theme.highConfidenceColor
                                : theme.accentColor,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copiedAll ? 'Copied' : 'Copy',
                            style: TextStyle(
                              color: _copiedAll
                                  ? theme.highConfidenceColor
                                  : theme.accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFamily: theme.fontFamily,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.surfaceColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.borderColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    child: Text(
                      recognizedText.isNotEmpty
                          ? recognizedText
                          : (widget.isScanning
                                ? 'Scanning optical glyphs...'
                                : 'No text recognized yet.'),
                      style: TextStyle(
                        color: recognizedText.isNotEmpty
                            ? theme.textColor
                            : theme.mutedTextColor,
                        fontSize: 12,
                        height: 1.5,
                        fontFamily: theme.fontFamily,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (entities.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  OcrIcon(
                    OcrIconType.sparkles,
                    color: theme.secondaryAccentColor,
                    size: 13,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Detected Entities (${entities.length})',
                    style: TextStyle(
                      color: theme.mutedTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: theme.fontFamily,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              OcrEntityChips(
                entities: entities,
                maxVisible: 6,
                spacing: 6,
                runSpacing: 6,
                onEntityTap: widget.onEntityTap,
                theme: theme,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
