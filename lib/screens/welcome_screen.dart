import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/user_service.dart';
import 'onboarding_screen.dart';
import 'session_hub_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _navigate);
  }

  void _navigate() {
    if (!mounted) return;
    final isLoggedIn = context.read<UserService>().isLoggedIn;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            isLoggedIn ? const SessionHubScreen() : const OnboardingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.cyan, Colors.blue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'Syncosis',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 3,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Real-time Canvas for Two',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white54,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 64),
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Colors.cyan),
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
