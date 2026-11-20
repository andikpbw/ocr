import 'package:flutter_ocr/flutter_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrPoint', () {
    test('distance, translate, scale, and JSON round-trip', () {
      const a = OcrPoint(3, 4);
      const b = OcrPoint(6, 8);
      expect(a.distanceTo(b), closeTo(5.0, 1e-6));
      expect(a.translate(2, -1), equals(const OcrPoint(5, 3)));
      expect(a.scale(2, 3), equals(const OcrPoint(6, 12)));
      expect(OcrPoint.fromJson(a.toJson()), equals(a));
      expect(OcrPoint.fromOffset(a.toOffset()), equals(a));
    });
  });

  group('OcrRect', () {
    test('geometry properties, union, intersection, IoU, and clamp', () {
      const r1 = OcrRect(left: 10, top: 20, width: 40, height: 20);
      const r2 = OcrRect(left: 30, top: 20, width: 40, height: 20);

      expect(r1.right, 50);
      expect(r1.bottom, 40);
      expect(r1.center, const OcrPoint(30, 30));
      expect(r1.area, 800);
      expect(r1.aspectRatio, 2.0);
      expect(r1.containsPoint(const OcrPoint(25, 30)), isTrue);
      expect(r1.containsPoint(const OcrPoint(5, 30)), isFalse);
      expect(r1.intersects(r2), isTrue);

      final u = r1.union(r2);
      expect(u, const OcrRect(left: 10, top: 20, width: 60, height: 20));

      final inter = r1.intersection(r2);
      expect(inter, const OcrRect(left: 30, top: 20, width: 20, height: 20));
      expect(r1.intersectionOverUnion(r2), closeTo(400 / 1200, 1e-6));

      final clamped = const OcrRect(
        left: -5,
        top: 5,
        width: 100,
        height: 100,
      ).clampToBounds(50, 40);
      expect(clamped, const OcrRect(left: 0, top: 5, width: 50, height: 35));

      expect(OcrRect.fromJson(r1.toJson()), equals(r1));
      expect(OcrRect.fromRect(r1.toRect()), equals(r1));
    });
  });

  group('OcrPolygon', () {
    test('boundingBox, scale, and JSON round-trip', () {
      const rect = OcrRect(left: 5, top: 10, width: 30, height: 15);
      final poly = rect.toPolygon();
      expect(poly.points.length, 4);
      expect(poly.boundingBox, equals(rect));
      expect(poly.scale(2).boundingBox, equals(rect.scale(2)));
      expect(OcrPolygon.fromJson(poly.toJson()), equals(poly));
    });
  });
}
