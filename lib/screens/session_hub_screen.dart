import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/user_service.dart';
import '../services/session_service.dart';
import 'auth_screen.dart';
import 'create_session_screen.dart';
import 'pair_screen.dart';

class SessionHubScreen extends StatefulWidget {
  const SessionHubScreen({super.key});

  @override
  State<SessionHubScreen> createState() => _SessionHubScreenState();
}

class _SessionHubScreenState extends State<SessionHubScreen>
    with TickerProviderStateMixin {
  late AnimationController _heartController;
  late AnimationController _ecgController;
  late Animation<double> _heartScale;
  int _currentNavIndex = 0;

  int _ecgCycles = 0;
  double _lastEcgValue = 0.0;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _ecgController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 2400),
          )
          ..addListener(() {
            if (_ecgController.value < _lastEcgValue) {
              _ecgCycles++;
            }
            _lastEcgValue = _ecgController.value;
          })
          ..repeat();

    // Heartbeat: scale up quickly, back down, small bump, rest
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.25,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.12,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 13,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 45),
    ]).animate(_heartController);
  }

  @override
  void dispose() {
    _ecgController.dispose();
    _heartController.dispose();
    super.dispose();
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign out?',
          style: GoogleFonts.lora(
            color: const Color(0xFF2D1B3D),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'You will need to choose a new username to use Syncosis again.',
          style: GoogleFonts.inriaSans(
            color: const Color(0xFF757575),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inriaSans(color: const Color(0xFF9E9E9E)),
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
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Sign out',
              style: GoogleFonts.inriaSans(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<UserService>().logout();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _uploadAvatar(BuildContext context) async {
    final userService = context.read<UserService>();
    try {
      await userService.uploadAvatar();
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;
    final user = context.read<UserService>().currentUser;
    if (user == null) return;

    switch (index) {
      case 0:
        // Memories — already on hub (or future screen)
        break;
      case 1:
        // Create
        context.read<SessionService>().createSession(user);
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CreateSessionScreen()));
        return;
      case 2:
        // Join
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PairScreen()));
        return;
      case 3:
        // Settings — sign out for now
        _signOut(context);
        return;
    }
    setState(() => _currentNavIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserService>().currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFFDF8F3),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFE85D5D)),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFFDF8F3),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _uploadAvatar(context),
                      child: Stack(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: user.avatarColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE85D5D).withAlpha(60),
                                width: 2,
                              ),
                              image: user.avatarUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(user.avatarUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: user.avatarUrl == null
                                ? Center(
                                    child: Text(
                                      user.username[0].toUpperCase(),
                                      style: GoogleFonts.lora(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE85D5D),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 9,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Our Scrapbook',
                      style: GoogleFonts.inriaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2D1B3D),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _signOut(context),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D1B3D).withAlpha(15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: Color(0xFF2D1B3D),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 36),

                // ── ECG wave + animated heartbeat ──
                SizedBox(
                  width: double.infinity,
                  height: 120, // Increased height for taller wave
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // ECG wave behind the heart
                      AnimatedBuilder(
                        animation: _ecgController,
                        builder: (context, _) => CustomPaint(
                          size: const Size(
                            double.infinity,
                            120,
                          ), // Increased height
                          painter: _EcgPainter(
                            progress: _ecgController.value,
                            cycles: _ecgCycles,
                            color: const Color(0xFFE85D5D).withAlpha(60),
                          ),
                        ),
                      ),
                      // Pulsing heart on top
                      AnimatedBuilder(
                        animation: _heartScale,
                        builder: (context, child) => Transform.scale(
                          scale: _heartScale.value,
                          child: child,
                        ),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDF8F3),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE85D5D).withAlpha(20),
                                blurRadius: 16,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.favorite,
                            color: Color(0xFFE85D5D),
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Title ──
                Text(
                  'Connect to Your\nSpace',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inriaSerif(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2D1B3D),
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                // ── Subtitle ──
                Text(
                  'A shared sanctuary for your favorite\nmoments. Join an existing scrapbook\nor start a fresh one.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inriaSans(
                    fontSize: 14,
                    color: const Color(0xFF9E9E9E),
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 36),

                // ── Start a New Session card ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2D1B3D).withAlpha(8),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start a Session',
                        style: GoogleFonts.inriaSerif(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2D1B3D),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Generate a unique invite code to share\nwith your person.',
                        style: GoogleFonts.inriaSans(
                          fontSize: 13,
                          color: const Color(0xFF9E9E9E),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () {
                          context.read<SessionService>().createSession(user);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CreateSessionScreen(),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 243, 121, 115),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Color.fromARGB(255, 254, 180, 177),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.add_circle_outline,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Create Code',
                                style: GoogleFonts.inriaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Join a Session card ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2D1B3D).withAlpha(8),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Join a Session',
                        style: GoogleFonts.inriaSerif(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2D1B3D),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter the code shared by your friend or\npartner.',
                        style: GoogleFonts.inriaSans(
                          fontSize: 13,
                          color: const Color(0xFF9E9E9E),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PairScreen(),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F2EF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'E.G. XPPLOUK',
                            style: GoogleFonts.inriaSans(
                              fontSize: 15,
                              color: const Color(0xFFCCC5BD),
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PairScreen(),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D1B3D),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Join Shared Space',
                                style: GoogleFonts.inriaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Bottom Navigation Bar ──
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFDF8F3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2D1B3D).withAlpha(10),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Memories
                  _buildNavItem(
                    icon: Icons.auto_stories_outlined,
                    label: 'Memories',
                    index: 1,
                  ),
                  // Create (center, prominent)
                  _buildCreateButton(user),
                  // Join
                  _buildNavItem(icon: Icons.alarm, label: 'Timeline', index: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () => _onNavTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive
                  ? const Color(0xFFE85D5D)
                  : const Color(0xFF9E9E9E),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inriaSans(
                fontSize: 11,
                color: isActive
                    ? const Color(0xFFE85D5D)
                    : const Color(0xFF9E9E9E),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton(dynamic user) {
    return GestureDetector(
      onTap: () {
        context.read<SessionService>().createSession(user);
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CreateSessionScreen()));
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE85D5D), Color(0xFFD94080)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE85D5D).withAlpha(60),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}

/// Draws a scrolling ECG / heartbeat waveform.
class _EcgPainter extends CustomPainter {
  final double progress; // 0..1 — drives horizontal scroll
  final int cycles;
  final Color color;

  _EcgPainter({
    required this.progress,
    required this.cycles,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final midY = size.height / 2;
    final waveWidth = size.width * 0.6; // one full PQRST complex width
    final offset = -progress * waveWidth; // scroll left over time

    final path = Path();
    // Draw 3 copies of the waveform so one is always visible
    for (int i = -1; i <= 2; i++) {
      final startX = offset + i * waveWidth;
      final absoluteIndex = cycles + i;
      // Stable random scale based on absolute wave index
      final randomScale =
          0.4 +
          0.9 * math.Random(absoluteIndex).nextDouble(); // 0.4x to 1.3x height
      _drawComplex(path, startX, midY, waveWidth, size.height, randomScale);
    }

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, paint);
  }

  void _drawComplex(
    Path path,
    double startX,
    double midY,
    double w,
    double h,
    double scale,
  ) {
    // Flat baseline
    path.moveTo(startX, midY);
    path.lineTo(startX + w * 0.15, midY);

    // P wave — small gentle bump
    path.quadraticBezierTo(
      startX + w * 0.20,
      midY - (h * 0.08 * scale),
      startX + w * 0.25,
      midY,
    );

    // Flat before QRS
    path.lineTo(startX + w * 0.32, midY);

    // Q dip
    path.lineTo(startX + w * 0.36, midY + (h * 0.06 * scale));

    // R spike (sharp up)
    path.lineTo(startX + w * 0.42, midY - (h * 0.38 * scale));

    // S dip (sharp down)
    path.lineTo(startX + w * 0.48, midY + (h * 0.12 * scale));

    // Back to baseline
    path.lineTo(startX + w * 0.52, midY);

    // Flat before T wave
    path.lineTo(startX + w * 0.60, midY);

    // T wave — gentle bump
    path.quadraticBezierTo(
      startX + w * 0.68,
      midY - (h * 0.12 * scale),
      startX + w * 0.76,
      midY,
    );

    // Flat tail
    path.lineTo(startX + w, midY);
  }

  @override
  bool shouldRepaint(covariant _EcgPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
