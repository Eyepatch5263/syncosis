import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../models/canvas_media.dart';
import '../painters/canvas_painter.dart';
import '../services/canvas_upload_service.dart';
import '../services/session_task_handler.dart';
import '../services/websocket_service.dart';
import '../services/widget_service.dart';

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

enum CanvasTool { pan, pen, erase }

class _CanvasScreenState extends State<CanvasScreen>
    with WidgetsBindingObserver {
  Color _selectedColor = const Color(0xFF2D1B3D);
  double _strokeWidth = 4.0;
  bool _showToolbar = true;
  bool _partnerLeftDialogShown = false;
  CanvasTool _tool = CanvasTool.pen;
  bool _isUploadingMedia = false;
  double? _scaleStartWidth;
  double? _scaleStartHeight;
  double? _scaleStartRotation;

  late final WebSocketService _ws;
  final TransformationController _transformCtrl = TransformationController();

  static const _palette = [
    Color(0xFFE85D5D),
    Color(0xFF2D1B3D),
    Color(0xFFF3A683),
    Color(0xFF78B7BB),
    Color(0xFFE77F67),
    Color(0xFFAE8CC8),
  ];

  @override
  void initState() {
    super.initState();
    _ws = context.read<WebSocketService>();
    WidgetsBinding.instance.addObserver(this);
    _ws.addListener(_onWsState);
    _transformCtrl.addListener(_onCanvasTransform);
    _startForegroundService();
  }

  Future<void> _startForegroundService() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Syncosis Session Active',
        notificationText: 'Your scrapbook session is running ♡',
        callback: startCallback,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ws.removeListener(_onWsState);
    _transformCtrl.removeListener(_onCanvasTransform);
    _transformCtrl.dispose();
    super.dispose();
  }

  // Rebuild whenever the canvas is panned/zoomed so screen-space items follow.
  void _onCanvasTransform() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Session stays alive when the app is backgrounded.
    // Only explicit "End Room" kills it.
    // But we do push a fresh snapshot to the home widget.
    if (state == AppLifecycleState.paused) {
      WidgetService.update(strokes: _ws.strokes, mediaItems: _ws.canvasItems);
    }
  }

  void _onWsState() {
    if (_ws.syncState == SyncState.partnerLeft &&
        !_partnerLeftDialogShown &&
        mounted) {
      _partnerLeftDialogShown = true;
      _showPartnerLeftDialog();
    }
  }

  // ── Viewport helpers ────────────────────────────────────────────────────────

  Offset _toCanvasCoords(Offset screenPos) {
    final inv = Matrix4.copy(_transformCtrl.value)..invert();
    return MatrixUtils.transformPoint(inv, screenPos);
  }

  Offset _viewportCenter() {
    final size = MediaQuery.of(context).size;
    return _toCanvasCoords(Offset(size.width / 2, size.height / 2));
  }

  // ── Image upload ─────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    setState(() => _isUploadingMedia = true);
    try {
      final bytes = await file.readAsBytes();

      // Get natural dimensions so the image renders at the right aspect ratio
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final naturalW = frame.image.width.toDouble();
      final naturalH = frame.image.height.toDouble();

      const maxSize = 350.0;
      double w = naturalW, h = naturalH;
      if (w > maxSize || h > maxSize) {
        final scale = maxSize / (w > h ? w : h);
        w *= scale;
        h *= scale;
      }

      final url = await CanvasUploadService.upload(
        bytes: bytes,
        filename: file.name,
      );

      if (!mounted) return;
      final center = _viewportCenter();
      context.read<WebSocketService>().addCanvasItem(
        CanvasMedia.image(
          url: url,
          position: Offset(center.dx - w / 2, center.dy - h / 2),
          width: w,
          height: h,
        ),
      );
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2D1B3D),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    setState(() => _isUploadingMedia = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await CanvasUploadService.upload(
        bytes: bytes,
        filename: file.name,
      );

      if (!mounted) return;
      final center = _viewportCenter();
      context.read<WebSocketService>().addCanvasItem(
        CanvasMedia.video(
          url: url,
          position: Offset(center.dx - 100, center.dy - 100),
          width: 200,
          height: 200,
        ),
      );
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2D1B3D),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  // ── Audio sheet ──────────────────────────────────────────────────────────────

  Future<void> _showAudioSheet() async {
    final result =
        await showModalBottomSheet<
          (String url, String filename, String quote)?
        >(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => const _AudioRecorderSheet(),
        );

    if (result == null || !mounted) return;
    final (url, filename, quote) = result;
    final center = _viewportCenter();

    Map<String, dynamic>? meta;
    if (quote.isNotEmpty) {
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
      meta = {'isPost': true, 'quote': quote, 'timestamp': timeStr};
    }

    context.read<WebSocketService>().addCanvasItem(
      CanvasMedia.audio(
        url: url,
        position: Offset(center.dx - 110, center.dy - 30),
        filename: filename,
        metadata: meta,
      ),
    );
  }

  Future<void> _showTextSheet() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        String input = '';
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Add Text',
            style: GoogleFonts.lora(
              color: const Color(0xFF2D1B3D),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            onChanged: (val) => input = val,
            decoration: const InputDecoration(
              hintText: 'Type something sweet...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE85D5D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(context, input),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (text == null || text.trim().isEmpty || !mounted) return;

    final center = _viewportCenter();
    context.read<WebSocketService>().addCanvasItem(
      CanvasMedia.text(
        text: text.trim(),
        colorHex: _selectedColor.value.toRadixString(16).padLeft(8, '0'),
        position: Offset(center.dx - 100, center.dy - 30),
      ),
    );
  }

  void _showCreatePostSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePostSheet(
        ws: context.read<WebSocketService>(),
        viewportCenter: _viewportCenter(),
      ),
    );
  }

  // ── Brush Settings Sheet ──────────────────────────────────────────────────────

  void _showBrushSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Brush Thickness',
                style: GoogleFonts.lora(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2D1B3D),
                ),
              ),
              const SizedBox(height: 24),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFFE85D5D),
                  inactiveTrackColor: const Color(0xFFE85D5D).withOpacity(0.2),
                  thumbColor: const Color(0xFFE85D5D),
                  overlayColor: const Color(0xFFE85D5D).withOpacity(0.1),
                ),
                child: Slider(
                  value: _strokeWidth,
                  min: 1.0,
                  max: 30.0,
                  divisions: 29,
                  label: _strokeWidth.round().toString(),
                  onChanged: (val) {
                    setState(() => _strokeWidth = val);
                    setSheetState(() {});
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showColorPickerDialog() {
    Color tempColor = _selectedColor;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Pick a Color',
          style: GoogleFonts.lora(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: HueRingPicker(
            pickerColor: tempColor,
            onColorChanged: (color) => tempColor = color,
            enableAlpha: false,
            displayThumbColor: true,
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Got it', style: TextStyle(color: Color(0xFFE85D5D))),
            onPressed: () {
              setState(() {
                _selectedColor = tempColor;
                _tool = CanvasTool.pen;
              });
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────────

  void _showDeleteDialog(CanvasMedia item, WebSocketService ws) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Item?',
          style: GoogleFonts.lora(
            color: const Color(0xFF2D1B3D),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Remove this from the canvas?',
          style: GoogleFonts.inriaSans(
            color: const Color(0xFF757575),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inriaSans(
                color: const Color(0xFF9E9E9E),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE85D5D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              ws.removeCanvasItem(item.id);
              Navigator.pop(context);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.inriaSans(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showPartnerLeftDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.person_off_outlined,
              color: Color(0xFFE85D5D),
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              'Partner Left',
              style: GoogleFonts.lora(
                color: const Color(0xFF2D1B3D),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Your partner has left the session.\nPlease create or join a new session to continue.',
          style: GoogleFonts.inriaSans(
            color: const Color(0xFF757575),
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE85D5D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              FlutterForegroundTask.stopService();
              Navigator.of(context).pop();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: Text(
              'Back to Hub',
              style: GoogleFonts.inriaSans(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showEndRoomDialog(WebSocketService ws) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.exit_to_app_rounded,
              color: Color(0xFFE85D5D),
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              'End Room?',
              style: GoogleFonts.lora(
                color: const Color(0xFF2D1B3D),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'This will end the session for both you and your partner. Are you sure?',
          style: GoogleFonts.inriaSans(
            color: const Color(0xFF757575),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inriaSans(
                color: const Color(0xFF757575),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE85D5D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              FlutterForegroundTask.stopService();
              ws.leaveSession();
              Navigator.of(context).pop(); // close dialog
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: Text(
              'End Room',
              style: GoogleFonts.inriaSans(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status helpers ────────────────────────────────────────────────────────────

  String _statusLabel(SyncState state) => switch (state) {
    SyncState.disconnected => 'Disconnected',
    SyncState.connecting => 'Connecting…',
    SyncState.waitingForPartner => 'Waiting for partner…',
    SyncState.connected => 'Partner is Online',
    SyncState.partnerLeft => 'Partner left',
  };

  Color _statusDotColor(SyncState state) => switch (state) {
    SyncState.disconnected => const Color(0xFFE85D5D),
    SyncState.connecting => const Color(0xFFF3A683),
    SyncState.waitingForPartner => const Color(0xFFF3A683),
    SyncState.connected => const Color(0xFF66BB6A),
    SyncState.partnerLeft => const Color(0xFFE85D5D),
  };

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();

    return PopScope(
      onPopInvokedWithResult: (_, __) {
        // Back just navigates away; session stays alive.
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            // ── Infinite canvas ──
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _tool == CanvasTool.pen
                  ? (e) => ws.onDrawStart(
                      _toCanvasCoords(e.localPosition),
                      _selectedColor,
                      _strokeWidth,
                    )
                  : null,
              onPointerMove: (e) {
                final pos = _toCanvasCoords(e.localPosition);
                if (_tool == CanvasTool.pen) {
                  ws.onDrawMove(pos);
                  ws.onCursorMove(pos);
                } else if (_tool == CanvasTool.erase) {
                  final strokesToRemove = <String>[];
                  for (final s in ws.strokes) {
                    for (final pt in s.points) {
                      if ((pt - pos).distance < 20.0) {
                        strokesToRemove.add(s.id);
                        break;
                      }
                    }
                  }
                  for (final id in strokesToRemove) {
                    ws.eraseStroke(id);
                  }
                }
              },
              onPointerUp: _tool == CanvasTool.pen
                  ? (_) => ws.onDrawEnd()
                  : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showToolbar = !_showToolbar),
                child: InteractiveViewer(
                  transformationController: _transformCtrl,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  constrained: false,
                  minScale: 0.2,
                  maxScale: 4.0,
                  panEnabled: _tool == CanvasTool.pan,
                  scaleEnabled: _tool == CanvasTool.pan,
                  child: SizedBox(
                    width: 4000,
                    height: 4000,
                    // Strokes only — items live in the outer Stack (screen space)
                    child: CustomPaint(
                      painter: CanvasPainter(
                        cachedPicture: ws.cachedStrokesPicture,
                        activeStrokes: ws.activeStrokes,
                        partnerCursor: ws.partnerCursor,
                      ),
                      size: const Size(4000, 4000),
                    ),
                  ),
                ),
              ),
            ),

            // ── Media items in screen space (outside InteractiveViewer) ──
            for (final item in ws.canvasItems) _buildScreenItem(item, ws),

            // ── Upload loading overlay ──
            if (_isUploadingMedia)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withAlpha(60),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          'Uploading…',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Top bar ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).scaffoldBackgroundColor,
                      Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor.withAlpha(200),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2D1B3D).withAlpha(12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Color(0xFF2D1B3D),
                              size: 20,
                            ),
                          ),
                        ),
                        Spacer(),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(200),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2D1B3D).withAlpha(8),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _statusDotColor(ws.syncState),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _statusLabel(ws.syncState),
                                    style: GoogleFonts.inriaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF2D1B3D),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                        // end session
                        GestureDetector(
                          onTap: () => _showEndRoomDialog(ws),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE85D5D).withAlpha(30),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.exit_to_app_rounded,
                                  color: Color(0xFFE85D5D),
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'End',
                                  style: GoogleFonts.inriaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFE85D5D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom toolbar ──
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              bottom: _showToolbar ? 24 : -100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2D1B3D).withAlpha(18),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (final color in _palette)
                        GestureDetector(
                          onTap: () => setState(() {
                            _selectedColor = color;
                            _tool = CanvasTool.pen;
                          }),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border:
                                  _selectedColor == color &&
                                      _tool == CanvasTool.pen
                                  ? Border.all(
                                      color: const Color(0xFF2D1B3D),
                                      width: 2.5,
                                    )
                                  : Border.all(
                                      color: Colors.transparent,
                                      width: 2.5,
                                    ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),

                      // RGB Color Wheel Picker
                      GestureDetector(
                        onTap: _showColorPickerDialog,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const SweepGradient(
                              colors: [
                                Colors.red,
                                Colors.yellow,
                                Colors.green,
                                Colors.cyan,
                                Colors.blue,
                                Colors.purple,
                                Colors.red,
                              ],
                            ),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(20),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Vertical Divider
                      Container(width: 1, height: 24, color: Theme.of(context).dividerColor.withOpacity(0.2)),
                      const SizedBox(width: 8),

                      // Undo / Redo
                      _buildToolButton(
                        icon: Icons.undo_rounded,
                        onTap: ws.canUndo ? ws.undoLocalStroke : () {},
                        color: ws.canUndo ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey[400],
                      ),
                      const SizedBox(width: 2),
                      _buildToolButton(
                        icon: Icons.redo_rounded,
                        onTap: ws.canRedo ? ws.redoLocalStroke : () {},
                        color: ws.canRedo ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey[400],
                      ),
                      const SizedBox(width: 8),

                      // Vertical Divider
                      Container(width: 1, height: 24, color: Theme.of(context).dividerColor.withOpacity(0.2)),
                      const SizedBox(width: 8),
                      
                      _buildToolButton(
                        icon: _isUploadingMedia
                            ? Icons.hourglass_top_rounded
                            : Icons.image_outlined,
                        onTap: _isUploadingMedia ? () {} : _pickImage,
                      ),
                      const SizedBox(width: 6),
                      _buildToolButton(
                        icon: _isUploadingMedia
                            ? Icons.hourglass_empty_rounded
                            : Icons.videocam_outlined,
                        onTap: _isUploadingMedia ? () {} : _pickVideo,
                      ),
                      const SizedBox(width: 6),
                      _buildToolButton(
                        icon: Icons.mic_none_rounded,
                        onTap: _showAudioSheet,
                      ),
                      const SizedBox(width: 6),
                      _buildToolButton(
                        icon: Icons.text_fields_rounded,
                        onTap: _showTextSheet,
                      ),
                      const SizedBox(width: 6),
                      _buildToolButton(
                        icon: Icons.post_add_rounded,
                        onTap: _showCreatePostSheet,
                      ),
                      const SizedBox(width: 6),
                      _buildToolIcon(
                        CanvasTool.pan,
                        Icons.pan_tool_outlined,
                        'Pan',
                      ),
                      const SizedBox(width: 6),
                      // Brush Thickness
                      _buildToolButton(
                        icon: Icons.lens_outlined,
                        onTap: _showBrushSettingsSheet,
                      ),
                      const SizedBox(width: 6),
                      _buildToolIcon(CanvasTool.pen, Icons.edit_rounded, 'Pen'),
                      const SizedBox(width: 6),
                      _buildToolIcon(
                        CanvasTool.erase,
                        Icons.cleaning_services_rounded,
                        'Erase',
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: ws.clearCanvas,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2D1B3D).withAlpha(12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                            size: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Screen-space media item (drag + pinch + rotate outside InteractiveViewer) ──

  // Audio minimum sizes
  static const double _audioMinWidth = 160.0;
  static const double _audioMinHeight = 50.0;
  // Threshold below which audio shows compact play-only button
  static const double _audioCompactThreshold = 180.0;

  Widget _buildScreenItem(CanvasMedia item, WebSocketService ws) {
    final transform = _transformCtrl.value;
    final screenPos = MatrixUtils.transformPoint(transform, item.position);
    final viewScale = transform.getMaxScaleOnAxis();
    final screenW = item.width * viewScale;
    final screenH = item.height * viewScale;

    final isAudio = item.type == MediaType.audio;
    final isCompact = isAudio && item.width < _audioCompactThreshold;

    return Positioned(
      left: screenPos.dx,
      top: screenPos.dy,
      width: screenW,
      height: screenH,
      child: Transform.rotate(
        angle: item.rotation,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            _showDeleteDialog(item, ws);
          },
          onScaleStart: (_) {
            final current = ws.canvasItems.firstWhere((m) => m.id == item.id);
            setState(() {
              _scaleStartWidth = current.width;
              _scaleStartHeight = current.height;
              _scaleStartRotation = current.rotation;
            });
          },
          onScaleUpdate: (details) {
            final vScale = _transformCtrl.value.getMaxScaleOnAxis();
            final current = ws.canvasItems.firstWhere((m) => m.id == item.id);
            final newPos = current.position + details.focalPointDelta / vScale;

            double? newW, newH;
            double? newRotation;

            if (details.pointerCount >= 2) {
              // ── Resize ──
              if (_scaleStartWidth != null) {
                if (isAudio) {
                  final isAudioPost = current.metadata?['isPost'] == true;
                  newW = (_scaleStartWidth! * details.scale).clamp(
                    _audioMinWidth,
                    400.0,
                  );
                  newH = (_scaleStartHeight! * details.scale).clamp(
                    _audioMinHeight,
                    isAudioPost ? 400.0 : 120.0,
                  );
                } else {
                  newW = (_scaleStartWidth! * details.scale).clamp(
                    40.0,
                    1200.0,
                  );
                  newH = (_scaleStartHeight! * details.scale).clamp(
                    40.0,
                    1200.0,
                  );
                }
              }
              // ── Rotate ──
              if (_scaleStartRotation != null) {
                newRotation = _scaleStartRotation! + details.rotation;
              }
            }

            ws.moveCanvasItemLocal(
              item.id,
              newPos,
              width: newW,
              height: newH,
              rotation: newRotation,
            );
          },
          onScaleEnd: (_) {
            ws.broadcastItemMoved(item.id);
          },
          child: RepaintBoundary(
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: (item.metadata?['isPost'] == true) ? 240.0 : item.width,
                height: (item.metadata?['isPost'] == true)
                    ? (240.0 * item.height / item.width)
                    : item.height,
                child: _buildMediaContent(item, isCompact),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaContent(CanvasMedia item, bool isCompact) {
    Widget mediaWidget;
    if (item.type == MediaType.audio) {
      mediaWidget = _AudioChip(
        media: item,
        isCompact: isCompact,
        isPost: item.metadata?['isPost'] == true,
      );
    } else if (item.type == MediaType.video) {
      mediaWidget = _VideoChip(media: item);
    } else if (item.type == MediaType.text) {
      mediaWidget = FittedBox(
        fit: BoxFit.contain,
        child: Text(
          item.url, // text payload
          style: GoogleFonts.lora(
            fontWeight: FontWeight.w600,
            color: Color(
              int.parse(item.filename, radix: 16),
            ), // color stored in filename
          ),
        ),
      );
    } else {
      // Image fallback
      mediaWidget = Image.network(
        item.url,
        filterQuality: FilterQuality.low, // GPU optimization
        cacheWidth: 600, // Reduced texture size constraint
        fit: (item.metadata != null && item.metadata!['isPost'] == true)
            ? BoxFit.cover
            : BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (item.metadata != null && item.metadata!['isPost'] == true) {
      final isAudio = item.type == MediaType.audio;
      final m = item.metadata!;
      final title = m['title'] as String?;
      final subtitle = m['subtitle'] as String?;
      final quote = m['quote'] as String?;
      final time = m['timestamp'] as String?;
      final frame = m['frame'] as String? ?? 'polaroid';
      final String? url2 = m['url2'] as String?;
      final bool hasTwo = url2 != null;

      Widget buildSingleFrame(
        String targetUrl,
        String? fTitle,
        String? fSubtitle,
        String? fTime,
        bool isSecondary,
      ) {
        final tMediaWidget = isSecondary
            ? Image.network(
                targetUrl,
                filterQuality: FilterQuality.low, // GPU optimization
                cacheWidth: 600, // Reduced texture size constraint
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                errorBuilder: (_, __, ___) =>
                    Container(color: Colors.grey[200]),
              )
            : mediaWidget;

        if (frame == 'film' && !isAudio) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF111113),
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      10,
                      (_) => Container(
                        width: 8,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F7F4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: tMediaWidget,
                        ),
                      ),
                      if ((fTitle != null && fTitle.isNotEmpty) ||
                          (fSubtitle != null && fSubtitle.isNotEmpty) ||
                          (fTime != null))
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 12,
                            left: 4,
                            right: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (fTitle != null && fTitle.isNotEmpty)
                                Text(
                                  fTitle,
                                  style: GoogleFonts.inriaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (fTitle != null && fTitle.isNotEmpty)
                                const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (fSubtitle != null && fSubtitle.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        fSubtitle.toUpperCase(),
                                        style: GoogleFonts.inriaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1.2,
                                          color: Colors.white54,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if (fTime != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: Text(
                                        fTime,
                                        style: GoogleFonts.inriaSans(
                                          fontSize: 10,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 24,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      10,
                      (_) => Container(
                        width: 8,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F7F4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isAudio ? 28 : 8),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2D1B3D).withAlpha(30),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: EdgeInsets.all(isAudio ? 16 : 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isAudio) ...[
                    tMediaWidget,
                    if (quote != null && quote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0, bottom: 12.0),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(4),
                          ),
                          child: Container(
                            color: const Color(0xFFFBF7F1),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: 4,
                                    color: const Color(0xFFB18941),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Text(
                                        '"$quote"',
                                        style: GoogleFonts.lora(
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                          color: const Color(0xFF7A6034),
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (quote == null || quote.isEmpty)
                      const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.mic,
                          size: 12,
                          color: Color(0xFF9E9E9E),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'VOICE NOTE',
                          style: GoogleFonts.inriaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF9E9E9E),
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        if (fTime != null)
                          Text(
                            fTime,
                            style: GoogleFonts.inriaSans(
                              fontSize: 10,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (!isAudio) ...[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: tMediaWidget,
                      ),
                    ),
                    if (fTitle != null && fTitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 12.0,
                          left: 4,
                          right: 4,
                        ),
                        child: Text(
                          fTitle,
                          style: GoogleFonts.inriaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2D1B3D),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 4.0,
                        left: 4,
                        right: 4,
                        bottom: 12.0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (fSubtitle != null && fSubtitle.isNotEmpty)
                            Expanded(
                              child: Text(
                                fSubtitle.toUpperCase(),
                                style: GoogleFonts.inriaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: const Color(0xFF9E9E9E),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (fTime != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                fTime,
                                style: GoogleFonts.inriaSans(
                                  fontSize: 10,
                                  color: const Color(0xFF9E9E9E),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isAudio && frame != 'film')
              Positioned(
                top: -4,
                right: 18,
                child: Transform.rotate(
                  angle: -0.15,
                  child: Container(
                    width: 44,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDAA045).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      }

      if (hasTwo && !isAudio) {
        return SizedBox(
          width: item.width,
          height: item.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                right: 0,
                width: item.width * 0.70,
                height: item.height * 0.70,
                child: Transform.rotate(
                  angle: 0.1,
                  child: buildSingleFrame(
                    item.url,
                    null,
                    null,
                    time,
                    false,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                width: item.width * 0.70,
                height: item.height * 0.70,
                child: Transform.rotate(
                  angle: -0.1,
                  child: buildSingleFrame(url2, null, null, null, true),
                ),
              ),
            ],
          ),
        );
      }

      return buildSingleFrame(item.url, title, subtitle, time, false);
    }

    return mediaWidget;
  }

  Widget _buildToolIcon(CanvasTool tool, IconData icon, String label) {
    final active = _tool == tool;
    return GestureDetector(
      onTap: () => setState(() => _tool = tool),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE85D5D) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inriaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color ?? Theme.of(context).textTheme.bodyLarge?.color, size: 18),
      ),
    );
  }
}

// ── Audio chip rendered on canvas ─────────────────────────────────────────────

class _AudioChip extends StatefulWidget {
  final CanvasMedia media;
  final bool isCompact;
  final bool isPost;
  const _AudioChip({
    required this.media,
    this.isCompact = false,
    this.isPost = false,
  });

  @override
  State<_AudioChip> createState() => _AudioChipState();
}

class _AudioChipState extends State<_AudioChip> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted)
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
    });
    _player.setSource(UrlSource(widget.media.url));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration != Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.resume();
    }
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPost) {
      final progress = _duration.inMilliseconds > 0
          ? _position.inMilliseconds / _duration.inMilliseconds
          : 0.0;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFD34F73),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD34F73).withAlpha(60),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: const Color(0xFFF1EBE3),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFA12C4D),
                    ),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: GoogleFonts.inriaSans(
                        fontSize: 10,
                        color: const Color(0xFF8F8A83),
                      ),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: GoogleFonts.inriaSans(
                        fontSize: 10,
                        color: const Color(0xFF8F8A83),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Compact mode: just a play/pause circle button
    if (widget.isCompact) {
      return GestureDetector(
        onTap: _toggle,
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFD34F73),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD34F73).withAlpha(60),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );
    }

    final label = widget.media.filename.isEmpty
        ? 'Voice note'
        : widget.media.filename;
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D1B3D).withAlpha(30),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFD34F73),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inriaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2D1B3D),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _playing
                        ? '${_formatDuration(_position)} / ${_formatDuration(_duration)}'
                        : 'Tap to play',
                    style: GoogleFonts.inriaSans(
                      fontSize: 10,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Video chip rendered on canvas ─────────────────────────────────────────────

class _VideoChip extends StatefulWidget {
  final CanvasMedia media;
  const _VideoChip({required this.media});

  @override
  State<_VideoChip> createState() => _VideoChipState();
}

class _VideoChipState extends State<_VideoChip> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.media.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _initialized = true;
          });
          _controller.setLooping(true);
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _controller.value.isPlaying
              ? _controller.pause()
              : _controller.play();
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_initialized)
              VideoPlayer(_controller)
            else
              Container(
                color: Colors.black12,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_initialized && !_controller.value.isPlaying)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Audio recorder bottom sheet ───────────────────────────────────────────────

class _AudioRecorderSheet extends StatefulWidget {
  const _AudioRecorderSheet();

  @override
  State<_AudioRecorderSheet> createState() => _AudioRecorderSheetState();
}

class _AudioRecorderSheetState extends State<_AudioRecorderSheet> {
  final _recorder = AudioRecorder();
  final _quoteCtrl = TextEditingController();
  bool _recording = false;
  bool _uploading = false;
  int _seconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _quoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission || !mounted) return;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);

    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _stopAndUpload() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (!mounted || path == null) return;

    setState(() {
      _recording = false;
      _uploading = true;
    });

    try {
      final bytes = await File(path).readAsBytes();
      final filename = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final url = await CanvasUploadService.upload(
        bytes: bytes,
        filename: filename,
      );
      if (mounted)
        Navigator.of(context).pop((url, 'Voice note', _quoteCtrl.text.trim()));
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2D1B3D),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _formatTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Voice Note',
              style: GoogleFonts.lora(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2D1B3D),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _quoteCtrl,
              decoration: InputDecoration(
                labelText: 'Add a quote... (Optional)',
                labelStyle: GoogleFonts.inriaSans(
                  color: const Color(0xFF9E9E9E),
                ),
                filled: true,
                fillColor: const Color(0xFFF5F2EF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 2,
              style: GoogleFonts.inriaSans(color: const Color(0xFF2D1B3D)),
            ),
            const SizedBox(height: 16),
            Text(
              _recording
                  ? 'Recording… tap the mic to stop'
                  : _uploading
                  ? 'Uploading…'
                  : 'Tap the mic to start recording',
              textAlign: TextAlign.center,
              style: GoogleFonts.inriaSans(
                fontSize: 13,
                color: const Color(0xFF9E9E9E),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            // big mic button
            GestureDetector(
              onTap: _uploading
                  ? null
                  : _recording
                  ? _stopAndUpload
                  : _startRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recording
                      ? const Color(0xFFE85D5D)
                      : const Color(0xFF2D1B3D),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_recording
                                  ? const Color(0xFFE85D5D)
                                  : const Color(0xFF2D1B3D))
                              .withAlpha(60),
                      blurRadius: _recording ? 24 : 12,
                      spreadRadius: _recording ? 4 : 0,
                    ),
                  ],
                ),
                child: _uploading
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Icon(
                        _recording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
              ),
            ),
            const SizedBox(height: 20),
            // timer
            AnimatedOpacity(
              opacity: _recording ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE85D5D),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatTime(_seconds),
                    style: GoogleFonts.inriaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2D1B3D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Create Post Sheet ─────────────────────────────────────────────────────────

class _CreatePostSheet extends StatefulWidget {
  final WebSocketService ws;
  final Offset viewportCenter;
  const _CreatePostSheet({required this.ws, required this.viewportCenter});

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();

  String _selectedFrame = 'polaroid';
  bool _isUploading = false;

  Future<void> _uploadAndCreatePost(MediaType type) async {
    if (_isUploading) return;

    final picker = ImagePicker();
    List<Uint8List> fileBytesList = [];
    List<String> filenames = [];

    if (type == MediaType.image) {
      final List<XFile> xFiles = await picker.pickMultiImage();
      if (xFiles.isNotEmpty) {
        for (int i = 0; i < xFiles.length && i < 2; i++) {
          fileBytesList.add(await xFiles[i].readAsBytes());
          filenames.add(xFiles[i].name);
        }
      }
    } else if (type == MediaType.video) {
      final xf = await picker.pickVideo(source: ImageSource.gallery);
      if (xf != null) {
        fileBytesList.add(await xf.readAsBytes());
        filenames.add(xf.name);
      }
    }

    if (fileBytesList.isEmpty) return;

    setState(() => _isUploading = true);

    try {
      final url = await CanvasUploadService.upload(
        bytes: fileBytesList[0],
        filename: filenames[0],
      );

      String? url2;
      // Upload second image if it exists
      if (fileBytesList.length > 1) {
        url2 = await CanvasUploadService.upload(
          bytes: fileBytesList[1],
          filename: filenames[1],
        );
      }

      // Auto format timestamp
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';

      final meta = {
        'isPost': true,
        'title': _titleCtrl.text.trim(),
        'subtitle': _subtitleCtrl.text.trim(),
        'timestamp': timeStr,
        'frame': _selectedFrame,
        if (url2 != null) 'url2': url2,
      };

      if (!mounted) return;

      if (type == MediaType.image) {
        final decoded = await decodeImageFromList(fileBytesList[0]);
        double w = 240;
        double h = (decoded.height / decoded.width) * 240;
        widget.ws.addCanvasItem(
          CanvasMedia.image(
            url: url,
            position: widget.viewportCenter,
            width: w,
            height: h,
            metadata: meta,
          ),
        );
      } else if (type == MediaType.video) {
        widget.ws.addCanvasItem(
          CanvasMedia.video(
            url: url,
            position: widget.viewportCenter,
            width: 240,
            height: 400,
            metadata: meta,
          ),
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to post. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create Post',
                style: GoogleFonts.lora(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2D1B3D),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _frameOption(
                    'polaroid',
                    'Polaroid',
                    Icons.photo_camera_front,
                  ),
                  const SizedBox(width: 12),
                  _frameOption(
                    'film',
                    'Film Strip',
                    Icons.movie_creation_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Title (e.g. Sunflowers & Smiles)',
                  labelStyle: GoogleFonts.inriaSans(
                    color: const Color(0xFF9E9E9E),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF5F2EF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: GoogleFonts.inriaSans(
                  color: const Color(0xFF2D1B3D),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subtitleCtrl,
                decoration: InputDecoration(
                  labelText: 'Subtitle (e.g. SHARED BY SARAH)',
                  labelStyle: GoogleFonts.inriaSans(
                    color: const Color(0xFF9E9E9E),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF5F2EF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: GoogleFonts.inriaSans(color: const Color(0xFF2D1B3D)),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE85D5D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isUploading
                          ? null
                          : () => _uploadAndCreatePost(MediaType.image),
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        'Post Photo',
                        style: GoogleFonts.inriaSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE85D5D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isUploading
                          ? null
                          : () => _uploadAndCreatePost(MediaType.video),
                      icon: const Icon(Icons.videocam_outlined),
                      label: Text(
                        'Post Video',
                        style: GoogleFonts.inriaSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_isUploading)
            Positioned.fill(
              child: Container(
                color: Colors.white.withAlpha(150),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFFE85D5D)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _frameOption(String value, String label, IconData icon) {
    final isSelected = _selectedFrame == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFrame = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFE85D5D)
                : const Color(0xFFF5F2EF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF9E9E9E),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inriaSans(
                  color: isSelected ? Colors.white : const Color(0xFF2D1B3D),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
