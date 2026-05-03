class TrackingToken {
  final String id;
  final String driverId;
  final String vehiclePlate;
  final String vehicleMake;
  final String vehicleModel;
  final int createdAt;
  final int expiresAt;
  final bool isActive;

  TrackingToken({
    required this.id,
    required this.driverId,
    required this.vehiclePlate,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.createdAt,
    required this.expiresAt,
    this.isActive = true,
  });

  factory TrackingToken.fromMap(Map<String, dynamic> map, String id) {
    return TrackingToken(
      id: id,
      driverId: map['driverId'] ?? '',
      vehiclePlate: map['vehiclePlate'] ?? '',
      vehicleMake: map['vehicleMake'] ?? '',
      vehicleModel: map['vehicleModel'] ?? '',
      createdAt: map['createdAt'] ?? 0,
      expiresAt: map['expiresAt'] ?? 0,
      isActive: map['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'driverId': driverId,
      'vehiclePlate': vehiclePlate,
      'vehicleMake': vehicleMake,
      'vehicleModel': vehicleModel,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
      'isActive': isActive,
    };
  }

  bool get isExpired {
    return DateTime.now().millisecondsSinceEpoch > expiresAt;
  }

  Duration get timeRemaining {
    final remaining = expiresAt - DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: remaining > 0 ? remaining : 0);
  }
}
