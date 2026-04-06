import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Callback to start the task handler — must be top-level.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SessionTaskHandler());
}

/// Minimal task handler that simply keeps the foreground service alive
/// so that the WebSocket connection in the main isolate is not killed
/// by Android when the app is backgrounded.
class SessionTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Nothing to do — the service being alive is enough.
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Optional: send a heartbeat to main isolate
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Service destroyed
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}
