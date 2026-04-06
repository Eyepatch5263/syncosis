import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../models/stroke.dart';

class CanvasPainter extends CustomPainter {
  final ui.Picture? cachedPicture;
  final List<Stroke> activeStrokes;
  final Offset? partnerCursor;

  CanvasPainter({
    required this.cachedPicture,
    required this.activeStrokes,
    this.partnerCursor,
  });

  /// The beautiful quadratic bezier math algorithm abstracted so it can be 
  /// shared by the static PictureRecorder caching engine and the active painter loop.
  static void drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

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
      return;
    }

    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    
    for (int i = 0; i < stroke.points.length - 1; i++) {
      final currentPoint = stroke.points[i];
      final nextPoint = stroke.points[i + 1];
      
      final midPoint = Offset(
        (currentPoint.dx + nextPoint.dx) / 2,
        (currentPoint.dy + nextPoint.dy) / 2,
      );

      if (i == 0) {
        path.lineTo(midPoint.dx, midPoint.dy);
      } else {
        path.quadraticBezierTo(
          currentPoint.dx,
          currentPoint.dy,
          midPoint.dx,
          midPoint.dy,
        );
      }
    }
    
    path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Instantly stamp the baked picture of thousands of strokes (Zero Math overhead)
    if (cachedPicture != null) {
      canvas.drawPicture(cachedPicture!);
    }

    // 2. Perform math dynamically ONLY for the 1 or 2 strokes currently being dragged
    for (final stroke in activeStrokes) {
      drawStroke(canvas, stroke);
    }

    // 3. Draw the active floating partner cursor
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
  bool shouldRepaint(covariant CanvasPainter oldDelegate) => true;
}
