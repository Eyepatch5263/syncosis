import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/canvas_event.dart';
import '../models/canvas_media.dart';
import '../models/stroke.dart';
import '../painters/canvas_painter.dart';
import 'widget_service.dart';

enum SyncState { disconnected, connecting, waitingForPartner, connected, partnerLeft }

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  SyncState syncState = SyncState.disconnected;

  final List<Stroke> strokes = [];
  final Map<String, Stroke> _activeStrokesMap = {};
  
  // Undo/Redo Engine
  final List<Stroke> undoStack = [];
  bool get canUndo => strokes.any((s) => s.isLocal);
  bool get canRedo => undoStack.isNotEmpty;

  // Expose isolated lists for the Painter optimization
  List<Stroke> get activeStrokes => _activeStrokesMap.values.toList();
  Picture? cachedStrokesPicture;

  final List<CanvasMedia> canvasItems = [];
  Offset? partnerCursor;

  final _uuid = const Uuid();
  String? _currentStrokeId;
  String? _sessionCode;
  bool _intentionalDisconnect = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  static const String _serverHost = 'syncosis-server-b075827ce03d.herokuapp.com';

  void connect(String sessionCode) {
    _sessionCode = sessionCode;
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;
    _connectInternal(sessionCode);
  }

  void _connectInternal(String sessionCode) {
    syncState = SyncState.connecting;
    notifyListeners();

    _channel = WebSocketChannel.connect(
      Uri.parse('wss://$_serverHost/ws?session=$sessionCode'),
    );

    syncState = SyncState.waitingForPartner;
    notifyListeners();

    _channel!.stream.listen(
      _handleMessage,
      onError: (_) => _onDisconnect(),
      onDone: _onDisconnect,
    );
  }

  void _handleMessage(dynamic raw) {
    final json = jsonDecode(raw as String) as Map<String, dynamic>;
    final event = CanvasEvent.fromJson(json);

    switch (event.type) {
      case CanvasEventType.sessionReady:
        _reconnectAttempts = 0;
        syncState = SyncState.connected;
        notifyListeners();

      case CanvasEventType.drawStart:
        _onPartnerDrawStart(event.data);

      case CanvasEventType.drawMove:
        _onPartnerDrawMove(event.data);

      case CanvasEventType.drawEnd:
        _activeStrokesMap.remove(event.data['id'] as String);
        _rebuildStrokeCache();
        _tryUpdateWidget();

      case CanvasEventType.cursorMove:
        final next = _offsetFromData(event.data);
        if (next == partnerCursor) return;
        partnerCursor = next;
        notifyListeners();

      case CanvasEventType.clearCanvas:
        _clearLocal();
        _tryUpdateWidget();

      case CanvasEventType.userLeft:
        syncState = SyncState.partnerLeft;
        notifyListeners();
        _tryUpdateWidget();

      case CanvasEventType.canvasImage:
        canvasItems.add(CanvasMedia.fromEventData(event.data, MediaType.image));
        notifyListeners();
        _tryUpdateWidget();

      case CanvasEventType.canvasAudio:
        canvasItems.add(CanvasMedia.fromEventData(event.data, MediaType.audio));
        notifyListeners();
        _tryUpdateWidget();

      case CanvasEventType.canvasVideo:
        canvasItems.add(CanvasMedia.fromEventData(event.data, MediaType.video));
        notifyListeners();
        _tryUpdateWidget();

      case CanvasEventType.canvasText:
        canvasItems.add(CanvasMedia.fromEventData(event.data, MediaType.text));
        notifyListeners();
        _tryUpdateWidget();

      case CanvasEventType.eraseStroke:
        final id = event.data['id'] as String;
        strokes.removeWhere((s) => s.id == id);
        _rebuildStrokeCache();
        _tryUpdateWidget();

      case CanvasEventType.removeCanvasItem:
        final id = event.data['id'] as String;
        canvasItems.removeWhere((m) => m.id == id);
        notifyListeners();
        _tryUpdateWidget();

      case CanvasEventType.canvasItemMoved:
        final id = event.data['id'] as String;
        final idx = canvasItems.indexWhere((m) => m.id == id);
        if (idx == -1) return;
        canvasItems[idx] = canvasItems[idx].copyWith(
          position: Offset(
            (event.data['x'] as num).toDouble(),
            (event.data['y'] as num).toDouble(),
          ),
          width: event.data['width'] != null
              ? (event.data['width'] as num).toDouble()
              : null,
          height: event.data['height'] != null
              ? (event.data['height'] as num).toDouble()
              : null,
          rotation: event.data['rotation'] != null
              ? (event.data['rotation'] as num).toDouble()
              : null,
        );
        notifyListeners();
        _tryUpdateWidget();
    }
  }

  /// Bakes all completed strokes into a single static hardware-accelerated 
  /// Picture object to bypass expensive looping math in the UI thread.
  void _rebuildStrokeCache() {
    if (strokes.isEmpty) {
      cachedStrokesPicture = null;
      notifyListeners();
      return;
    }

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    for (final stroke in strokes) {
      // Skip strokes currently being drawn actively
      if (_activeStrokesMap.containsKey(stroke.id)) continue;
      CanvasPainter.drawStroke(canvas, stroke);
    }

    cachedStrokesPicture = recorder.endRecording();
    notifyListeners();
  }

  Timer? _widgetUpdateTimer;
  bool _widgetUpdatePending = false;

  void _tryUpdateWidget({bool throttle = false}) {
    if (!throttle) {
      _widgetUpdateTimer?.cancel();
      _widgetUpdateTimer = null;
      _widgetUpdatePending = false;
      WidgetService.update(
        strokes: strokes,
        mediaItems: canvasItems,
      );
      return;
    }

    if (_widgetUpdateTimer != null && _widgetUpdateTimer!.isActive) {
      _widgetUpdatePending = true;
      return;
    }

    WidgetService.update(
      strokes: strokes,
      mediaItems: canvasItems,
    );
    
    _widgetUpdateTimer = Timer(const Duration(milliseconds: 2000), () {
      if (_widgetUpdatePending) {
        _widgetUpdatePending = false;
        WidgetService.update(
          strokes: strokes,
          mediaItems: canvasItems,
        );
      }
    });
  }

  void _onPartnerDrawStart(Map<String, dynamic> data) {
    final stroke = Stroke(
      id: data['id'] as String,
      points: [_offsetFromData(data)],
      color: _hexToColor(data['color'] as String),
      width: (data['width'] as num).toDouble(),
      userId: data['userId'] as String? ?? 'partner',
      isLocal: false,
    );
    _activeStrokesMap[stroke.id] = stroke;
    strokes.add(stroke);
    notifyListeners();
  }

  void _onPartnerDrawMove(Map<String, dynamic> data) {
    final stroke = _activeStrokesMap[data['id'] as String];
    if (stroke == null) return;
    
    if (data.containsKey('points')) {
      // Handle the new batched points array
      final pts = data['points'] as List;
      for (final p in pts) {
        stroke.points.add(Offset(
          (p['x'] as num).toDouble(),
          (p['y'] as num).toDouble(),
        ));
      }
    } else {
      // Legacy single-point fallback
      stroke.points.add(_offsetFromData(data));
    }
    
    notifyListeners();
    _tryUpdateWidget(throttle: true);
  }

  // Batching timers for network efficiency
  Timer? _drawMoveTimer;
  final List<Offset> _drawMoveBatchQueue = [];
  Timer? _cursorMoveTimer;
  Offset? _lastCursorPos;

  void onDrawStart(Offset position, Color color, double width) {
    _currentStrokeId = _uuid.v4();
    final stroke = Stroke(
      id: _currentStrokeId!,
      points: [position],
      color: color,
      width: width,
      userId: 'local',
      isLocal: true,
    );
    strokes.add(stroke);
    _activeStrokesMap[_currentStrokeId!] = stroke;
    
    // Breaking the timeline invalidates future redos
    undoStack.clear();
    
    notifyListeners();

    _send(CanvasEvent(
      type: CanvasEventType.drawStart,
      data: {
        'id': _currentStrokeId,
        'x': position.dx,
        'y': position.dy,
        'color': _colorToHex(color),
        'width': width,
      },
    ));
  }

  void onDrawMove(Offset position) {
    if (_currentStrokeId == null) return;
    
    // 1. Unthrottled local instantaneous render
    _activeStrokesMap[_currentStrokeId!]?.points.add(position);
    notifyListeners();

    // 2. Queue for network batching
    _drawMoveBatchQueue.add(position);

    // 3. Dispatch at ~30 FPS network rate (32ms)
    if (_drawMoveTimer == null || !_drawMoveTimer!.isActive) {
      _drawMoveTimer = Timer(const Duration(milliseconds: 32), () {
        if (_drawMoveBatchQueue.isEmpty || _currentStrokeId == null) return;

        final pointsArray = _drawMoveBatchQueue
            .map((p) => {'x': p.dx, 'y': p.dy})
            .toList();
            
        _drawMoveBatchQueue.clear();

        _send(CanvasEvent(
          type: CanvasEventType.drawMove,
          data: {'id': _currentStrokeId, 'points': pointsArray},
        ));
      });
    }
  }

  void onDrawEnd() {
    if (_currentStrokeId == null) return;
    
    // Immediately flush any pending batched geometry
    _drawMoveTimer?.cancel();
    if (_drawMoveBatchQueue.isNotEmpty) {
      final pointsArray = _drawMoveBatchQueue
          .map((p) => {'x': p.dx, 'y': p.dy})
          .toList();
      _drawMoveBatchQueue.clear();
      _send(CanvasEvent(
        type: CanvasEventType.drawMove,
        data: {'id': _currentStrokeId, 'points': pointsArray},
      ));
    }

    _send(CanvasEvent(
      type: CanvasEventType.drawEnd,
      data: {'id': _currentStrokeId},
    ));
    _activeStrokesMap.remove(_currentStrokeId);
    _currentStrokeId = null;
    
    _rebuildStrokeCache();
    _tryUpdateWidget();
  }

  void onCursorMove(Offset position) {
    _lastCursorPos = position;
    
    // Cursor move can also be safely detached from device refresh rate
    if (_cursorMoveTimer == null || !_cursorMoveTimer!.isActive) {
      _cursorMoveTimer = Timer(const Duration(milliseconds: 32), () {
        if (_lastCursorPos == null) return;
        _send(CanvasEvent(
          type: CanvasEventType.cursorMove,
          data: {'x': _lastCursorPos!.dx, 'y': _lastCursorPos!.dy},
        ));
      });
    }
  }

  void eraseStroke(String strokeId) {
    strokes.removeWhere((s) => s.id == strokeId);
    
    _rebuildStrokeCache();
    
    _send(CanvasEvent(
      type: CanvasEventType.eraseStroke,
      data: {'id': strokeId},
    ));
    _tryUpdateWidget();
  }

  /// Removes the user's most recent local stroke without affecting the partner's strokes.
  void undoLocalStroke() {
    final idx = strokes.lastIndexWhere((s) => s.isLocal);
    if (idx == -1) return;

    final target = strokes.removeAt(idx);
    undoStack.add(target);
    
    _rebuildStrokeCache();
    
    _send(CanvasEvent(
      type: CanvasEventType.eraseStroke,
      data: {'id': target.id},
    ));
    _tryUpdateWidget();
  }

  /// Restores the user's most recently undone stroke.
  void redoLocalStroke() {
    if (undoStack.isEmpty) return;

    final target = undoStack.removeLast();
    strokes.add(target);
    
    _rebuildStrokeCache();
    
    // To restore it on the partner's screen, we must resend it as a fast-forwarded stroke event.
    // Technically, it's just firing drawStart followed by drawMove points array and drawEnd instantaneously.
    _send(CanvasEvent(
      type: CanvasEventType.drawStart,
      data: {
        'id': target.id,
        'x': target.points.first.dx,
        'y': target.points.first.dy,
        'color': _colorToHex(target.color),
        'width': target.width,
        'userId': 'local', // We spoof it or trust the client logic
      },
    ));
    
    _send(CanvasEvent(
      type: CanvasEventType.drawMove,
      data: {
        'id': target.id,
        'points': target.points.map((p) => {'x': p.dx, 'y': p.dy}).toList()
      },
    ));

    _send(CanvasEvent(
      type: CanvasEventType.drawEnd,
      data: {'id': target.id},
    ));
    
    _tryUpdateWidget();
  }

  void removeCanvasItem(String id) {
    canvasItems.removeWhere((m) => m.id == id);
    notifyListeners();
    _send(CanvasEvent(
      type: CanvasEventType.removeCanvasItem,
      data: {'id': id},
    ));
    _tryUpdateWidget();
  }

  /// Adds a media item locally and broadcasts it to the partner.
  void addCanvasItem(CanvasMedia item) {
    canvasItems.add(item);
    notifyListeners();
    String eType;
    switch (item.type) {
      case MediaType.image:
        eType = CanvasEventType.canvasImage;
        break;
      case MediaType.audio:
        eType = CanvasEventType.canvasAudio;
        break;
      case MediaType.video:
        eType = CanvasEventType.canvasVideo;
        break;
      case MediaType.text:
        eType = CanvasEventType.canvasText;
        break;
    }
    _send(CanvasEvent(
      type: eType,
      data: item.toEventData(),
    ));
    _tryUpdateWidget();
  }

  /// Updates position/size/rotation locally (called every gesture frame — no WS send).
  void moveCanvasItemLocal(String id, Offset position,
      {double? width, double? height, double? rotation}) {
    final idx = canvasItems.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    canvasItems[idx] = canvasItems[idx].copyWith(
        position: position, width: width, height: height, rotation: rotation);
    notifyListeners();
    _tryUpdateWidget();
  }

  /// Broadcasts the item's current position + size + rotation to the partner (gesture end).
  void broadcastItemMoved(String id) {
    final idx = canvasItems.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    final item = canvasItems[idx];
    _send(CanvasEvent(
      type: CanvasEventType.canvasItemMoved,
      data: {
        'id': id,
        'x': item.position.dx,
        'y': item.position.dy,
        'width': item.width,
        'height': item.height,
        'rotation': item.rotation,
      },
    ));
    _tryUpdateWidget();
  }

  void _clearLocal() {
    strokes.clear();
    _activeStrokesMap.clear();
    canvasItems.clear();
    undoStack.clear();
    _currentStrokeId = null;
    _rebuildStrokeCache();
  }

  void clearCanvas() {
    _clearLocal();
    _send(CanvasEvent(type: CanvasEventType.clearCanvas, data: {}));
    _tryUpdateWidget();
  }

  void leaveSession() {
    _intentionalDisconnect = true;
    _send(CanvasEvent(type: CanvasEventType.userLeft, data: {}));
    _channel?.sink.close();
    _channel = null;
    _sessionCode = null;
    syncState = SyncState.disconnected;
    _clearLocal();
  }

  void _send(CanvasEvent event) {
    _channel?.sink.add(jsonEncode(event.toJson()));
  }

  void _onDisconnect() {
    _channel = null;
    // If the user explicitly left, don't reconnect.
    if (_intentionalDisconnect || _sessionCode == null) {
      syncState = SyncState.disconnected;
      notifyListeners();
      return;
    }
    // Auto-reconnect for unexpected disconnects (e.g. app backgrounded)
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      syncState = SyncState.connecting;
      notifyListeners();
      Future.delayed(const Duration(seconds: 2), () {
        if (_sessionCode != null && !_intentionalDisconnect) {
          _connectInternal(_sessionCode!);
        }
      });
    } else {
      syncState = SyncState.disconnected;
      notifyListeners();
    }
  }

  static Offset _offsetFromData(Map<String, dynamic> data) => Offset(
        (data['x'] as num).toDouble(),
        (data['y'] as num).toDouble(),
      );

  String _colorToHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  Color _hexToColor(String hex) =>
      Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }
}
