import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/session.dart';
import '../models/user.dart';

class SessionService extends ChangeNotifier {
  Session? _currentSession;

  Session? get currentSession => _currentSession;
  bool get isInSession => _currentSession != null;

  static final _rng = Random.secure();

  // Generate a 6-char alphanumeric code
  static String generateSessionCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(6, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  void createSession(User user1) {
    final code = generateSessionCode();
    _currentSession = Session(
      id: const Uuid().v4(),
      code: code,
      user1: user1,
    );
    notifyListeners();
  }

  void joinSession(String code, User user2) {
    // In a real app, this would verify the code with the server
    if (_currentSession != null && _currentSession!.code == code) {
      _currentSession = Session(
        id: _currentSession!.id,
        code: _currentSession!.code,
        user1: _currentSession!.user1,
        user2: user2,
        createdAt: _currentSession!.createdAt,
      );
      notifyListeners();
    }
  }

  void leaveSession() {
    _currentSession = null;
    notifyListeners();
  }

  @override
  void dispose() {
    leaveSession();
    super.dispose();
  }
}
