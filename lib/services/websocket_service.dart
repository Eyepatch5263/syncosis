import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/canvas_event.dart';
import '../models/canvas_media.dart';
import '../models/stroke.dart';
import 'widget_service.dart';

enum SyncState { disconnected, connecting, waitingForPartner, connected, partnerLeft }

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  SyncState syncState = SyncState.disconnected;

  final List<Stroke> strokes = [];
  final Map<String, Stroke> _activeStrokes = {};
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
        _activeStrokes.remove(event.data['id'] as String);
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
        notifyListeners();
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
    _activeStrokes[stroke.id] = stroke;
    strokes.add(stroke);
    notifyListeners();
  }

  void _onPartnerDrawMove(Map<String, dynamic> data) {
    final stroke = _activeStrokes[data['id'] as String];
    if (stroke == null) return;
    stroke.points.add(_offsetFromData(data));
    notifyListeners();
    _tryUpdateWidget(throttle: true);
  }

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
    _activeStrokes[_currentStrokeId!] = stroke;
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
    _activeStrokes[_currentStrokeId!]?.points.add(position);
    notifyListeners();

    _send(CanvasEvent(
      type: CanvasEventType.drawMove,
      data: {'id': _currentStrokeId, 'x': position.dx, 'y': position.dy},
    ));
  }

  void onDrawEnd() {
    if (_currentStrokeId == null) return;
    _send(CanvasEvent(
      type: CanvasEventType.drawEnd,
      data: {'id': _currentStrokeId},
    ));
    _activeStrokes.remove(_currentStrokeId);
    _currentStrokeId = null;
    _tryUpdateWidget();
  }

  void onCursorMove(Offset position) {
    _send(CanvasEvent(
      type: CanvasEventType.cursorMove,
      data: {'x': position.dx, 'y': position.dy},
    ));
  }

  void eraseStroke(String strokeId) {
    strokes.removeWhere((s) => s.id == strokeId);
    notifyListeners();
    _send(CanvasEvent(
      type: CanvasEventType.eraseStroke,
      data: {'id': strokeId},
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
    _activeStrokes.clear();
    canvasItems.clear();
    _currentStrokeId = null;
    notifyListeners();
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
