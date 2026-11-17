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
}
