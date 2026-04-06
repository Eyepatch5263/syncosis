import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/user_service.dart';
import 'onboarding_screen.dart';
import 'session_hub_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bgScale;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _bgScale = Tween<double>(begin: 1.08, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuart,
      ),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 1.0, curve: Curves.easeOut),
      ),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();

    // Give it a bit more time to admire the splash screen before transitioning
    Future.delayed(const Duration(milliseconds: 2800), _navigate);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigate() {
    if (!mounted) return;
    final isLoggedIn = context.read<UserService>().isLoggedIn;
    
    // Switch completely using a smooth fading transition
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                isLoggedIn ? const SessionHubScreen() : const OnboardingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1) Ken Burns effect on the user's splash image
          AnimatedBuilder(
            animation: _bgScale,
            builder:
                (context, child) => Transform.scale(
                  scale: _bgScale.value,
                  child: child,
                ),
            child: Image.asset('assets/images/splash.png', fit: BoxFit.cover),
          ),

          // 2) Full-Screen Glassmorphism Overlay
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor.withAlpha(160), // Adapts frosty glass logic
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SafeArea(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder:
                          (context, child) => FadeTransition(
                            opacity: _fadeAnim,
                            child: SlideTransition(
                              position: _slideAnim,
                              child: child,
                            ),
                          ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(flex: 3),
                          // Heart Icon acting as a subtle logo above the text
                          const Icon(
                            Icons.favorite_rounded,
                            size: 48,
                            color: Color(0xFFE85D5D),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // App Brand
                          ShaderMask(
                            shaderCallback:
                                (bounds) => const LinearGradient(
                                  colors: [Color(0xFFD94080), Color(0xFFE85D5D)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds),
                            child: Text(
                              'Syncosis',
                              style: GoogleFonts.lora(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2.0,
                                color: Colors.white, 
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Deeper tagline
                          Text(
                            'Craft your shared story.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inriaSans(
                              fontSize: 22,
                              color: Theme.of(context).textTheme.bodyLarge?.color, 
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Subtitle explaining the app vision
                          Text(
                            'A private space where distance fades\nand your memories sync.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inriaSans(
                              fontSize: 15,
                              color: Theme.of(context).textTheme.bodyLarge?.color?.withAlpha(160), 
                              height: 1.5,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),

                          const Spacer(flex: 2),

                          // An elegant smooth loader
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              width: 140,
                              height: 3,
                              color: Theme.of(context).textTheme.bodyLarge?.color?.withAlpha(20),
                              child: const LinearProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(
                                  Color(0xFFE85D5D), // Signature coral-rose
                                ),
                                backgroundColor: Colors.transparent,
                              ),
                            ),
                          ),
                          
                          const Spacer(flex: 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
