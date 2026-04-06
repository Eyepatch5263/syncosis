import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/session_service.dart';
import '../services/websocket_service.dart';
import 'canvas_screen.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  bool _codeCopied = false;
  late final WebSocketService _ws;

  @override
  void initState() {
    super.initState();
    _ws = context.read<WebSocketService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final code = context.read<SessionService>().currentSession?.code;
      if (code == null) return;
      _ws.connect(code);
      _ws.addListener(_onWsState);
    });
  }

  void _onWsState() {
    if (_ws.syncState == SyncState.connected && mounted) {
      _ws.removeListener(_onWsState);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CanvasScreen()),
      );
    }
  }

  @override
  void dispose() {
    _ws.removeListener(_onWsState);
    super.dispose();
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _codeCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _codeCopied = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied to clipboard!'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>().currentSession;

    if (session == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: Theme.of(context).primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      context.read<SessionService>().leaveSession();
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).textTheme.bodyLarge?.color?.withAlpha(15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        size: 16,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Our Scrapbook',
                    style: GoogleFonts.lora(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 38),
                ],
              ),
            ),

            // ── Content ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 32),

                    // Title
                    Text(
                      'Your Invite Code',
                      style: GoogleFonts.lora(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Text(
                      'Share this with your person to\nstart your shared journey.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inriaSans(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Code card ──
                    GestureDetector(
                      onTap: () => _copyCode(session.code),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 32,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).textTheme.bodyLarge!.color!.withAlpha(10),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              'UNIQUE PAIR KEY',
                              style: GoogleFonts.inriaSans(
                                fontSize: 11,
                                color: Theme.of(context).textTheme.bodySmall?.color,
                                letterSpacing: 3,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              session.code,
                              style: GoogleFonts.lora(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                                letterSpacing: 4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: 60,
                              height: 3,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE85D5D).withAlpha(80),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Heart icon
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.favorite,
                          color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(80),
                          size: 24,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Waiting status
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).textTheme.bodyLarge?.color?.withAlpha(8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor.withAlpha(150),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Waiting for your partner...',
                            style: GoogleFonts.inriaSans(
                              fontSize: 13,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),

                    // Share Code button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () => _copyCode(session.code),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D1B3D),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        icon: Icon(
                          _codeCopied ? Icons.check : Icons.share_outlined,
                          size: 20,
                        ),
                        label: Text(
                          _codeCopied ? 'Copied!' : 'Share Code',
                          style: GoogleFonts.inriaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Go to Canvas button (disabled look)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEDE9E5),
                          disabledBackgroundColor: const Color(0xFFEDE9E5),
                          foregroundColor: const Color(0xFFBDBDBD),
                          disabledForegroundColor: const Color(0xFFBDBDBD),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        icon: const Icon(Icons.auto_stories_outlined, size: 20),
                        label: Text(
                          'Go to Canvas',
                          style: GoogleFonts.inriaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
