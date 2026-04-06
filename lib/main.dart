import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import 'screens/welcome_screen.dart';
import 'services/session_service.dart';
import 'services/user_service.dart';
import 'services/websocket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize foreground task communication port
  FlutterForegroundTask.initCommunicationPort();

  // Initialize foreground service config
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'syncosis_session',
      channelName: 'Syncosis Session',
      channelDescription: 'Keeps your scrapbook session alive in the background.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  // Initialize home widget
  HomeWidget.setAppGroupId('com.example.syncosis');

  // Restore persisted user before the first frame so WelcomeScreen
  // can immediately route to SessionHubScreen without a loading state.
  final userService = UserService();
  await userService.init();

  runApp(SyncosisApp(userService: userService));
}

class SyncosisApp extends StatelessWidget {
  const SyncosisApp({super.key, required this.userService});

  final UserService userService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: userService),
        ChangeNotifierProvider(create: (_) => SessionService()),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
      ],
      child: MaterialApp(
        title: 'Syncosis',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        
        // ── Aesthetic Light Theme ──
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF9F6F0),
          canvasColor: Colors.white,
          cardColor: const Color(0xFFF5F2EF),
          primaryColor: const Color(0xFFE85D5D),
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFE85D5D),
            surface: Colors.white,
            onSurface: Color(0xFF2D1B3D),
          ),
          iconTheme: const IconThemeData(color: Color(0xFF2D1B3D)),
          textTheme: TextTheme(
            bodyLarge: GoogleFonts.inriaSans(color: const Color(0xFF2D1B3D)),
            bodyMedium: GoogleFonts.inriaSans(color: const Color(0xFF2D1B3D)),
            bodySmall: GoogleFonts.inriaSans(color: const Color(0xFF5A4B6B)),
            headlineLarge: GoogleFonts.lora(color: const Color(0xFF2D1B3D)),
            headlineMedium: GoogleFonts.lora(color: const Color(0xFF2D1B3D)),
            headlineSmall: GoogleFonts.lora(color: const Color(0xFF2D1B3D)),
            titleLarge: GoogleFonts.lora(color: const Color(0xFF2D1B3D)),
            titleMedium: GoogleFonts.inriaSans(color: const Color(0xFF2D1B3D)),
            titleSmall: GoogleFonts.inriaSans(color: const Color(0xFF5A4B6B)),
          ),
        ),

        // ── Immersive Dark Theme ──
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF1A131F),
          canvasColor: const Color(0xFF221929),
          cardColor: const Color(0xFF2D2336), // Replaces #F5F2EF boxes in dark mode
          primaryColor: const Color(0xFFE85D5D),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFE85D5D),
            surface: Color(0xFF221929),
            onSurface: Color(0xFFF4ECE6),
          ),
          iconTheme: const IconThemeData(color: Color(0xFFF4ECE6)),
          textTheme: TextTheme(
            bodyLarge: GoogleFonts.inriaSans(color: const Color(0xFFF4ECE6)),
            bodyMedium: GoogleFonts.inriaSans(color: const Color(0xFFF4ECE6)),
            bodySmall: GoogleFonts.inriaSans(color: const Color(0xFFBCAEB8)),
            headlineLarge: GoogleFonts.lora(color: const Color(0xFFF4ECE6)),
            headlineMedium: GoogleFonts.lora(color: const Color(0xFFF4ECE6)),
            headlineSmall: GoogleFonts.lora(color: const Color(0xFFF4ECE6)),
            titleLarge: GoogleFonts.lora(color: const Color(0xFFF4ECE6)),
            titleMedium: GoogleFonts.inriaSans(color: const Color(0xFFF4ECE6)),
            titleSmall: GoogleFonts.inriaSans(color: const Color(0xFFBCAEB8)),
          ),
        ),
        
        home: const WelcomeScreen(),
      ),
    );
  }
}
