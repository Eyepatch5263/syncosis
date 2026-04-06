import 'package:flutter/material.dart';

import '../models/stroke.dart';

class CanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Offset? partnerCursor;

  CanvasPainter({required this.strokes, this.partnerCursor});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first,
          stroke.width / 2,
          Paint()..color = stroke.color..style = PaintingStyle.fill,
        );
        continue;
      }

      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    // Partner cursor: coral circle
    if (partnerCursor != null) {
      canvas.drawCircle(
        partnerCursor!,
        8,
        Paint()..color = const Color(0xFFE85D5D).withAlpha(180),
      );
      canvas.drawCircle(
        partnerCursor!,
        8,
        Paint()
          ..color = const Color(0xFFE85D5D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) => true;
}
