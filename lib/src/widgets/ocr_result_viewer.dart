import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/ocr_geometry.dart';
import '../models/ocr_result.dart';
import 'ocr_icons.dart';
import 'ocr_theme.dart';

/// Granularity level of bounding boxes rendered over a recognized image.
enum OcrOverlayGranularity {
  /// Draw paragraph/column block outlines.
  blocks,

  /// Draw text line outlines.
  lines,

  /// Draw individual word outlines.
  words,

  /// Draw individual character glyph outlines.
  characters,

  /// Hide bounding box overlays while keeping the document visible.
  none,
}

/// Interactive document viewer rendering an image (or custom document [child])
/// alongside clickable, confidence-colored OCR bounding boxes, floating
/// inspection tooltips, one-tap clipboard copy, and pan/zoom support.
class OcrResultViewer extends StatefulWidget {
  /// Creates an [OcrResultViewer].
  const OcrResultViewer({
    required this.child,
    this.result,
    this.granularity = OcrOverlayGranularity.words,
    this.showConfidenceBadges = true,
    this.enableZoom = true,
    this.selectedIndex,
    this.onRegionSelected,
    this.theme,
    super.key,
  });

  /// The source document widget (for example, `Image.memory(...)` or a
  /// rendered preview widget) matching `result.imageWidth x result.imageHeight`.
  final Widget child;

  /// OCR recognition result whose bounding boxes will be overlaid.
  final OcrResult? result;

  /// Active overlay granularity (`blocks`, `lines`, `words`, `characters`, or `none`).
  final OcrOverlayGranularity granularity;

  /// Whether to render compact percentage badges on hovered/selected boxes.
  final bool showConfidenceBadges;

  /// Enables pinch-to-zoom and drag panning via [InteractiveViewer].
  final bool enableZoom;

  /// Optional controlled selected region index for programmatic highlighting.
  final int? selectedIndex;

  /// Callback invoked whenever the user taps a detected text region.
  final void Function(String text, OcrRect boundingBox, double confidence)?
  onRegionSelected;

  /// Optional theme override; defaults to [OcrTheme.of].
  final OcrThemeData? theme;

  @override
  State<OcrResultViewer> createState() => _OcrResultViewerState();
}

class _OcrResultViewerState extends State<OcrResultViewer> {
  int? _internalSelectedIndex;
  int? _hoveredIndex;
  bool _copied = false;

  int? get _activeIndex => widget.selectedIndex ?? _internalSelectedIndex;

