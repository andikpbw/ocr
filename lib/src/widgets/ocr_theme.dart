import 'package:flutter/widgets.dart';

/// Visual styling configuration for all `ocr` UI widgets.
///
/// Built exclusively on `package:flutter/widgets.dart` with zero Material or
/// Cupertino dependencies for seamless compatibility with Flutter 3.47+ and
/// Flutter 3.50+.
@immutable
class OcrThemeData {
  /// Creates a custom [OcrThemeData].
  const OcrThemeData({
    required this.name,
    required this.isDark,
    required this.surfaceColor,
    required this.panelColor,
    required this.borderColor,
    required this.accentColor,
    required this.secondaryAccentColor,
    required this.textColor,
    required this.mutedTextColor,
    required this.highConfidenceColor,
    required this.mediumConfidenceColor,
    required this.lowConfidenceColor,
    required this.scrimColor,
    this.borderRadius = 16.0,
    this.boxStrokeWidth = 1.6,
    this.cornerLength = 26.0,
    this.cornerStrokeWidth = 3.2,
    this.fontFamily,
  });

  /// Deep midnight slate theme with luminous electric cyan & emerald accents.
  factory OcrThemeData.midnight() => const OcrThemeData(
    name: 'Midnight',
    isDark: true,
    surfaceColor: Color(0xFF070D1B),
    panelColor: Color(0xFF0F172A),
    borderColor: Color(0xFF1E293B),
    accentColor: Color(0xFF38BDF8),
    secondaryAccentColor: Color(0xFF818CF8),
    textColor: Color(0xFFF8FAFC),
    mutedTextColor: Color(0xFF94A3B8),
    highConfidenceColor: Color(0xFF34D399),
    mediumConfidenceColor: Color(0xFFFBBF24),
    lowConfidenceColor: Color(0xFFFB7185),
    scrimColor: Color(0x8A020617),
  );

  /// Ultra-modern violet-indigo aurora theme with neon lavender & rose accents.
  factory OcrThemeData.aurora() => const OcrThemeData(
    name: 'Aurora',
    isDark: true,
    surfaceColor: Color(0xFF0D0A1A),
    panelColor: Color(0xFF17122B),
    borderColor: Color(0xFF2D244D),
    accentColor: Color(0xFFA78BFA),
    secondaryAccentColor: Color(0xFFF472B6),
    textColor: Color(0xFFF5F3FF),
    mutedTextColor: Color(0xFFA5B4FC),
    highConfidenceColor: Color(0xFF2DD4BF),
    mediumConfidenceColor: Color(0xFFFCD34D),
    lowConfidenceColor: Color(0xFFFB7185),
    scrimColor: Color(0x8A090614),
  );

  /// Precision dark emerald studio theme with crisp mint & amber highlights.
  factory OcrThemeData.emerald() => const OcrThemeData(
    name: 'Emerald',
    isDark: true,
    surfaceColor: Color(0xFF051310),
    panelColor: Color(0xFF0B221C),
    borderColor: Color(0xFF164035),
    accentColor: Color(0xFF10B981),
    secondaryAccentColor: Color(0xFFFBBF24),
    textColor: Color(0xFFECFDF5),
    mutedTextColor: Color(0xFF6EE7B7),
    highConfidenceColor: Color(0xFF34D399),
    mediumConfidenceColor: Color(0xFFFBBF24),
    lowConfidenceColor: Color(0xFFF87171),
    scrimColor: Color(0x8A030D0A),
  );

  /// Clean daylight studio theme for crisp light-mode applications.
  factory OcrThemeData.daylight() => const OcrThemeData(
    name: 'Daylight',
    isDark: false,
    surfaceColor: Color(0xFFF8FAFC),
    panelColor: Color(0xFFFFFFFF),
    borderColor: Color(0xFFE2E8F0),
    accentColor: Color(0xFF2563EB),
    secondaryAccentColor: Color(0xFF7C3AED),
    textColor: Color(0xFF0F172A),
    mutedTextColor: Color(0xFF64748B),
    highConfidenceColor: Color(0xFF059669),
    mediumConfidenceColor: Color(0xFFD97706),
    lowConfidenceColor: Color(0xFFE11D48),
    scrimColor: Color(0x660F172A),
  );

