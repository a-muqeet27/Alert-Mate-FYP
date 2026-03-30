import 'package:cloud_firestore/cloud_firestore.dart';

class OwnerVehicleSubmission {
  final String id;
  final String ownerId;
  final String ownerEmail;
  final String ownerName;
  final String make;
  final String model;
  final String year;
  final String licensePlate;
  final String type;
  final bool willOwnerDrive;
  final String vehicleBookUrl;
  final String status; // pending_review | approved | rejected
  final String? rejectedReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  OwnerVehicleSubmission({
    required this.id,
    required this.ownerId,
    required this.ownerEmail,
    required this.ownerName,
    required this.make,
    required this.model,
    required this.year,
    required this.licensePlate,
    required this.type,
    required this.willOwnerDrive,
    required this.vehicleBookUrl,
    required this.status,
    this.rejectedReason,
    this.submittedAt,
    this.reviewedAt,
  });

  bool get isPending => status == 'pending_review';

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    return null;
  }

  factory OwnerVehicleSubmission.fromDoc(String id, Map<String, dynamic> map) {
    return OwnerVehicleSubmission(
      id: id,
      ownerId: map['ownerId'] ?? '',
      ownerEmail: map['ownerEmail'] ?? '',
      ownerName: map['ownerName'] ?? '',
      make: map['make'] ?? '',
      model: map['model'] ?? '',
      year: map['year']?.toString() ?? '',
      licensePlate: map['licensePlate'] ?? '',
      type: map['type'] ?? 'Car',
      willOwnerDrive: map['willOwnerDrive'] ?? false,
      vehicleBookUrl: map['vehicleBookUrl'] ?? '',
      status: map['status'] ?? 'pending_review',
      rejectedReason: map['rejectedReason'],
      submittedAt: _ts(map['submittedAt']),
      reviewedAt: _ts(map['reviewedAt']),
    );
  }
}

