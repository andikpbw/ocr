import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/ocr_result.dart';
import 'ocr_icons.dart';
import 'ocr_theme.dart';

/// Modern animated document & camera OCR viewfinder overlay.
///
/// Renders glowing corner brackets, a smooth luminous laser scan beam, live
/// status telemetry pill, and optional real-time bounding boxes mapped to the
/// viewport. Built exclusively with `package:flutter/widgets.dart`.
class OcrScannerOverlay extends StatefulWidget {
  /// Creates an [OcrScannerOverlay].
  const OcrScannerOverlay({
    this.isScanning = true,
    this.scanProgress,
    this.result,
    this.statusLabel,
    this.viewfinderInsets = const EdgeInsets.all(20),
    this.showScrim = false,
    this.showLiveBoxes = true,
    this.beamDuration = const Duration(milliseconds: 2100),
    this.theme,
    super.key,
  });

  /// Whether the laser scan beam animation is actively running.
  final bool isScanning;

  /// Optional explicit scan progress in `[0.0, 1.0]` overriding the internal
  /// animation loop (useful for deterministic frame rendering and tests).
  final double? scanProgress;

  /// Optional live [OcrResult] whose detected lines are highlighted inside the
  /// scanning frame.
  final OcrResult? result;

  /// Optional status badge label displayed at the bottom of the viewfinder.
  final String? statusLabel;

  /// Padding between the outer widget bounds and the viewfinder bracket frame.
  final EdgeInsets viewfinderInsets;

  /// Whether to dim the area outside the viewfinder frame.
  final bool showScrim;

  /// Whether to paint live detected word bounding boxes from [result].
  final bool showLiveBoxes;

  /// Duration of one top-to-bottom laser sweep cycle.
  final Duration beamDuration;

  /// Optional theme override; defaults to [OcrTheme.of].
  final OcrThemeData? theme;

  @override
  State<OcrScannerOverlay> createState() => _OcrScannerOverlayState();
}

