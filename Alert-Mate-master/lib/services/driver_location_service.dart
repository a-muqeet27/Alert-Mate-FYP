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

  /// Stream all non-offline drivers with valid, fresh GPS coordinates.
  /// Used by Admin Dashboard to show all drivers on the map.
  Stream<List<DriverLocation>> getAllDriversStream() {
    return _firestore
        .collection('drivers')
        .where('status', isNotEqualTo: 'offline')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DriverLocation.fromMap(doc.data(), doc.id))
            .where((d) => d.lat != 0.0 && d.lng != 0.0 && !_isStale(d))
            .toList());
  }

  /// Stream all drivers (including offline) — used when we filter client-side.
  /// Returns only drivers with valid, fresh GPS coordinates.
  Stream<List<DriverLocation>> getDriversStream() {
    return _firestore
        .collection('drivers')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DriverLocation.fromMap(doc.data(), doc.id))
            .where((d) => d.lat != 0.0 && d.lng != 0.0 && !_isStale(d))
            .toList());
  }

  /// Stream drivers filtered to specific IDs.
  /// Used by Owner Dashboard to show only their assigned drivers.
  /// Filters are applied client-side to avoid Firestore compound query limitations.
  Stream<List<DriverLocation>> getDriversByIdsStream(List<String> driverIds) {
    if (driverIds.isEmpty) return Stream.value([]);

    return getDriversStream().map((drivers) => drivers
        .where((d) => driverIds.contains(d.id) && d.isOnline)
        .toList());
  }
}
