import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

class UserService extends ChangeNotifier {
  static const _keyUserId = 'user_id';
  static const _keyUsername = 'user_name';
  static const _keyUserColor = 'user_color';
  static const _keyAvatarUrl = 'avatar_url';
  static const _apiBase =  'https://syncosis-server-b075827ce03d.herokuapp.com';

  User? _currentUser;
  SharedPreferences? _prefs;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  Future<SharedPreferences> get _storage async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> init() async {
    final prefs = await _storage;
    final id = prefs.getInt(_keyUserId);
    final username = prefs.getString(_keyUsername);
    final colorValue = prefs.getInt(_keyUserColor);
    final avatarUrl = prefs.getString(_keyAvatarUrl);

    if (id != null && username != null) {
      _currentUser = User(
        id: id.toString(),
        username: username,
        avatarColor:
            colorValue != null ? Color(colorValue) : const Color(0xFF4ECDC4),
        avatarUrl: avatarUrl,
      );
      notifyListeners();
    }
  }

  Future<User> createUser(String username, String password, Color avatarColor) async {
    final response = await http
        .post(
          Uri.parse('$_apiBase/api/users/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 201) {
      return _saveUserFromResponse(response.body, avatarColor);
    }
    if (response.statusCode == 409) {
      throw Exception('Username already taken. Please choose another.');
    }
    throw Exception('Could not reach the server. Please try again.');
  }

  Future<User> login(String username, String password) async {
    final response = await http
        .post(
          Uri.parse('$_apiBase/api/users/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return _saveUserFromResponse(response.body, _pickColor(username));
    }
    if (response.statusCode == 401) {
      throw Exception('Invalid username or password.');
    }
    throw Exception('Could not reach the server. Please try again.');
  }

  Future<User> _saveUserFromResponse(String body, Color avatarColor) async {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final user = User(
      id: (data['id'] as int).toString(),
      username: data['username'] as String,
      avatarColor: avatarColor,
      avatarUrl: data['avatar_url'] as String?,
    );
    _currentUser = user;

    final prefs = await _storage;
    final futures = <Future>[
      prefs.setInt(_keyUserId, data['id'] as int),
      prefs.setString(_keyUsername, user.username),
      prefs.setInt(_keyUserColor, avatarColor.toARGB32()),
    ];
    if (user.avatarUrl != null) {
      futures.add(prefs.setString(_keyAvatarUrl, user.avatarUrl!));
    }
    await Future.wait(futures);

    notifyListeners();
    return user;
  }

  Future<String?> uploadAvatar() async {
    final user = _currentUser;
    if (user == null) return null;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBase/api/users/upload-avatar'),
    )
      ..fields['user_id'] = user.id
      ..files.add(http.MultipartFile.fromBytes(
        'avatar',
        bytes,
        filename: picked.name,
      ));

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      final err =
          (jsonDecode(body) as Map<String, dynamic>)['error'] as String?;
      throw Exception(err ?? 'Upload failed');
    }

    final url =
        (jsonDecode(body) as Map<String, dynamic>)['avatar_url'] as String;
    _currentUser = user.copyWith(avatarUrl: url);
    final prefs = await _storage;
    await prefs.setString(_keyAvatarUrl, url);
    notifyListeners();
    return url;
  }

  Future<void> logout() async {
    final prefs = await _storage;
    await Future.wait([
      prefs.remove(_keyUserId),
      prefs.remove(_keyUsername),
      prefs.remove(_keyUserColor),
      prefs.remove(_keyAvatarUrl),
    ]);
    _currentUser = null;
    notifyListeners();
  }

  static const _palette = [
    Color(0xFFFF6B6B),
    Color(0xFF4ECDC4),
    Color(0xFF45B7D1),
    Color(0xFF96CEB4),
    Color(0xFFFFD93D),
    Color(0xFF6C5CE7),
  ];

  static Color _pickColor(String username) =>
      _palette[username.codeUnits.fold(0, (a, b) => a + b) % _palette.length];
}
