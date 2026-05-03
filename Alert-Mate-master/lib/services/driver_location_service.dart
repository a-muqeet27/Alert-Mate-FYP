import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/driver_location.dart';

/// Service for real-time driver location streaming from Firestore.
/// Reads from the `drivers` collection via Firestore snapshots.
class DriverLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Drivers whose location is older than this are treated as gone —
  /// prevents "ghost" pins when a driver's app is force-closed and
  /// goOffline() never fires.
  static const Duration _staleThreshold = Duration(minutes: 5);

  bool _isStale(DriverLocation d) {
    if (d.updatedAt == null) return true;
    return DateTime.now().difference(d.updatedAt!) > _staleThreshold;
  }

  /// Stream all drivers who are actively on trip (monitoring started).
  /// Used by Admin Dashboard to show all drivers on the map.
  /// Only shows drivers with status 'on_trip' (monitoring active).
  Stream<List<DriverLocation>> getAllDriversStream() {
    return _firestore
        .collection('drivers')
        .where('status', isEqualTo: 'on_trip')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DriverLocation.fromMap(doc.data(), doc.id))
            .where((d) => d.lat != 0.0 && d.lng != 0.0 && !_isStale(d))
            .toList());
  }

  /// Stream all drivers who are actively on trip (monitoring started).
  /// Returns only drivers with status 'on_trip' and valid, fresh GPS coordinates.
  Stream<List<DriverLocation>> getDriversStream() {
    return _firestore
        .collection('drivers')
        .where('status', isEqualTo: 'on_trip')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DriverLocation.fromMap(doc.data(), doc.id))
            .where((d) => d.lat != 0.0 && d.lng != 0.0 && !_isStale(d))
            .toList());
  }

  /// Stream drivers filtered to specific IDs who are actively on trip.
  /// Used by Owner Dashboard to show only their assigned drivers.
  /// Only shows drivers with status 'on_trip' (monitoring active).
  Stream<List<DriverLocation>> getDriversByIdsStream(List<String> driverIds) {
    if (driverIds.isEmpty) return Stream.value([]);

    return getDriversStream().map((drivers) => drivers
        .where((d) => driverIds.contains(d.id))
        .toList());
  }
}
