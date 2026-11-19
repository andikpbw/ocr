import 'package:flutter/widgets.dart';

import '../models/ocr_entity.dart';
import 'ocr_icons.dart';
import 'ocr_theme.dart';

/// Displays automatically extracted [OcrEntity] items as crisp, interactive
/// category-coded pill chips with custom vector icons.
class OcrEntityChips extends StatelessWidget {
  /// Creates an [OcrEntityChips] strip.
  const OcrEntityChips({
    required this.entities,
    this.onEntityTap,
    this.maxVisible,
    this.spacing = 8.0,
    this.runSpacing = 8.0,
    this.theme,
    super.key,
  });

  /// Extracted semantic entities to display.
  final List<OcrEntity> entities;

  /// Callback invoked when the user taps an entity chip.
  final ValueChanged<OcrEntity>? onEntityTap;

  /// Optional cap on the number of chips rendered.
  final int? maxVisible;

  /// Horizontal gap between chips.
  final double spacing;

  /// Vertical gap between wrapped rows.
  final double runSpacing;

  /// Optional theme override; defaults to [OcrTheme.of].
  final OcrThemeData? theme;

  @override
  Widget build(BuildContext context) {
    if (entities.isEmpty) return const SizedBox.shrink();
    final activeTheme = theme ?? OcrTheme.of(context);
    final visible = maxVisible != null && entities.length > maxVisible!
        ? entities.sublist(0, maxVisible!)
        : entities;

    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: visible
          .map((OcrEntity e) => _buildChip(e, activeTheme))
          .toList(growable: false),
    );
  }

  Widget _buildChip(OcrEntity entity, OcrThemeData t) {
    final accent = _accentFor(entity.type, t);
    final icon = _iconFor(entity.type);
    final text = entity.label != null
        ? '${entity.label}: ${entity.value}'
        : entity.value;

    return GestureDetector(
      onTap: onEntityTap != null ? () => onEntityTap!(entity) : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: t.isDark ? 0.14 : 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.42)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OcrIcon(icon, color: accent, size: 13),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 210),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: t.fontFamily,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static OcrIconType _iconFor(OcrEntityType type) {
    switch (type) {
      case OcrEntityType.email:
        return OcrIconType.email;
      case OcrEntityType.url:
        return OcrIconType.link;
      case OcrEntityType.phone:
        return OcrIconType.phone;
      case OcrEntityType.date:
        return OcrIconType.calendar;
      case OcrEntityType.amount:
        return OcrIconType.currency;
      case OcrEntityType.percentage:
        return OcrIconType.percent;
      case OcrEntityType.invoiceNumber:
        return OcrIconType.document;
      case OcrEntityType.cardNumber:
      case OcrEntityType.hashtag:
        return OcrIconType.tag;
      case OcrEntityType.keyValue:
        return OcrIconType.keyValue;
    }
  }

  static Color _accentFor(OcrEntityType type, OcrThemeData t) {
    switch (type) {
      case OcrEntityType.email:
      case OcrEntityType.url:
        return t.accentColor;
      case OcrEntityType.amount:
      case OcrEntityType.percentage:
        return t.highConfidenceColor;
      case OcrEntityType.date:
      case OcrEntityType.invoiceNumber:
        return t.secondaryAccentColor;
      case OcrEntityType.phone:
      case OcrEntityType.cardNumber:
        return t.mediumConfidenceColor;
      case OcrEntityType.hashtag:
      case OcrEntityType.keyValue:
        return t.mutedTextColor;
    }
  }
}
