import 'dart:ui';

class Stroke {
  final String id;
  final List<Offset> points;
  final Color color;
  final double width;
  final String userId; // Track who drew this
  final bool isLocal;

  Stroke({
    required this.id,
    required this.points,
    required this.color,
    required this.width,
    required this.userId,
    required this.isLocal,
  });
}
