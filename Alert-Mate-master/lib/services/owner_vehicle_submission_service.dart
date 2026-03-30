import 'dart:typed_data';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/owner_vehicle_submission.dart';
import 'cloudinary_service.dart';
import 'vehicle_service.dart';

class OwnerVehicleSubmissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final VehicleService _vehicleService = VehicleService();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  static const String _collection = 'owner_vehicle_submissions';
  static const Duration _uploadTimeout = Duration(seconds: 90);
  static const Duration _firestoreTimeout = Duration(seconds: 30);

  Future<String> _uploadDoc({
    required String ownerId,
    required String label,
    required Uint8List bytes,
  }) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$label.jpg';
      return await _cloudinaryService
          .uploadBytes(bytes, fileName, 'owner_vehicle_docs/$ownerId')
          .timeout(_uploadTimeout);
    } on TimeoutException {
      throw Exception('Upload timed out. Check your internet and try again.');
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool> hasPendingSubmissionForOwner(String ownerId) async {
    final snap = await _firestore
        .collection(_collection)
        .where('ownerId', isEqualTo: ownerId)
        .where('status', isEqualTo: 'pending_review')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> submitVehicle({
    required String ownerId,
    required String ownerEmail,
    required String ownerName,
    required String make,
    required String model,
    required String year,
    required String licensePlate,
    required String type,
    required bool willOwnerDrive,
    required Uint8List vehicleBookBytes,
  }) async {
    // Allow multiple submissions; you can remove this if you want.
    // We keep it permissive for owners who add multiple vehicles.

    final vehicleBookUrl = await _uploadDoc(
      ownerId: ownerId,
      label: 'vehicle_book',
      bytes: vehicleBookBytes,
    );

    try {
      await _firestore.collection(_collection).add({
        'ownerId': ownerId,
        'ownerEmail': ownerEmail,
        'ownerName': ownerName,
        'make': make,
        'model': model,
        'year': year,
        'licensePlate': licensePlate,
        'type': type,
        'willOwnerDrive': willOwnerDrive,
        'vehicleBookUrl': vehicleBookUrl,
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

  Stream<List<OwnerVehicleSubmission>> watchPendingSubmissions() {
    // No where/orderBy here to avoid Firestore composite index requirements.
    // We filter/sort in Dart.
    return _firestore.collection(_collection).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => OwnerVehicleSubmission.fromDoc(d.id, d.data()))
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

    final ownerId = data['ownerId'] as String;
    final ownerEmail = (data['ownerEmail'] as String?) ?? '';
    final make = (data['make'] as String?) ?? '';
    final model = (data['model'] as String?) ?? '';
    final year = (data['year'] as String?) ?? '';
    final licensePlate = (data['licensePlate'] as String?) ?? '';
    final type = (data['type'] as String?) ?? 'Car';
    final willOwnerDrive = (data['willOwnerDrive'] as bool?) ?? false;
    final vehicleBookUrl = (data['vehicleBookUrl'] as String?) ?? '';

    final vehicleRef = await _firestore.collection('vehicles').add({
      'make': make,
      'model': model,
      'year': year,
      'licensePlate': licensePlate,
      'ownerId': ownerId,
      'ownerEmail': ownerEmail,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'Offline',
      'alertness': 0,
      'location': 'Unknown',
      'assignedDriverId': null,
      'assignedDriverEmail': null,
      'driverName': null,
      'pendingAssignment': !willOwnerDrive, // general pending pool
      'pendingOwnerAssignment': willOwnerDrive, // waiting for owner to become driver
      'lastUpdate': DateTime.now().toString(),
      'vehicleBookUrl': vehicleBookUrl,
    });

    await ref.update({
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
      'approvedVehicleId': vehicleRef.id,
    });

    // If owner will drive AND docs are already approved -> assign immediately.
    if (willOwnerDrive) {
      final ownerDoc = await _firestore.collection('users').doc(ownerId).get();
      final ownerApproved = (ownerDoc.data()?['driverDocsApproved'] as bool?) ?? false;
      if (ownerApproved) {
        // Ignore if owner already has a vehicle; assignVehicleToDriver will throw.
        try {
          await _vehicleService.assignVehicleToDriver(
            vehicleId: vehicleRef.id,
            driverId: ownerId,
            driverEmail: ownerEmail,
          );
        } catch (_) {}
      }
      return;
    }

    // General pool: assign to the first driver with approved docs who doesn't have a vehicle.
    final candidateSnap = await _firestore
        .collection('users')
        .where('driverDocsApproved', isEqualTo: true)
        .where('roles', arrayContains: 'driver')
        .limit(10)
        .get();

    for (final c in candidateSnap.docs) {
      final driverId = c.id;
      final driverEmail = (c.data()['email'] as String?) ?? '';

      try {
        await _vehicleService.assignVehicleToDriver(
          vehicleId: vehicleRef.id,
          driverId: driverId,
          driverEmail: driverEmail,
        );
        break;
      } catch (_) {
        // Driver already has vehicle; try next candidate.
      }
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

