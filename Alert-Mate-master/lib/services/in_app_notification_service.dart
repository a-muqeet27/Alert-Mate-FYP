import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Persists one row per recipient in Firestore; dashboards listen and show SnackBars.
class InAppNotificationService {
  InAppNotificationService._();
  static final InAppNotificationService instance = InAppNotificationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'user_notifications';
  static const Duration _writeTimeout = Duration(seconds: 25);

  Future<Set<String>> _adminUserIds() async {
    final ids = <String>{};
    void addAll(QuerySnapshot<Map<String, dynamic>> snap) {
      for (final d in snap.docs) {
        ids.add(d.id);
      }
    }

    try {
      addAll(await _firestore.collection('users').where('roles', arrayContains: 'admin').get().timeout(_writeTimeout));
    } catch (_) {}
    try {
      addAll(await _firestore.collection('users').where('activeRole', isEqualTo: 'admin').get().timeout(_writeTimeout));
    } catch (_) {}
    try {
      addAll(await _firestore.collection('users').where('role', isEqualTo: 'admin').get().timeout(_writeTimeout));
    } catch (_) {}

    return ids;
  }

  Map<String, dynamic> _payload({
    required String userId,
    required String title,
    required String body,
    required String type,
  }) =>
      <String, dynamic>{
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Future<void> _batchWrite(Set<String> userIds, Map<String, dynamic> template) async {
    if (userIds.isEmpty) return;
    final payloads = userIds.map((uid) => _payload(userId: uid, title: template['title']! as String, body: template['body']! as String, type: template['type']! as String));
    WriteBatch batch = _firestore.batch();
    var n = 0;
    for (final docData in payloads) {
      batch.set(_firestore.collection(_collection).doc(), docData);
      n++;
      if (n >= 400) {
        await batch.commit().timeout(_writeTimeout);
        batch = _firestore.batch();
        n = 0;
      }
    }
    if (n > 0) {
      await batch.commit().timeout(_writeTimeout);
    }
  }

  /// Driver, optional vehicle owner, and all admin accounts.
  Future<void> notifyEmergencyAlertRecipients({
    required String emergencyAlertId,
    required String driverId,
    String? ownerId,
    required String passengerName,
    required String licensePlate,
    required String vehicleMake,
    required String vehicleModel,
    required String category,
  }) async {
    final plate = licensePlate.trim();
    final makeModel = '$vehicleMake $vehicleModel'.trim();
    final title = 'Emergency alert: $category';
    final body =
        'Passenger $passengerName reported "$category" for vehicle $makeModel (plate $plate). Please respond immediately.';

    final targets = <String>{driverId};
    if (ownerId != null && ownerId.isNotEmpty) targets.add(ownerId);
    targets.addAll(await _adminUserIds());

    WriteBatch batch = _firestore.batch();
    var n = 0;
    for (final uid in targets) {
      batch.set(_firestore.collection(_collection).doc(), <String, dynamic>{
        'userId': uid,
        'title': title,
        'body': body,
        'type': 'emergency_alert',
        'read': false,
        'emergencyAlertId': emergencyAlertId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      n++;
      if (n >= 400) {
        await batch.commit().timeout(_writeTimeout);
        batch = _firestore.batch();
        n = 0;
      }
    }
    if (n > 0) {
      await batch.commit().timeout(_writeTimeout);
    }
  }

  Future<void> notifyDriverDocumentsApproved({required String driverId, required String driverName}) async {
    final name = driverName.trim().isEmpty ? 'Driver' : driverName.trim();
    await _batchWrite({driverId}, <String, dynamic>{
      'title': 'Documents Approved',
      'body':
          '$name: admin approved your CNIC and driving licence. You can proceed with vehicle assignment.',
      'type': 'driver_docs_approved',
    });
  }

  Future<void> notifyDriverDocumentsRejected({
    required String driverId,
    required String driverName,
    String? reason,
  }) async {
    final name = driverName.trim().isEmpty ? 'Driver' : driverName.trim();
    final suffix = (reason != null && reason.trim().isNotEmpty) ? ' Reason: ${reason.trim()}.' : '';
    await _batchWrite({driverId}, <String, dynamic>{
      'title': 'Documents Rejected',
      'body': '$name: your CNIC and licence submission was rejected.$suffix Please re-upload.',
      'type': 'driver_docs_rejected',
    });
  }

  Future<void> notifyOwnerVehicleApproved({
    required String ownerId,
    required String ownerName,
    required String licensePlate,
    required String make,
    required String model,
  }) async {
    final plate = licensePlate.trim();
    final name = ownerName.trim().isEmpty ? 'Owner' : ownerName.trim();
    await _batchWrite({ownerId}, <String, dynamic>{
      'title': 'Vehicle registration approved',
      'body': '$name: your vehicle registration (plate $plate, $make $model) was approved.',
      'type': 'owner_vehicle_approved',
    });
  }

  Future<void> notifyOwnerVehicleRejected({
    required String ownerId,
    required String ownerName,
    required String licensePlate,
    String? reason,
  }) async {
    final plate = licensePlate.trim();
    final name = ownerName.trim().isEmpty ? 'Owner' : ownerName.trim();
    final suffix = (reason != null && reason.trim().isNotEmpty) ? ' Reason: ${reason.trim()}.' : '';
    await _batchWrite({ownerId}, <String, dynamic>{
      'title': 'Vehicle registration rejected',
      'body': '$name: your vehicle submission for plate $plate was rejected.$suffix',
      'type': 'owner_vehicle_rejected',
    });
  }
}
