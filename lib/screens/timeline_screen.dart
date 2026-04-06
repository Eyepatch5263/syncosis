import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.construction_rounded,
                size: 80,
                color: const Color(0xFFE85D5D).withAlpha(128),
              ),
              const SizedBox(height: 24),
              Text(
                'Timeline Under Construction',
                textAlign: TextAlign.center,
                style: GoogleFonts.inriaSerif(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'We are building a beautiful space to view all your shared memories across the days. Check back later!',
                textAlign: TextAlign.center,
                style: GoogleFonts.inriaSans(
                  fontSize: 16,
                  color: const Color(0xFF9E9E9E),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