  @override
  void didUpdateWidget(OcrResultViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result != widget.result ||
        oldWidget.granularity != widget.granularity) {
      _internalSelectedIndex = null;
      _hoveredIndex = null;
      _copied = false;
    }
  }

  List<_OverlayRegion> _buildRegions() {
    final res = widget.result;
    if (res == null || widget.granularity == OcrOverlayGranularity.none) {
      return const <_OverlayRegion>[];
    }
    switch (widget.granularity) {
      case OcrOverlayGranularity.blocks:
        return res.blocks
            .map(
              (OcrBlock b) =>
                  _OverlayRegion(b.text, b.boundingBox, b.confidence),
            )
            .toList(growable: false);
      case OcrOverlayGranularity.lines:
        return res.lines
            .map(
              (OcrLine l) =>
                  _OverlayRegion(l.text, l.boundingBox, l.confidence),
            )
            .toList(growable: false);
      case OcrOverlayGranularity.words:
        return res.words
            .map(
              (OcrWord w) =>
                  _OverlayRegion(w.text, w.boundingBox, w.confidence),
            )
            .toList(growable: false);
      case OcrOverlayGranularity.characters:
        return res.characters
            .map(
              (OcrCharacter c) =>
                  _OverlayRegion(c.text, c.boundingBox, c.confidence),
            )
            .toList(growable: false);
      case OcrOverlayGranularity.none:
        return const <_OverlayRegion>[];
    }
  }

  int? _hitTest(
    Offset localPosition,
    Size viewportSize,
    List<_OverlayRegion> regions,
  ) {
    final res = widget.result;
    if (res == null ||
        res.imageWidth <= 0 ||
        res.imageHeight <= 0 ||
        regions.isEmpty) {
      return null;
    }
    final metrics = _computeLayout(
      viewportSize,
      res.imageWidth.toDouble(),
      res.imageHeight.toDouble(),
    );
    final imgX = (localPosition.dx - metrics.offsetX) / metrics.scale;
    final imgY = (localPosition.dy - metrics.offsetY) / metrics.scale;
    final pt = OcrPoint(imgX, imgY);

    for (var i = 0; i < regions.length; i++) {
      if (regions[i].rect.inflate(4).containsPoint(pt)) {
        return i;
      }
    }
    return null;
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? OcrTheme.of(context);
    final regions = _buildRegions();
    final res = widget.result;

    Widget content = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final imgW = (res?.imageWidth ?? 0) > 0
            ? res!.imageWidth.toDouble()
            : size.width;
        final imgH = (res?.imageHeight ?? 0) > 0
            ? res!.imageHeight.toDouble()
            : size.height;
        final layout = _computeLayout(size, imgW, imgH);
        final selIdx = _activeIndex;
        final validSelected =
            selIdx != null && selIdx >= 0 && selIdx < regions.length
            ? regions[selIdx]
            : null;

        return MouseRegion(
          onHover: (PointerHoverEvent event) {
            final idx = _hitTest(event.localPosition, size, regions);
            if (idx != _hoveredIndex) {
              setState(() => _hoveredIndex = idx);
            }
          },
          onExit: (_) {
            if (_hoveredIndex != null) {
              setState(() => _hoveredIndex = null);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (TapUpDetails details) {
              final idx = _hitTest(details.localPosition, size, regions);
              setState(() {
                _internalSelectedIndex = idx;
                _copied = false;
              });
              if (idx != null) {
                final reg = regions[idx];
                widget.onRegionSelected?.call(
                  reg.text,
                  reg.rect,
                  reg.confidence,
                );
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned(
                  left: layout.offsetX,
                  top: layout.offsetY,
                  width: layout.drawWidth,
                  height: layout.drawHeight,
                  child: widget.child,
                ),
                if (regions.isNotEmpty &&
                    res != null &&
                    res.imageWidth > 0 &&
                    res.imageHeight > 0)
                  CustomPaint(
                    painter: _ResultOverlayPainter(
                      regions: regions,
                      layout: layout,
                      theme: theme,
                      selectedIndex: selIdx,
                      hoveredIndex: _hoveredIndex,
                      showConfidenceBadges: widget.showConfidenceBadges,
                    ),
                  ),
                if (validSelected != null)
                  _buildSelectionTooltip(
                    theme: theme,
                    region: validSelected,
                    layout: layout,
                    viewport: size,
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (widget.enableZoom) {
      content = InteractiveViewer(minScale: 1.0, maxScale: 4.0, child: content);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(theme.borderRadius),
      child: ColoredBox(color: theme.surfaceColor, child: content),
    );
  }

  Widget _buildSelectionTooltip({
    required OcrThemeData theme,
    required _OverlayRegion region,
    required _ViewportLayout layout,
    required Size viewport,
  }) {
    final screenLeft = layout.offsetX + region.rect.left * layout.scale;
    final screenTop = layout.offsetY + region.rect.top * layout.scale;
    final screenBottom = layout.offsetY + region.rect.bottom * layout.scale;

    final placeAbove = screenTop > 56;
    final top = placeAbove
        ? math.max(8.0, screenTop - 44)
        : math.min(viewport.height - 46, screenBottom + 8);
    final left = screenLeft
        .clamp(8.0, math.max(8.0, viewport.width - 230))
        .toDouble();
    final confColor = theme.confidenceColor(region.confidence);

    return Positioned(
      left: left,
      top: top,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.panelColor.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: confColor.withValues(alpha: 0.65)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  region.text.replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: theme.fontFamily,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  child: Text(
                    '${(region.confidence * 100).round()}%',
                    style: TextStyle(
                      color: confColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: theme.fontFamily,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _copyText(region.text),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: OcrIcon(
                    _copied ? OcrIconType.check : OcrIconType.copy,
                    color: _copied
                        ? theme.highConfidenceColor
                        : theme.mutedTextColor,
                    size: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _ViewportLayout _computeLayout(
    Size viewport,
    double imageWidth,
    double imageHeight,
  ) {
    if (viewport.width <= 0 ||
        viewport.height <= 0 ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      return const _ViewportLayout(1, 0, 0, 0, 0);
    }
    final scale = math.min(
      viewport.width / imageWidth,
      viewport.height / imageHeight,
    );
    final drawW = imageWidth * scale;
    final drawH = imageHeight * scale;
    return _ViewportLayout(
      scale,
      (viewport.width - drawW) * 0.5,
      (viewport.height - drawH) * 0.5,
      drawW,
      drawH,
    );
  }
}

class _OverlayRegion {
  const _OverlayRegion(this.text, this.rect, this.confidence);
  final String text;
  final OcrRect rect;
  final double confidence;
}

class _ViewportLayout {
  const _ViewportLayout(
    this.scale,
    this.offsetX,
    this.offsetY,
    this.drawWidth,
    this.drawHeight,
  );
  final double scale;
  final double offsetX;
  final double offsetY;
  final double drawWidth;
  final double drawHeight;
}

class _ResultOverlayPainter extends CustomPainter {
  const _ResultOverlayPainter({
    required this.regions,
    required this.layout,
    required this.theme,
    required this.selectedIndex,
    required this.hoveredIndex,
    required this.showConfidenceBadges,
  });

  final List<_OverlayRegion> regions;
  final _ViewportLayout layout;
  final OcrThemeData theme;
  final int? selectedIndex;
  final int? hoveredIndex;
  final bool showConfidenceBadges;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < regions.length; i++) {
      final reg = regions[i];
      final isSelected = i == selectedIndex;
      final isHovered = i == hoveredIndex;
      final rect = Rect.fromLTWH(
        layout.offsetX + reg.rect.left * layout.scale,
        layout.offsetY + reg.rect.top * layout.scale,
        math.max(2.0, reg.rect.width * layout.scale),
        math.max(2.0, reg.rect.height * layout.scale),
      );
      final color = isSelected
          ? theme.accentColor
          : theme.confidenceColor(reg.confidence);
      final rrect = RRect.fromRectAndRadius(
        rect.inflate(isSelected ? 2.0 : 1.0),
        const Radius.circular(4),
      );

      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(
            alpha: isSelected ? 0.24 : (isHovered ? 0.18 : 0.10),
          ),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(
            alpha: isSelected ? 1.0 : (isHovered ? 0.92 : 0.72),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected
              ? theme.boxStrokeWidth + 0.9
              : theme.boxStrokeWidth,
      );

      if (showConfidenceBadges && isSelected) {
        // Luminous corner handles on the active selection.
        final dotPaint = Paint()..color = theme.accentColor;
        canvas.drawCircle(rrect.outerRect.topLeft, 3.0, dotPaint);
        canvas.drawCircle(rrect.outerRect.topRight, 3.0, dotPaint);
        canvas.drawCircle(rrect.outerRect.bottomLeft, 3.0, dotPaint);
        canvas.drawCircle(rrect.outerRect.bottomRight, 3.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ResultOverlayPainter oldDelegate) =>
      oldDelegate.regions != regions ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.hoveredIndex != hoveredIndex ||
      oldDelegate.theme != theme ||
      oldDelegate.showConfidenceBadges != showConfidenceBadges;
}
