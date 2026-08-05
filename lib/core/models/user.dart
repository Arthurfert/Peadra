class User {
  final String? id;
  final String username;
  final String passwordHash;
  final String? createdAt;

  User({
    this.id,
    required this.username,
    required this.passwordHash,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'username': username,
        'password_hash': passwordHash,
        if (createdAt != null) 'created_at': createdAt,
      };

  factory User.fromMap(Map<String, dynamic> map) => User(
        id: map['id'] as String?,
        username: map['username'] as String,
        passwordHash: map['password_hash'] as String,
        createdAt: map['created_at'] as String?,
      );
}
