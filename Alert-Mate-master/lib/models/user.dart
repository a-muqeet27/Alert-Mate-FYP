class User {
  /// Non-nullable unique identifier (Firebase UID)
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;

  /// Single active role (e.g. 'driver', 'owner')
  final String? role;

  /// Optional list of all roles this user has (e.g. ['owner', 'driver'])
  final List<String>? roles;

  User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    this.role,
    this.roles,
  });

  String get fullName => '$firstName $lastName';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'role': role,
      'roles': roles,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    final dynamic rawRoles = map['roles'];
    final List<String>? roleList = rawRoles is List
        ? rawRoles.map((e) => e.toString()).toList()
        : null;

    return User(
      id: (map['id'] ?? map['uid'] ?? '') as String,
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'] ?? map['activeRole'],
      roles: roleList,
    );
  }
}