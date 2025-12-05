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

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      id: map['id'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      userRole: map['userRole'] as String? ?? '',
      name: map['name'] as String? ?? '',
      relationship: map['relationship'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      priority: map['priority'] as String? ?? 'secondary',
      methods: List<String>.from(map['methods'] as List? ?? []),
      enabled: map['enabled'] as bool? ?? true,
      createdAt: map['createdAt'] != null 
          ? (map['createdAt'] as Timestamp).toDate() 
          : null,
      updatedAt: map['updatedAt'] != null 
          ? (map['updatedAt'] as Timestamp).toDate() 
          : null,
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

  // Convert to the Map format used in dashboards
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
}
