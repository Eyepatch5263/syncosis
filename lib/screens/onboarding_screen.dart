import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      image: 'assets/images/feature_status.jpg',
      title: 'Stay Connected,\nAlways in Sync',
      subtitle:
          'Share real-time status updates with your loved ones.\n'
          'They always know what you\'re up to — and you know theirs.',
    ),
    _OnboardingPage(
      image: 'assets/images/feature_scribble.jpg',
      title: 'Scribble Together,\nIn Real Time',
      subtitle:
          'Draw, doodle, and express yourself on a shared canvas.\n'
          'Every stroke appears instantly on their screen.',
    ),
    _OnboardingPage(
      image: 'assets/images/feature_widget.jpg',
      title: 'Widgets & Media,\nRight on Home',
      subtitle:
          'Send photos, voice notes, and more — all in one place.\n'
          'Pin a widget to see their status without opening the app.',
    ),
  ];

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _goToAuth();
    }
  }

  void _goToAuth() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          // ── Page view (full-screen images + text) ──
          PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final page = _pages[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Background image
                  Image.asset(page.image, fit: BoxFit.cover),
                  // Gradient overlay for text readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF1A1A2E).withAlpha(30),
                          const Color(0xFF1A1A2E).withAlpha(210),
                          const Color(0xFF1A1A2E).withAlpha(245),
                          const Color(0xFF1A1A2E),
                        ],
                        stops: const [0.0, 0.35, 0.6, 0.75, 1.0],
                      ),
                    ),
                  ),
                  // Text content pinned to bottom
                  Positioned(
                    left: 28,
                    right: 28,
                    bottom: 180,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lora(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.subtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inriaSans(
                            fontSize: 14,
                            color: Colors.white.withAlpha(180),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          // ── Skip button (top-right) ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 20,
            child: GestureDetector(
              onTap: _goToAuth,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Skip',
                  style: GoogleFonts.inriaSans(
                    fontSize: 14,
                    color: Colors.white.withAlpha(200),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom controls: dots + button ──
          Positioned(
            left: 28,
            right: 28,
            bottom: MediaQuery.of(context).padding.bottom + 40,
            child: Column(
              children: [
                // Dot indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == i ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == i
                            ? const Color(0xFFE85D5D)
                            : Colors.white.withAlpha(80),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Get Started / Next button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE85D5D),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: Text(
                      isLast ? 'Get Started' : 'Next',
                      style: GoogleFonts.inriaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final String image;
  final String title;
  final String subtitle;

  const _OnboardingPage({
    required this.image,
    required this.title,
    required this.subtitle,
  });
}
