import 'package:cloud_firestore/cloud_firestore.dart';

class DriverVehicleSubmission {
  final String id;
  final String driverId;
  final String driverEmail;
  final String driverName;
  final String make;
  final String model;
  final String year;
  final String licensePlate;
  final String type;
  final String cnicUrl;
  final String licenseUrl;
  final String? vehicleRegistrationUrl;
  final String? insuranceUrl;
  final String status;
  final String? rejectedReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  DriverVehicleSubmission({
    required this.id,
    required this.driverId,
    required this.driverEmail,
    required this.driverName,
    required this.make,
    required this.model,
    required this.year,
    required this.licensePlate,
    required this.type,
    required this.cnicUrl,
    required this.licenseUrl,
    this.vehicleRegistrationUrl,
    this.insuranceUrl,
    required this.status,
    this.rejectedReason,
    this.submittedAt,
    this.reviewedAt,
  });

  bool get isPending => status == 'pending_review';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory DriverVehicleSubmission.fromDoc(String id, Map<String, dynamic> map) {
    return DriverVehicleSubmission(
      id: id,
      driverId: map['driverId'] ?? '',
      driverEmail: map['driverEmail'] ?? '',
      driverName: map['driverName'] ?? '',
      make: map['make'] ?? '',
      model: map['model'] ?? '',
      year: map['year']?.toString() ?? '',
      licensePlate: map['licensePlate'] ?? '',
      type: map['type'] ?? 'Car',
      cnicUrl: map['cnicUrl'] ?? '',
      licenseUrl: map['licenseUrl'] ?? '',
      vehicleRegistrationUrl: map['vehicleRegistrationUrl'],
      insuranceUrl: map['insuranceUrl'],
      status: map['status'] ?? 'pending_review',
      rejectedReason: map['rejectedReason'],
      submittedAt: _ts(map['submittedAt']),
      reviewedAt: _ts(map['reviewedAt']),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    return null;
  }
}
