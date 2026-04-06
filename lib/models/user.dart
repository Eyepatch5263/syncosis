import 'dart:ui';

class User {
  final String id;
  final String username;
  final Color avatarColor;
  final String? avatarUrl;

  const User({
    required this.id,
    required this.username,
    required this.avatarColor,
    this.avatarUrl,
  });

  User copyWith({String? avatarUrl}) => User(
        id: id,
        username: username,
        avatarColor: avatarColor,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatarColor': avatarColor.toARGB32(),
        'avatarUrl': avatarUrl,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        username: json['username'] as String,
        avatarColor: Color(json['avatarColor'] as int),
        avatarUrl: json['avatarUrl'] as String?,
      );
}