  /// Human-readable theme name.
  final String name;

  /// Whether this theme uses dark surfaces.
  final bool isDark;

  /// Outer workspace background color.
  final Color surfaceColor;

  /// Elevated card / panel background color.
  final Color panelColor;

  /// Subtle hairline border color for cards and dividers.
  final Color borderColor;

  /// Primary luminous accent used for laser beams, corners, and active tabs.
  final Color accentColor;

  /// Secondary accent used for gradients and subtle highlights.
  final Color secondaryAccentColor;

  /// Primary high-contrast foreground text color.
  final Color textColor;

  /// Secondary label and metadata text color.
  final Color mutedTextColor;

  /// Indicator color for high recognition confidence (`>= 0.85`).
  final Color highConfidenceColor;

  /// Indicator color for moderate recognition confidence (`0.65 .. 0.85`).
  final Color mediumConfidenceColor;

  /// Indicator color for low recognition confidence (`< 0.65`).
  final Color lowConfidenceColor;

  /// Semi-transparent viewfinder scrim outside the scanning frame.
  final Color scrimColor;

  /// Standard panel corner radius in logical pixels.
  final double borderRadius;

  /// Stroke width for detected text bounding boxes.
  final double boxStrokeWidth;

  /// Arm length of animated viewfinder corner brackets.
  final double cornerLength;

  /// Stroke width of viewfinder corner brackets.
  final double cornerStrokeWidth;

  /// Optional custom font family applied across OCR UI labels.
  final String? fontFamily;

  /// Returns the semantic color corresponding to [confidence] in `[0, 1]`.
  Color confidenceColor(double confidence) {
    if (confidence >= 0.85) return highConfidenceColor;
    if (confidence >= 0.65) return mediumConfidenceColor;
    return lowConfidenceColor;
  }

  /// Creates a copy with selectively overridden theme attributes.
  OcrThemeData copyWith({
    String? name,
    bool? isDark,
    Color? surfaceColor,
    Color? panelColor,
    Color? borderColor,
    Color? accentColor,
    Color? secondaryAccentColor,
    Color? textColor,
    Color? mutedTextColor,
    Color? highConfidenceColor,
    Color? mediumConfidenceColor,
    Color? lowConfidenceColor,
    Color? scrimColor,
    double? borderRadius,
    double? boxStrokeWidth,
    double? cornerLength,
    double? cornerStrokeWidth,
    String? fontFamily,
  }) {
    return OcrThemeData(
      name: name ?? this.name,
      isDark: isDark ?? this.isDark,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      panelColor: panelColor ?? this.panelColor,
      borderColor: borderColor ?? this.borderColor,
      accentColor: accentColor ?? this.accentColor,
      secondaryAccentColor: secondaryAccentColor ?? this.secondaryAccentColor,
      textColor: textColor ?? this.textColor,
      mutedTextColor: mutedTextColor ?? this.mutedTextColor,
      highConfidenceColor: highConfidenceColor ?? this.highConfidenceColor,
      mediumConfidenceColor:
          mediumConfidenceColor ?? this.mediumConfidenceColor,
      lowConfidenceColor: lowConfidenceColor ?? this.lowConfidenceColor,
      scrimColor: scrimColor ?? this.scrimColor,
      borderRadius: borderRadius ?? this.borderRadius,
      boxStrokeWidth: boxStrokeWidth ?? this.boxStrokeWidth,
      cornerLength: cornerLength ?? this.cornerLength,
      cornerStrokeWidth: cornerStrokeWidth ?? this.cornerStrokeWidth,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

/// Inherited theme provider propagating an [OcrThemeData] down the widget tree.
class OcrTheme extends InheritedWidget {
  /// Wraps [child] with [data].
  const OcrTheme({required this.data, required super.child, super.key});

  /// Active theme configuration.
  final OcrThemeData data;

  /// Returns the nearest ancestor [OcrThemeData], falling back to
  /// [OcrThemeData.midnight] when none is present.
  static OcrThemeData of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<OcrTheme>();
    return inherited?.data ?? OcrThemeData.midnight();
  }

  @override
  bool updateShouldNotify(OcrTheme oldWidget) => oldWidget.data != data;
}
