class CollectionModel {
  final String id;
  String name;
  String emoji;
  String description;
  DateTime createdAt;
  DateTime updatedAt;

  CollectionModel({
    required this.id,
    required this.name,
    this.emoji = '🧵',
    this.description = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory CollectionModel.fromJson(Map<String, dynamic> json) => CollectionModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        emoji: json['emoji'] as String? ?? '🧵',
        description: json['description'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static const List<String> emojis = [
    '🎀', '🌸', '❄️', '☀️', '🍂', '🎄', '💝', '🌺', '✨', '🦋', '🍒', '🌊', '🧵',
  ];
}
