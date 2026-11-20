class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;

  Notebook copyWith({
    String? title,
    int? colorValue,
    DateTime? updatedAt,
    bool? isFavorite,
  }) =>
      Notebook(
        id: id,
        title: title ?? this.title,
        colorValue: colorValue ?? this.colorValue,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isFavorite: isFavorite ?? this.isFavorite,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'colorValue': colorValue,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isFavorite': isFavorite,
  };

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
    id: json['id'] as String,
    title: json['title'] as String,
    colorValue: json['colorValue'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isFavorite: json['isFavorite'] as bool? ?? false,
  );
}
