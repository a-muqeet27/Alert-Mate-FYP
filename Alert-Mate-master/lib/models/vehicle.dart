class Vehicle {
  final String id;
  final String make;
  final String model;
  final String year;
  final String licensePlate;
  final String ownerId;
  final String? ownerEmail;
  final String? assignedDriverId;
  final String? assignedDriverEmail;
  final String? driverName;
  final String status; // 'Active', 'Break', 'Critical', 'Offline'
  final int alertness; // 0-100
  final String? location;
  final String? lastUpdate;
  final bool pendingAssignment; // Waiting for ANY driver (owner said "No")
  final bool pendingOwnerAssignment; // NEW: Waiting specifically for OWNER to become driver

  Vehicle({
    required this.id,
    required this.make,
    required this.model,
    required this.year,
    required this.licensePlate,
    required this.ownerId,
    this.ownerEmail,
    this.assignedDriverId,
    this.assignedDriverEmail,
    this.driverName,
    this.status = 'Offline',
    this.alertness = 0,
    this.location,
    this.lastUpdate,
    this.pendingAssignment = false,
    this.pendingOwnerAssignment = false, // NEW
  });

  // Create Vehicle from Firestore document
  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      id: map['id'] ?? '',
      make: map['make'] ?? '',
      model: map['model'] ?? '',
      year: map['year'] ?? '',
      licensePlate: map['licensePlate'] ?? '',
      ownerId: map['ownerId'] ?? '',
      ownerEmail: map['ownerEmail'],
      assignedDriverId: map['assignedDriverId'],
      assignedDriverEmail: map['assignedDriverEmail'],
      driverName: map['driverName'],
      status: map['status'] ?? 'Offline',
      alertness: _parseAlertness(map['alertness']),
      location: map['location'],
      lastUpdate: map['lastUpdate'],
      pendingAssignment: map['pendingAssignment'] ?? false,
      pendingOwnerAssignment: map['pendingOwnerAssignment'] ?? false, // NEW
    );
  }

  // Helper to parse alertness (handles both int and string)
  static int _parseAlertness(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      // Handle legacy string values
      switch (value.toLowerCase()) {
        case 'good':
        case 'high':
          return 85;
        case 'moderate':
        case 'medium':
          return 65;
        case 'low':
        case 'critical':
          return 40;
        default:
          return int.tryParse(value) ?? 0;
      }
    }
    return 0;
  }

  // Convert Vehicle to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'make': make,
      'model': model,
      'year': year,
      'licensePlate': licensePlate,
      'ownerId': ownerId,
      'ownerEmail': ownerEmail,
      'assignedDriverId': assignedDriverId,
      'assignedDriverEmail': assignedDriverEmail,
      'driverName': driverName,
      'status': status,
      'alertness': alertness,
      'location': location,
      'lastUpdate': lastUpdate,
      'pendingAssignment': pendingAssignment,
      'pendingOwnerAssignment': pendingOwnerAssignment, // NEW
    };
  }

  // Create a copy with updated fields
  Vehicle copyWith({
    String? id,
    String? make,
    String? model,
    String? year,
    String? licensePlate,
    String? ownerId,
    String? ownerEmail,
    String? assignedDriverId,
    String? assignedDriverEmail,
    String? driverName,
    String? status,
    int? alertness,
    String? location,
    String? lastUpdate,
    bool? pendingAssignment,
    bool? pendingOwnerAssignment,
  }) {
    return Vehicle(
      id: id ?? this.id,
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      licensePlate: licensePlate ?? this.licensePlate,
      ownerId: ownerId ?? this.ownerId,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      assignedDriverId: assignedDriverId ?? this.assignedDriverId,
      assignedDriverEmail: assignedDriverEmail ?? this.assignedDriverEmail,
      driverName: driverName ?? this.driverName,
      status: status ?? this.status,
      alertness: alertness ?? this.alertness,
      location: location ?? this.location,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      pendingAssignment: pendingAssignment ?? this.pendingAssignment,
      pendingOwnerAssignment: pendingOwnerAssignment ?? this.pendingOwnerAssignment,
    );
  }

  // Helper getters
  bool get isAssigned => assignedDriverId != null;
  bool get isActive => status == 'Active';
  bool get isCritical => status == 'Critical' || alertness < 50;
  bool get needsAssignment => pendingAssignment && !isAssigned;
  bool get waitingForOwner => pendingOwnerAssignment && !isAssigned; // NEW
  
  String get displayName => '$make $model ($year)';
  String get alertnessLevel {
    if (alertness >= 80) return 'High';
    if (alertness >= 70) return 'Good';
    if (alertness >= 50) return 'Moderate';
    return 'Low';
  }
  
  // NEW: Get assignment status description
  String get assignmentStatus {
    if (isAssigned) return 'Assigned to ${driverName ?? "driver"}';
    if (pendingOwnerAssignment) return 'Waiting for owner to become driver';
    if (pendingAssignment) return 'Waiting for driver assignment';
    return 'No driver assigned';
  }

  @override
  String toString() {
    return 'Vehicle(id: $id, $make $model, status: $status, driver: ${driverName ?? 'Unassigned'})';
  }
}