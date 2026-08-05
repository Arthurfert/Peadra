class Description {
  final String? id;
  final String userId;
  final String name;
  final String? createdAt;

  Description({
    this.id,
    required this.userId,
    required this.name,
    this.createdAt,
  });

  Description copyWith({
    String? id,
    String? userId,
    String? name,
    String? createdAt,
  }) =>
      Description(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'name': name,
        if (createdAt != null) 'created_at': createdAt,
      };

  factory Description.fromMap(Map<String, dynamic> map) => Description(
        id: map['id'] as String?,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        createdAt: map['created_at'] as String?,
      );
}
