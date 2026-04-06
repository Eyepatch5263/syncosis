import 'user.dart';

class Session {
  final String id;
  final String code; // 6-char code
  final User user1;
  final User? user2;
  final DateTime createdAt;

  Session({
    required this.id,
    required this.code,
    required this.user1,
    this.user2,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isComplete => user2 != null;

  String get inviteLink => 'syncosis://join/$code';

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'user1': user1.toJson(),
    'user2': user2?.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] as String,
    code: json['code'] as String,
    user1: User.fromJson(json['user1'] as Map<String, dynamic>),
    user2: json['user2'] != null
        ? User.fromJson(json['user2'] as Map<String, dynamic>)
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
