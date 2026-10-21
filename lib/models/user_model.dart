class UserModel {
  final String userId;
  final String username;
  final String fullName;
  final String email;
  final String role;
  final String token;

  UserModel({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.email,
    required this.role,
    required this.token,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, String token) {
    return UserModel(
      userId: json['userId'] ?? '',
      username: json['username'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'Parent',
      token: token,
    );
  }
}
