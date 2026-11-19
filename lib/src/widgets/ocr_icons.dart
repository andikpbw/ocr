import 'package:flutter/widgets.dart';

/// Semantic vector icon identifiers painted via [OcrIcon].
enum OcrIconType {
  /// Viewfinder scan frame icon.
  scan,

  /// Document copy icon.
  copy,

  /// Confirmation checkmark icon.
  check,

  /// Envelope email icon.
  email,

  /// Web link icon.
  link,

  /// Telephone handset icon.
  phone,

  /// Calendar date icon.
  calendar,

  /// Currency badge icon.
  currency,

  /// Percentage icon.
  percent,

  /// Document / invoice sheet icon.
  document,

  /// Hashtag / card tag icon.
  tag,

  /// Key-value field icon.
  keyValue,

  /// Overlay layers icon.
  layers,

  /// AI / precision sparkles icon.
  sparkles,
}

/// Lightweight vector icon widget rendered purely via [CustomPainter] with
/// zero dependency on Material or Cupertino icon fonts.
class OcrIcon extends StatelessWidget {
  /// Creates an [OcrIcon].
  const OcrIcon(
    this.type, {
    required this.color,
    this.size = 16.0,
    this.strokeWidth = 1.6,
    super.key,
  });

  /// Icon glyph to paint.
  final OcrIconType type;

  /// Stroke and accent color.
  final Color color;

  /// Square width and height in logical pixels.
  final double size;

  /// Stroke thickness in logical pixels.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _OcrIconPainter(
          type: type,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _OcrIconPainter extends CustomPainter {
  const _OcrIconPainter({
    required this.type,
    required this.color,
    required this.strokeWidth,
  });

  final OcrIconType type;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case OcrIconType.scan:
        final c = w * 0.28;
        final m = w * 0.12;
        // 4 corner brackets + horizontal scan line.
        canvas.drawPath(
          Path()
            ..moveTo(m, m + c)
            ..lineTo(m, m)
            ..lineTo(m + c, m)
            ..moveTo(w - m - c, m)
            ..lineTo(w - m, m)
            ..lineTo(w - m, m + c)
            ..moveTo(w - m, h - m - c)
            ..lineTo(w - m, h - m)
            ..lineTo(w - m - c, h - m)
            ..moveTo(m + c, h - m)
            ..lineTo(m, h - m)
            ..lineTo(m, h - m - c),
          paint,
        );
        canvas.drawLine(Offset(m, h * 0.5), Offset(w - m, h * 0.5), paint);

      case OcrIconType.copy:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.34, h * 0.34, w * 0.52, h * 0.52),
            Radius.circular(w * 0.10),
          ),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.66, h * 0.34)
            ..lineTo(w * 0.66, h * 0.20)
            ..lineTo(w * 0.16, h * 0.20)
            ..lineTo(w * 0.16, h * 0.70)
            ..lineTo(w * 0.34, h * 0.70),
          paint,
        );

      case OcrIconType.check:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.18, h * 0.52)
            ..lineTo(w * 0.42, h * 0.76)
            ..lineTo(w * 0.84, h * 0.26),
          paint,
        );

      case OcrIconType.email:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.12, h * 0.22, w * 0.76, h * 0.56),
            Radius.circular(w * 0.10),
          ),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.16, h * 0.28)
            ..lineTo(w * 0.50, h * 0.54)
            ..lineTo(w * 0.84, h * 0.28),
          paint,
        );

      case OcrIconType.link:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.12, h * 0.34, w * 0.42, h * 0.32),
            Radius.circular(h * 0.16),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.46, h * 0.34, w * 0.42, h * 0.32),
            Radius.circular(h * 0.16),
          ),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.36, h * 0.50),
          Offset(w * 0.64, h * 0.50),
          paint,
        );

      case OcrIconType.phone:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.26, h * 0.12, w * 0.48, h * 0.76),
            Radius.circular(w * 0.12),
          ),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.44, h * 0.74),
          Offset(w * 0.56, h * 0.74),
          paint,
        );

      case OcrIconType.calendar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.14, h * 0.22, w * 0.72, h * 0.64),
            Radius.circular(w * 0.10),
          ),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.14, h * 0.42),
          Offset(w * 0.86, h * 0.42),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.34, h * 0.12),
          Offset(w * 0.34, h * 0.28),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.66, h * 0.12),
          Offset(w * 0.66, h * 0.28),
          paint,
        );

      case OcrIconType.currency:
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.36, paint);
        canvas.drawLine(
          Offset(w * 0.50, h * 0.26),
          Offset(w * 0.50, h * 0.74),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.36, h * 0.40),
          Offset(w * 0.64, h * 0.40),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.36, h * 0.60),
          Offset(w * 0.64, h * 0.60),
          paint,
        );

      case OcrIconType.percent:
        canvas.drawLine(
          Offset(w * 0.76, h * 0.22),
          Offset(w * 0.24, h * 0.78),
          paint,
        );
        canvas.drawCircle(Offset(w * 0.28, h * 0.28), w * 0.11, paint);
        canvas.drawCircle(Offset(w * 0.72, h * 0.72), w * 0.11, paint);

      case OcrIconType.document:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.18, h * 0.12, w * 0.64, h * 0.76),
            Radius.circular(w * 0.10),
          ),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.32, h * 0.38),
          Offset(w * 0.68, h * 0.38),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.32, h * 0.56),
          Offset(w * 0.68, h * 0.56),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.32, h * 0.72),
          Offset(w * 0.54, h * 0.72),
          paint,
        );

      case OcrIconType.tag:
        canvas.drawLine(
          Offset(w * 0.36, h * 0.18),
          Offset(w * 0.28, h * 0.82),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.72, h * 0.18),
          Offset(w * 0.64, h * 0.82),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.18, h * 0.38),
          Offset(w * 0.84, h * 0.38),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.14, h * 0.64),
          Offset(w * 0.80, h * 0.64),
          paint,
        );

      case OcrIconType.keyValue:
        canvas.drawCircle(Offset(w * 0.24, h * 0.32), w * 0.08, paint);
        canvas.drawLine(
          Offset(w * 0.44, h * 0.32),
          Offset(w * 0.84, h * 0.32),
          paint,
        );
        canvas.drawCircle(Offset(w * 0.24, h * 0.68), w * 0.08, paint);
        canvas.drawLine(
          Offset(w * 0.44, h * 0.68),
          Offset(w * 0.84, h * 0.68),
          paint,
        );

      case OcrIconType.layers:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.50, h * 0.16)
            ..lineTo(w * 0.86, h * 0.36)
            ..lineTo(w * 0.50, h * 0.56)
            ..lineTo(w * 0.14, h * 0.36)
            ..close(),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.14, h * 0.60)
            ..lineTo(w * 0.50, h * 0.80)
            ..lineTo(w * 0.86, h * 0.60),
          paint,
        );

      case OcrIconType.sparkles:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.50, h * 0.12)
            ..quadraticBezierTo(w * 0.52, h * 0.48, w * 0.88, h * 0.50)
            ..quadraticBezierTo(w * 0.52, h * 0.52, w * 0.50, h * 0.88)
            ..quadraticBezierTo(w * 0.48, h * 0.52, w * 0.12, h * 0.50)
            ..quadraticBezierTo(w * 0.48, h * 0.48, w * 0.50, h * 0.12)
            ..close(),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_OcrIconPainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
