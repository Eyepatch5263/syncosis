import 'package:flutter/painting.dart';
import 'package:uuid/uuid.dart';

enum MediaType { image, audio, video, text }

class CanvasMedia {
  final String id;
  final MediaType type;
  final String url;
  final Offset position;
  final double width;
  final double height;
  final double rotation; // radians
  final String filename; // Also used for colorHex for text
  final Map<String, dynamic>? metadata;

  const CanvasMedia({
    required this.id,
    required this.type,
    required this.url, // Re-used for text content
    required this.position,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    this.filename = '', // Re-used for colorHex for text
    this.metadata,
  });

  static const _uuid = Uuid();

  factory CanvasMedia.image({
    required String url,
    required Offset position,
    required double width,
    required double height,
    Map<String, dynamic>? metadata,
  }) => CanvasMedia(
        id: _uuid.v4(),
        type: MediaType.image,
        url: url,
        position: position,
        width: width,
        height: height,
        metadata: metadata,
      );

  factory CanvasMedia.audio({
    required String url,
    required Offset position,
    required String filename,
    Map<String, dynamic>? metadata,
  }) {
    final hasQuote = metadata != null && metadata['quote'] != null && metadata['quote'].toString().isNotEmpty;
    // Base audio height is 60. A standard two-line quote adds around 100px of intrinsic height.
    final baseHeight = hasQuote ? 160.0 : 60.0;
    return CanvasMedia(
      id: _uuid.v4(),
      type: MediaType.audio,
      url: url,
      position: position,
      width: 220,
      height: baseHeight,
      filename: filename,
      metadata: metadata,
    );
  }

  factory CanvasMedia.video({
    required String url,
    required Offset position,
    required double width,
    required double height,
    Map<String, dynamic>? metadata,
  }) => CanvasMedia(
        id: _uuid.v4(),
        type: MediaType.video,
        url: url,
        position: position,
        width: width,
        height: height,
        metadata: metadata,
      );

  factory CanvasMedia.text({
    required String text,
    required String colorHex,
    required Offset position,
    Map<String, dynamic>? metadata,
  }) => CanvasMedia(
        id: _uuid.v4(),
        type: MediaType.text,
        url: text, // re-using url
        position: position,
        width: 200, // Default bounding box for scaling
        height: 60,
        filename: colorHex, // re-using filename
        metadata: metadata,
      );

  factory CanvasMedia.fromEventData(Map<String, dynamic> data, MediaType type) =>
      CanvasMedia(
        id: data['id'] as String,
        type: type,
        url: data['url'] as String,
        position: Offset(
          (data['x'] as num).toDouble(),
          (data['y'] as num).toDouble(),
        ),
        width: (data['width'] as num).toDouble(),
        height: (data['height'] as num).toDouble(),
        rotation: (data['rotation'] as num?)?.toDouble() ?? 0.0,
        filename: data['filename'] as String? ?? '',
        metadata: data['metadata'] as Map<String, dynamic>?,
      );

  CanvasMedia copyWith({
    Offset? position,
    double? width,
    double? height,
    double? rotation,
  }) =>
      CanvasMedia(
        id: id,
        type: type,
        url: url,
        position: position ?? this.position,
        width: width ?? this.width,
        height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        filename: filename,
        metadata: metadata,
      );

  Map<String, dynamic> toEventData() => {
        'id': id,
        'url': url,
        'x': position.dx,
        'y': position.dy,
        'width': width,
        'height': height,
        'rotation': rotation,
        'filename': filename,
        if (metadata != null) 'metadata': metadata,
      };
}

