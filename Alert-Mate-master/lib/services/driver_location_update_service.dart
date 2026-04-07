import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Service responsible for writing driver presence and GPS data to the
/// Firestore `drivers/{driverId}` document so that LiveMap can display them.
///
/// Firestore schema written by this service:
/// ```
/// drivers/{driverId} {
///   name:             String   — driver's display name
///   status:           String   — "idle" | "on_trip" | "offline"
///   lat:              double   — GPS latitude  (0.0 if unavailable)
///   lng:              double   — GPS longitude (0.0 if unavailable)
///   drowsinessAlert:  bool     — true when alertness < 70
///   updatedAt:        Timestamp
/// }
/// ```
class DriverLocationUpdateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Timer? _locationTimer;

  // ── Lifecycle helpers ──────────────────────────────────────────────────────

  /// Call in driver dashboard's [initState].
  /// Creates/merges the Firestore document and marks the driver as idle.
  Future<void> goOnline(String driverId, String driverName) async {
    try {
      await _firestore.collection('drivers').doc(driverId).set({
        'name': driverName,
        'status': 'idle',
        'drowsinessAlert': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Eagerly grab a first location so the map shows something immediately.
      await _updateLocation(driverId);

      print('✅ DriverLocationUpdateService: driver $driverId is now online (idle)');
    } catch (e) {
      print('⚠️ DriverLocationUpdateService.goOnline error: $e');
    }
  }

  /// Call when monitoring starts — marks driver as on_trip and starts
  /// periodic GPS updates every 10 seconds.
  Future<void> goOnTrip(String driverId) async {
    try {
      await _firestore.collection('drivers').doc(driverId).update({
        'status': 'on_trip',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      startLocationUpdates(driverId);
      print('✅ DriverLocationUpdateService: driver $driverId status → on_trip');
    } catch (e) {
      print('⚠️ DriverLocationUpdateService.goOnTrip error: $e');
    }
  }

  /// Call when monitoring stops — clears alert and reverts to idle.
  Future<void> goIdle(String driverId) async {
    try {
      stopLocationUpdates();
      await _firestore.collection('drivers').doc(driverId).update({
        'status': 'idle',
        'drowsinessAlert': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ DriverLocationUpdateService: driver $driverId status → idle');
    } catch (e) {
      print('⚠️ DriverLocationUpdateService.goIdle error: $e');
    }
  }

  /// Call in driver dashboard's [dispose] (fire-and-forget, no await needed).
  /// Sets status to offline so the driver disappears from all maps.
  Future<void> goOffline(String driverId) async {
    try {
      stopLocationUpdates();
      await _firestore.collection('drivers').doc(driverId).update({
        'status': 'offline',
        'drowsinessAlert': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ DriverLocationUpdateService: driver $driverId status → offline');
    } catch (e) {
      print('⚠️ DriverLocationUpdateService.goOffline error: $e');
    }
  }

  // ── Drowsiness ──────────────────────────────────────────────────────────────

  /// Toggle the drowsiness alert flag.  Only call when the value actually
  /// changes to avoid unnecessary Firestore writes.
  Future<void> updateDrowsinessAlert(String driverId, bool alert) async {
    try {
      await _firestore.collection('drivers').doc(driverId).update({
        'drowsinessAlert': alert,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('⚠️ DriverLocationUpdateService.updateDrowsinessAlert error: $e');
    }
  }

  // ── GPS helpers ─────────────────────────────────────────────────────────────

  /// Start a repeating 10-second GPS update loop.
  void startLocationUpdates(String driverId) {
    _locationTimer?.cancel();
    // Immediate first update
    _updateLocation(driverId);
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _updateLocation(driverId);
    });
  }

  /// Stop the repeating GPS loop.
  void stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _updateLocation(String driverId) async {
    try {
      final position = await _getPosition();
      if (position == null) return;

      await _firestore.collection('drivers').doc(driverId).update({
        'lat': position.latitude,
        'lng': position.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print(
        '📍 DriverLocationUpdateService: location updated '
        '(${position.latitude.toStringAsFixed(5)}, '
        '${position.longitude.toStringAsFixed(5)})',
      );
    } catch (e) {
      print('⚠️ DriverLocationUpdateService._updateLocation error: $e');
    }
  }

  Future<Position?> _getPosition() async {
    try {
      // 1. Location service must be enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Location services are disabled on this device.');
        return null;
      }

      // 2. Check / request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️ Location permission denied by user.');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        print('⚠️ Location permission permanently denied.');
        return null;
      }

      // 3. Fetch position (15-second timeout)
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      print('⚠️ DriverLocationUpdateService._getPosition error: $e');
      return null;
    }
  }

  /// Call when the service is no longer needed to cancel any running timers.
  void dispose() {
    stopLocationUpdates();
  }
}
