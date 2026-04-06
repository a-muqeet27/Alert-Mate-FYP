import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a driver's live location data from Firestore.
/// Maps to the `drivers/{driverId}` collection schema.
class DriverLocation {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String status; // "on_trip", "idle", "offline"
  final bool drowsinessAlert;
  final DateTime? updatedAt;

  DriverLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.status,
    required this.drowsinessAlert,
    this.updatedAt,
  });

  factory DriverLocation.fromMap(Map<String, dynamic> map, String docId) {
    DateTime? parsedDate;
    final rawUpdatedAt = map['updatedAt'];
    if (rawUpdatedAt is Timestamp) {
      parsedDate = rawUpdatedAt.toDate();
    } else if (rawUpdatedAt is String) {
      parsedDate = DateTime.tryParse(rawUpdatedAt);
    }

    return DriverLocation(
      id: docId,
      name: map['name'] ?? 'Unknown Driver',
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? 'offline',
      drowsinessAlert: map['drowsinessAlert'] ?? false,
      updatedAt: parsedDate,
    );
  }

  bool get isOnline => status != 'offline';
  bool get isOnTrip => status == 'on_trip';
  bool get isIdle => status == 'idle';

  String get statusLabel {
    switch (status) {
      case 'on_trip':
        return 'On Trip';
      case 'idle':
        return 'Idle';
      case 'offline':
        return 'Offline';
      default:
        return status;
    }
  }

  String get timeAgo {
    if (updatedAt == null) return 'Unknown';
    final diff = DateTime.now().difference(updatedAt!);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
