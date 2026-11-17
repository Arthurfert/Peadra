class Tag {
  final String? id;
  final String userId;
  final String name;
  final String color;
  final String? createdAt;

  Tag({
    this.id,
    required this.userId,
    required this.name,
    this.color = '#1976D2',
    this.createdAt,
  });

  factory Tag.fromMap(Map<String, dynamic> map) => Tag(
        id: map['id'] as String?,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        color: map['color'] as String? ?? '#1976D2',
        createdAt: map['created_at'] as String?,
      );
}
