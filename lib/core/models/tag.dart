class Tag {
  final int? id;
  final int userId;
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

  Tag copyWith({
    int? id,
    int? userId,
    String? name,
    String? color,
  }) =>
      Tag(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        color: color ?? this.color,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'name': name,
        'color': color,
      };

  factory Tag.fromMap(Map<String, dynamic> map) => Tag(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        name: map['name'] as String,
        color: map['color'] as String? ?? '#1976D2',
        createdAt: map['created_at'] as String?,
      );
}