class _OcrScannerOverlayState extends State<OcrScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.beamDuration,
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(OcrScannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beamDuration != widget.beamDuration) {
      _controller.duration = widget.beamDuration;
    }
    if (oldWidget.isScanning != widget.isScanning ||
        oldWidget.scanProgress != widget.scanProgress) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.scanProgress != null) {
      _controller.stop();
      _controller.value = widget.scanProgress!.clamp(0.0, 1.0);
    } else if (widget.isScanning) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? OcrTheme.of(context);
    final label =
        widget.statusLabel ??
        (widget.isScanning
            ? 'Scanning document...'
            : widget.result != null
            ? '${widget.result!.words.length} words • '
                  '${(widget.result!.confidence * 100).toStringAsFixed(1)}%'
            : 'Ready to scan');

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              final progress = widget.scanProgress ?? _controller.value;
              return CustomPaint(
                painter: _ScannerOverlayPainter(
                  theme: theme,
                  progress: progress,
                  isScanning: widget.isScanning,
                  insets: widget.viewfinderInsets,
                  showScrim: widget.showScrim,
                  result: widget.showLiveBoxes ? widget.result : null,
                ),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: math.max(10.0, widget.viewfinderInsets.bottom + 10.0),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.panelColor.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: theme.accentColor.withValues(alpha: 0.45),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      OcrIcon(
                        widget.isScanning
                            ? OcrIconType.scan
                            : OcrIconType.sparkles,
                        color: widget.isScanning
                            ? theme.accentColor
                            : theme.highConfidenceColor,
                        size: 13,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        label,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          fontFamily: theme.fontFamily,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({
    required this.theme,
    required this.progress,
    required this.isScanning,
    required this.insets,
    required this.showScrim,
    required this.result,
  });

  final OcrThemeData theme;
  final double progress;
  final bool isScanning;
  final EdgeInsets insets;
  final bool showScrim;
  final OcrResult? result;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTRB(
      insets.left,
      insets.top,
      math.max(insets.left + 24, size.width - insets.right),
      math.max(insets.top + 24, size.height - insets.bottom),
    );
    final frameRRect = RRect.fromRectAndRadius(
      frame,
      const Radius.circular(14),
    );

    if (showScrim) {
      final scrimPath = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(frameRRect);
      canvas.drawPath(scrimPath, Paint()..color = theme.scrimColor);
    }

    // Subtle hairline guide border around the scan region.
    canvas.drawRRect(
      frameRRect,
      Paint()
        ..color = theme.accentColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Optional live detected word polygons clipped to the frame.
    if (result != null && result!.imageWidth > 0 && result!.imageHeight > 0) {
      final scale = math.min(
        size.width / result!.imageWidth,
        size.height / result!.imageHeight,
      );
      final drawW = result!.imageWidth * scale;
      final drawH = result!.imageHeight * scale;
      final ox = (size.width - drawW) * 0.5;
      final oy = (size.height - drawH) * 0.5;

      for (final word in result!.words) {
        final b = word.boundingBox;
        final rect = Rect.fromLTWH(
          ox + b.left * scale,
          oy + b.top * scale,
          b.width * scale,
          b.height * scale,
        );
        final c = theme.confidenceColor(word.confidence);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = c.withValues(alpha: 0.14),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()
            ..color = c.withValues(alpha: 0.78)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }

    // Animated laser beam sweep with soft luminous wake.
    if (isScanning) {
      final beamY = frame.top + 10 + (frame.height - 20) * progress;
      final glowHeight = math.min(54.0, frame.height * 0.24);
      final glowRect = Rect.fromLTRB(
        frame.left + 6,
        math.max(frame.top + 4, beamY - glowHeight),
        frame.right - 6,
        beamY,
      );
      final glowPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            theme.accentColor.withValues(alpha: 0.0),
            theme.accentColor.withValues(alpha: 0.26),
          ],
        ).createShader(glowRect);
      canvas.drawRect(glowRect, glowPaint);

      // Core laser beam line with soft bloom.
      canvas.drawLine(
        Offset(frame.left + 8, beamY),
        Offset(frame.right - 8, beamY),
        Paint()
          ..color = theme.accentColor.withValues(alpha: 0.45)
          ..strokeWidth = 5.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );
      canvas.drawLine(
        Offset(frame.left + 6, beamY),
        Offset(frame.right - 6, beamY),
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              theme.accentColor.withValues(alpha: 0.15),
              theme.accentColor,
              theme.secondaryAccentColor,
              theme.accentColor,
              theme.accentColor.withValues(alpha: 0.15),
            ],
          ).createShader(Rect.fromLTWH(frame.left, beamY - 1, frame.width, 2))
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Crisp luminous corner brackets.
    final cornerLen = math.min(
      theme.cornerLength,
      math.min(frame.width, frame.height) * 0.24,
    );
    const r = 12.0;
    final bracketPaint = Paint()
      ..color = theme.accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = theme.cornerStrokeWidth
      ..strokeCap = StrokeCap.round;

    final glowBracketPaint = Paint()
      ..color = theme.accentColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = theme.cornerStrokeWidth + 3.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);

    final corners = Path()
      // Top-left
      ..moveTo(frame.left, frame.top + cornerLen)
      ..lineTo(frame.left, frame.top + r)
      ..quadraticBezierTo(frame.left, frame.top, frame.left + r, frame.top)
      ..lineTo(frame.left + cornerLen, frame.top)
      // Top-right
      ..moveTo(frame.right - cornerLen, frame.top)
      ..lineTo(frame.right - r, frame.top)
      ..quadraticBezierTo(frame.right, frame.top, frame.right, frame.top + r)
      ..lineTo(frame.right, frame.top + cornerLen)
      // Bottom-right
      ..moveTo(frame.right, frame.bottom - cornerLen)
      ..lineTo(frame.right, frame.bottom - r)
      ..quadraticBezierTo(
        frame.right,
        frame.bottom,
        frame.right - r,
        frame.bottom,
      )
      ..lineTo(frame.right - cornerLen, frame.bottom)
      // Bottom-left
      ..moveTo(frame.left + cornerLen, frame.bottom)
      ..lineTo(frame.left + r, frame.bottom)
      ..quadraticBezierTo(
        frame.left,
        frame.bottom,
        frame.left,
        frame.bottom - r,
      )
      ..lineTo(frame.left, frame.bottom - cornerLen);

    canvas.drawPath(corners, glowBracketPaint);
    canvas.drawPath(corners, bracketPaint);
  }

  @override
  bool shouldRepaint(_ScannerOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isScanning != isScanning ||
      oldDelegate.theme != theme ||
      oldDelegate.result != result ||
      oldDelegate.showScrim != showScrim;
}
