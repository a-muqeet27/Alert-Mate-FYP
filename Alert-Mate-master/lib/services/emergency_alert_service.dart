import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'in_app_notification_service.dart';

/// Service for managing emergency alerts from passengers
class EmergencyAlertService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _firestoreTimeout = Duration(seconds: 25);

  /// Send an emergency alert
  /// Creates an alert document that all dashboards can listen to
  Future<String> sendEmergencyAlert({
    required String passengerId,
    required String passengerName,
    required String driverId,
    required String driverName,
    required String vehiclePlate,
    required String vehicleMake,
    required String vehicleModel,
    required String category,
    String? ownerId,
    String? ownerName,
  }) async {
    try {
      final alertRef = _firestore.collection('emergency_alerts').doc();
      final alertId = alertRef.id;

      await alertRef.set({
        'id': alertId,
        'passengerId': passengerId,
        'passengerName': passengerName,
        'driverId': driverId,
        'driverName': driverName,
        'vehiclePlate': vehiclePlate,
        'vehicleMake': vehicleMake,
        'vehicleModel': vehicleModel,
        'category': category,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'status': 'active', // active, acknowledged, resolved
        'createdAt': FieldValue.serverTimestamp(),
        'acknowledgedAt': null,
        'acknowledgedBy': null,
        'resolvedAt': null,
      }).timeout(_firestoreTimeout);

      try {
        await InAppNotificationService.instance.notifyEmergencyAlertRecipients(
          emergencyAlertId: alertId,
          driverId: driverId,
          ownerId: ownerId,
          passengerName: passengerName,
          licensePlate: vehiclePlate,
          vehicleMake: vehicleMake,
          vehicleModel: vehicleModel,
          category: category,
        );
      } catch (e) {
        print('⚠️ EmergencyAlertService: in-app notification fan-out failed: $e');
      }

      print('✅ EmergencyAlertService: Alert created - $alertId');
      return alertId;
    } catch (e) {
      print('❌ EmergencyAlertService.sendEmergencyAlert error: $e');
      rethrow;
    }
  }

  /// Acknowledge an alert (mark as seen)
  Future<void> acknowledgeAlert(String alertId, String acknowledgedBy) async {
    try {
      await _firestore.collection('emergency_alerts').doc(alertId).update({
        'status': 'acknowledged',
        'acknowledgedAt': FieldValue.serverTimestamp(),
        'acknowledgedBy': acknowledgedBy,
      });
      print('✅ EmergencyAlertService: Alert acknowledged - $alertId');
    } catch (e) {
      print('❌ EmergencyAlertService.acknowledgeAlert error: $e');
      rethrow;
    }
  }

  /// Resolve an alert (mark as handled)
  Future<void> resolveAlert(String alertId) async {
    try {
      await _firestore.collection('emergency_alerts').doc(alertId).update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      print('✅ EmergencyAlertService: Alert resolved - $alertId');
    } catch (e) {
      print('❌ EmergencyAlertService.resolveAlert error: $e');
      rethrow;
    }
  }

  /// Stream active alerts for a specific driver
  Stream<List<Map<String, dynamic>>> streamDriverAlerts(String driverId) {
    return _firestore
        .collection('emergency_alerts')
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList());
  }

  /// Stream active alerts for a specific owner
  Stream<List<Map<String, dynamic>>> streamOwnerAlerts(String ownerId) {
    return _firestore
        .collection('emergency_alerts')
        .where('ownerId', isEqualTo: ownerId)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList());
  }

  /// Stream all active alerts (for admin)
  Stream<List<Map<String, dynamic>>> streamAllActiveAlerts() {
    return _firestore
        .collection('emergency_alerts')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList());
  }

  /// Get alert count for a user
  Future<int> getActiveAlertCount(String userId, String userRole) async {
    try {
      Query query = _firestore
          .collection('emergency_alerts')
          .where('status', isEqualTo: 'active');

      if (userRole == 'driver') {
        query = query.where('driverId', isEqualTo: userId);
      } else if (userRole == 'owner') {
        query = query.where('ownerId', isEqualTo: userId);
      }
      // Admin sees all alerts (no additional filter)

      final snapshot = await query.get();
      return snapshot.docs.length;
    } catch (e) {
      print('❌ EmergencyAlertService.getActiveAlertCount error: $e');
      return 0;
    }
  }
}
