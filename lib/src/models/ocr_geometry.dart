import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// A two-dimensional point in OCR image pixel coordinates.
@immutable
class OcrPoint {
  /// Creates an [OcrPoint] at ([x], [y]).
  const OcrPoint(this.x, this.y);

  /// Creates an [OcrPoint] from a JSON map.
  factory OcrPoint.fromJson(Map<String, Object?> json) {
    return OcrPoint(
      (json['x']! as num).toDouble(),
      (json['y']! as num).toDouble(),
    );
  }

  /// Creates an [OcrPoint] from a Flutter [ui.Offset].
  factory OcrPoint.fromOffset(ui.Offset offset) =>
      OcrPoint(offset.dx, offset.dy);

  /// The horizontal coordinate in pixels.
  final double x;

  /// The vertical coordinate in pixels.
  final double y;

  /// Computes the Euclidean distance from this point to [other].
  double distanceTo(OcrPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Returns a translated copy shifted by ([dx], [dy]).
  OcrPoint translate(double dx, double dy) => OcrPoint(x + dx, y + dy);

  /// Returns a scaled copy multiplied by [scaleX] and [scaleY].
  OcrPoint scale(double scaleX, [double? scaleY]) =>
      OcrPoint(x * scaleX, y * (scaleY ?? scaleX));

  /// Converts this point to a Flutter [ui.Offset].
  ui.Offset toOffset() => ui.Offset(x, y);

  /// Serializes this point to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'OcrPoint(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// An axis-aligned bounding rectangle in OCR image pixel coordinates.
@immutable
class OcrRect {
  /// Creates an [OcrRect] from its origin ([left], [top]) and size.
  const OcrRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(width >= 0, 'width must be non-negative'),
       assert(height >= 0, 'height must be non-negative');

  /// Creates an [OcrRect] from left, top, right, and bottom coordinates.
  factory OcrRect.fromLTRB(
    double left,
    double top,
    double right,
    double bottom,
  ) {
    final minX = math.min(left, right);
    final minY = math.min(top, bottom);
    final maxX = math.max(left, right);
    final maxY = math.max(top, bottom);
    return OcrRect(
      left: minX,
      top: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  /// Creates an [OcrRect] from a Flutter [ui.Rect].
  factory OcrRect.fromRect(ui.Rect rect) => OcrRect(
    left: rect.left,
    top: rect.top,
    width: math.max(0.0, rect.width),
    height: math.max(0.0, rect.height),
  );

  /// Creates an [OcrRect] from a JSON map.
  factory OcrRect.fromJson(Map<String, Object?> json) {
    return OcrRect(
      left: (json['left']! as num).toDouble(),
      top: (json['top']! as num).toDouble(),
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
    );
  }

  /// An empty rectangle positioned at the origin.
  static const OcrRect zero = OcrRect(left: 0, top: 0, width: 0, height: 0);

  /// The left edge coordinate in pixels.
  final double left;

  /// The top edge coordinate in pixels.
  final double top;

  /// The width in pixels.
  final double width;

  /// The height in pixels.
  final double height;

  /// The right edge coordinate (`left + width`).
  double get right => left + width;

  /// The bottom edge coordinate (`top + height`).
  double get bottom => top + height;

  /// The geometric center of this rectangle.
  OcrPoint get center => OcrPoint(left + width / 2, top + height / 2);

  /// The area (`width * height`) in square pixels.
  double get area => width * height;

  /// The aspect ratio (`width / height`), or `0` if [height] is zero.
  double get aspectRatio => height > 0 ? width / height : 0;

  /// Whether this rectangle has zero width or zero height.
  bool get isEmpty => width <= 0 || height <= 0;

  /// Returns `true` if [point] lies within or on the boundary of this rectangle.
  bool containsPoint(OcrPoint point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  /// Returns `true` if this rectangle overlaps [other].
  bool intersects(OcrRect other) =>
      left < other.right &&
      right > other.left &&
      top < other.bottom &&
      bottom > other.top;

  /// Returns the smallest rectangle containing both this and [other].
  OcrRect union(OcrRect other) {
    if (isEmpty) return other;
    if (other.isEmpty) return this;
    return OcrRect.fromLTRB(
      math.min(left, other.left),
      math.min(top, other.top),
      math.max(right, other.right),
      math.max(bottom, other.bottom),
    );
  }

  /// Returns the overlapping region between this and [other], or [OcrRect.zero].
  OcrRect intersection(OcrRect other) {
    final iLeft = math.max(left, other.left);
    final iTop = math.max(top, other.top);
    final iRight = math.min(right, other.right);
    final iBottom = math.min(bottom, other.bottom);
    if (iRight <= iLeft || iBottom <= iTop) return OcrRect.zero;
    return OcrRect.fromLTRB(iLeft, iTop, iRight, iBottom);
  }

  /// Computes the Intersection-over-Union (IoU) ratio with [other] in `[0, 1]`.
  double intersectionOverUnion(OcrRect other) {
    final interArea = intersection(other).area;
    if (interArea <= 0) return 0;
    final unionArea = area + other.area - interArea;
    return unionArea > 0 ? interArea / unionArea : 0;
  }

  /// Returns a rectangle expanded by [delta] on all four sides.
  OcrRect inflate(double delta) {
    final newW = math.max(0.0, width + delta * 2);
    final newH = math.max(0.0, height + delta * 2);
    return OcrRect(
      left: left - delta,
      top: top - delta,
      width: newW,
      height: newH,
    );
  }

  /// Returns a rectangle translated by ([dx], [dy]).
  OcrRect translate(double dx, double dy) =>
      OcrRect(left: left + dx, top: top + dy, width: width, height: height);

  /// Returns a rectangle scaled by [scaleX] and [scaleY].
  OcrRect scale(double scaleX, [double? scaleY]) {
    final sy = scaleY ?? scaleX;
    return OcrRect(
      left: left * scaleX,
      top: top * sy,
      width: width * scaleX,
      height: height * sy,
    );
  }

  /// Clamps this rectangle to stay within `[0, maxWidth] x [0, maxHeight]`.
  OcrRect clampToBounds(double maxWidth, double maxHeight) {
    final l = left.clamp(0.0, maxWidth);
    final t = top.clamp(0.0, maxHeight);
    final r = right.clamp(0.0, maxWidth);
    final b = bottom.clamp(0.0, maxHeight);
    return OcrRect.fromLTRB(l, t, r, b);
  }

  /// Converts this rectangle to a 4-corner clockwise [OcrPolygon].
  OcrPolygon toPolygon() => OcrPolygon(<OcrPoint>[
    OcrPoint(left, top),
    OcrPoint(right, top),
    OcrPoint(right, bottom),
    OcrPoint(left, bottom),
  ]);

  /// Converts this rectangle to a Flutter [ui.Rect].
  ui.Rect toRect() => ui.Rect.fromLTWH(left, top, width, height);

  /// Serializes this rectangle to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrRect &&
          other.left == left &&
          other.top == top &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'OcrRect(${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)}x${height.toStringAsFixed(1)})';
}

/// An ordered sequence of vertices outlining a detected text region.
@immutable
class OcrPolygon {
  /// Creates an [OcrPolygon] from [points].
  OcrPolygon(List<OcrPoint> points)
    : points = List<OcrPoint>.unmodifiable(points);

  /// Creates an [OcrPolygon] from a JSON list of point maps.
  factory OcrPolygon.fromJson(List<Object?> json) {
    return OcrPolygon(
      json
          .map((Object? e) => OcrPoint.fromJson(e! as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  /// The ordered vertices of the polygon.
  final List<OcrPoint> points;

  /// Computes the tight axis-aligned bounding box of all vertices.
  OcrRect get boundingBox {
    if (points.isEmpty) return OcrRect.zero;
    var minX = points.first.x;
    var minY = points.first.y;
    var maxX = minX;
    var maxY = minY;
    for (var i = 1; i < points.length; i++) {
      final p = points[i];
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return OcrRect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Returns a scaled copy of this polygon.
  OcrPolygon scale(double scaleX, [double? scaleY]) => OcrPolygon(
    points.map((OcrPoint p) => p.scale(scaleX, scaleY)).toList(growable: false),
  );

  /// Serializes this polygon to a JSON-compatible list.
  List<Map<String, Object?>> toJson() =>
      points.map((OcrPoint p) => p.toJson()).toList(growable: false);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrPolygon && listEquals(other.points, points);

  @override
  int get hashCode => Object.hashAll(points);
}
