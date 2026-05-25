import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyContact {
  final String id;
  final String userId;
  final String userRole;
  final String name;
  final String relationship;
  final String phone;
  final String email;
  final String priority;
  final List<String> methods;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  EmergencyContact({
    required this.id,
    required this.userId,
    required this.userRole,
    required this.name,
    required this.relationship,
    required this.phone,
    required this.email,
    required this.priority,
    required this.methods,
    required this.enabled,
    this.createdAt,
    this.updatedAt,
  });

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static List<String> _parseMethods(dynamic value) {
    if (value == null) return const ['call'];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const ['call'];
  }

  static bool _parseEnabled(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return true;
  }

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    final rawPriority =
        (map['priority'] as String? ?? map['contactType'] as String?) ?? 'secondary';
    return EmergencyContact(
      id: map['id'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      userRole: map['userRole'] as String? ?? '',
      name: map['name'] as String? ?? '',
      relationship: map['relationship'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      priority: rawPriority.toLowerCase().trim(),
      methods: _parseMethods(map['methods']),
      enabled: _parseEnabled(map['enabled']),
      createdAt: _parseTimestamp(map['createdAt']),
      updatedAt: _parseTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userRole': userRole,
      'name': name,
      'relationship': relationship,
      'phone': phone,
      'email': email,
      'priority': priority,
      'methods': methods,
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toDashboardMap() {
    return {
      'name': name,
      'relationship': relationship,
      'phone': phone,
      'email': email,
      'priority': priority,
      'methods': methods,
      'enabled': enabled,
    };
  }

  bool get isPrimary => priority == 'primary';

  bool get isSecondary => priority == 'secondary';

  String get contactTypeLabel => isPrimary ? 'Primary' : 'Secondary';

  String get contactType => priority;
}
