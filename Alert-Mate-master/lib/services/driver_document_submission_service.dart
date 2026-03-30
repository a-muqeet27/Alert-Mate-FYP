import 'dart:typed_data';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_document_submission.dart';
import 'cloudinary_service.dart';
import 'vehicle_service.dart';

class DriverDocumentSubmissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final VehicleService _vehicleService = VehicleService();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  static const String _collection = 'driver_document_submissions';
  static const Duration _uploadTimeout = Duration(seconds: 90);
  static const Duration _firestoreTimeout = Duration(seconds: 30);

  Future<bool> hasPendingSubmission(String driverId) async {
    final snap = await _firestore
        .collection(_collection)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'pending_review')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<String> _uploadDoc({
    required String driverId,
    required String label,
    required Uint8List bytes,
  }) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$label.jpg';
      return await _cloudinaryService
          .uploadBytes(bytes, fileName, 'driver_document_docs/$driverId')
          .timeout(_uploadTimeout);
    } on TimeoutException {
      throw Exception('Upload timed out. Check your internet and try again.');
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> submitDocuments({
    required String driverId,
    required String driverEmail,
    required String driverName,
    required Uint8List cnicBytes,
    required Uint8List licenseBytes,
  }) async {
    final cnicUrl = await _uploadDoc(driverId: driverId, label: 'cnic', bytes: cnicBytes);
    final licenseUrl = await _uploadDoc(driverId: driverId, label: 'license', bytes: licenseBytes);

    try {
      await _firestore.collection(_collection).add({
        'driverId': driverId,
        'driverEmail': driverEmail,
        'driverName': driverName,
        'cnicUrl': cnicUrl,
        'licenseUrl': licenseUrl,
        'status': 'pending_review',
        'submittedAt': FieldValue.serverTimestamp(),
      }).timeout(_firestoreTimeout);
    } on TimeoutException {
      throw Exception('Could not save submission. Please try again.');
    } on FirebaseException catch (e) {
      throw Exception(e.message ?? 'Could not save submission (${e.code}).');
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Stream<DriverDocumentSubmission?> watchLatestForDriver(String driverId) {
    return _firestore
        .collection(_collection)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final list = snap.docs
          .map((d) => DriverDocumentSubmission.fromDoc(d.id, d.data()))
          .toList();
      list.sort((a, b) {
        final da = a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
      return list.isEmpty ? null : list.first;
    });
  }

  Stream<List<DriverDocumentSubmission>> watchPendingSubmissions() {
    // No where/orderBy here to avoid Firestore composite index requirements.
    // We filter/sort in Dart.
    return _firestore.collection(_collection).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => DriverDocumentSubmission.fromDoc(d.id, d.data()))
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
    if ((data['status'] as String?) != 'pending_review') {
      throw Exception('Submission is not pending');
    }

    final driverId = data['driverId'] as String;
    final email = (data['driverEmail'] as String?) ?? '';

    await ref.update({
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    // Mark in user doc so vehicle assignment/queue can depend on it.
    await _firestore.collection('users').doc(driverId).update({
      'driverDocsApproved': true,
      'driverDocsReviewedAt': FieldValue.serverTimestamp(),
    });

    // Assign the next available vehicle (only after admin approval).
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

