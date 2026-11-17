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
}
