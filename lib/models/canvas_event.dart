abstract final class CanvasEventType {
  static const sessionReady = 'SESSION_READY';
  static const drawStart = 'DRAW_START';
  static const drawMove = 'DRAW_MOVE';
  static const drawEnd = 'DRAW_END';
  static const cursorMove = 'CURSOR_MOVE';
  static const clearCanvas = 'CLEAR_CANVAS';
  static const userLeft = 'USER_LEFT';
  static const canvasImage = 'CANVAS_IMAGE';
  static const canvasAudio = 'CANVAS_AUDIO';
  static const canvasVideo = 'CANVAS_VIDEO';
  static const canvasText = 'CANVAS_TEXT';
  static const canvasItemMoved = 'CANVAS_ITEM_MOVED';
  static const eraseStroke = 'ERASE_STROKE';
  static const removeCanvasItem = 'REMOVE_CANVAS_ITEM';
}

class CanvasEvent {
  final String type;
  final Map<String, dynamic> data;

  CanvasEvent({required this.type, required this.data});

  Map<String, dynamic> toJson() => {'type': type, ...data};

  factory CanvasEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final data = Map<String, dynamic>.from(json)
      ..remove('type')
      ..remove('sender_id');
    return CanvasEvent(type: type, data: data);
  }
}
