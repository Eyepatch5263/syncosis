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
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          textTheme: TextTheme(
            bodyLarge: GoogleFonts.inriaSans(),
            bodyMedium: GoogleFonts.inriaSans(),
            bodySmall: GoogleFonts.inriaSans(),
            headlineLarge: GoogleFonts.lora(),
            headlineMedium: GoogleFonts.lora(),
            headlineSmall: GoogleFonts.lora(),
            titleLarge: GoogleFonts.lora(),
            titleMedium: GoogleFonts.inriaSans(),
            titleSmall: GoogleFonts.inriaSans(),
          ),
        ),
        home: const WelcomeScreen(),
      ),
    );
  }
}
