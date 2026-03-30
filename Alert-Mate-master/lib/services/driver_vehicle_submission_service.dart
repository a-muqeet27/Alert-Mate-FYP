import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/driver_vehicle_submission.dart';
import 'vehicle_service.dart';

class DriverVehicleSubmissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final VehicleService _vehicleService = VehicleService();

  static const String _collection = 'driver_vehicle_submissions';

  Future<String> _uploadDocument({
    required String driverId,
    required String label,
    required Uint8List bytes,
  }) async {
    final name = '${DateTime.now().millisecondsSinceEpoch}_$label';
    final ref = FirebaseStorage.instance.ref().child('driver_vehicle_docs/$driverId/$name');
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  /// Returns true if driver already has a submission awaiting admin review.
  Future<bool> hasPendingSubmission(String driverId) async {
    final snap = await _firestore
        .collection(_collection)
        .where('driverId', isEqualTo: driverId)
        .get();
    return snap.docs.any((d) {
      final s = d.data()['status'] as String? ?? '';
      return s == 'pending_review';
    });
  }

  Future<void> submitRegistration({
    required String driverId,
    required String driverEmail,
    required String driverName,
    required String make,
    required String model,
    required String year,
    required String licensePlate,
    required String type,
    required Uint8List cnicBytes,
    required Uint8List licenseBytes,
    Uint8List? vehicleRegistrationBytes,
    Uint8List? insuranceBytes,
  }) async {
    if (await hasPendingSubmission(driverId)) {
      throw Exception('You already have a registration pending approval.');
    }

    final cnicUrl = await _uploadDocument(driverId: driverId, label: 'cnic', bytes: cnicBytes);
    final licenseUrl = await _uploadDocument(driverId: driverId, label: 'license', bytes: licenseBytes);
    String? regUrl;
    String? insUrl;
    if (vehicleRegistrationBytes != null) {
      regUrl = await _uploadDocument(driverId: driverId, label: 'vehicle_reg', bytes: vehicleRegistrationBytes);
    }
    if (insuranceBytes != null) {
      insUrl = await _uploadDocument(driverId: driverId, label: 'insurance', bytes: insuranceBytes);
    }

    await _firestore.collection(_collection).add({
      'driverId': driverId,
      'driverEmail': driverEmail,
      'driverName': driverName,
      'make': make,
      'model': model,
      'year': year,
      'licensePlate': licensePlate,
      'type': type,
      'cnicUrl': cnicUrl,
      'licenseUrl': licenseUrl,
      'vehicleRegistrationUrl': regUrl,
      'insuranceUrl': insUrl,
      'status': 'pending_review',
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Latest submission for this driver (any status), for UI.
  Stream<DriverVehicleSubmission?> watchLatestForDriver(String driverId) {
    return _firestore
        .collection(_collection)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final sorted = [...snap.docs]..sort((a, b) {
          final ta = a.data()['submittedAt'];
          final tb = b.data()['submittedAt'];
          final da = ta is Timestamp ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          final db = tb is Timestamp ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
      final doc = sorted.first;
      return DriverVehicleSubmission.fromDoc(doc.id, doc.data());
    });
  }

  /// Real-time pending submissions for admin (sorted client-side).
  Stream<List<DriverVehicleSubmission>> watchPendingSubmissions() {
    return _firestore.collection(_collection).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => DriverVehicleSubmission.fromDoc(d.id, d.data()))
          .where((s) => s.isPending)
          .toList();
      list.sort((a, b) {
        final da = a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
      return list;
    });
  }

  Future<void> approveSubmission(String submissionId) async {
    final ref = _firestore.collection(_collection).doc(submissionId);
    final doc = await ref.get();
    if (!doc.exists) throw Exception('Submission not found');
    final data = doc.data()!;
    if (data['status'] != 'pending_review') {
      throw Exception('Submission is not pending');
    }
    final driverId = data['driverId'] as String;
    final email = data['driverEmail'] as String? ?? '';

    await ref.update({
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    final ownerAssigned = await _vehicleService.assignOwnerPendingVehicles(driverId, email);
    if (ownerAssigned.isEmpty) {
      await _vehicleService.assignGeneralPendingVehiclesToNewDriver(driverId, email);
    }
  }

  Future<void> rejectSubmission(String submissionId, {String? reason}) async {
    await _firestore.collection(_collection).doc(submissionId).update({
      'status': 'rejected',
      'rejectedReason': reason,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
  }
}
