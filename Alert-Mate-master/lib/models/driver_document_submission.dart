import 'package:cloud_firestore/cloud_firestore.dart';

class DriverDocumentSubmission {
  final String id;
  final String driverId;
  final String driverEmail;
  final String driverName;
  final String cnicUrl;
  final String licenseUrl;
  final String status; // pending_review | approved | rejected
  final String? rejectedReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  DriverDocumentSubmission({
    required this.id,
    required this.driverId,
    required this.driverEmail,
    required this.driverName,
    required this.cnicUrl,
    required this.licenseUrl,
    required this.status,
    this.rejectedReason,
    this.submittedAt,
    this.reviewedAt,
  });

  bool get isPending => status == 'pending_review';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory DriverDocumentSubmission.fromDoc(String id, Map<String, dynamic> map) {
    return DriverDocumentSubmission(
      id: id,
      driverId: map['driverId'] ?? '',
      driverEmail: map['driverEmail'] ?? '',
      driverName: map['driverName'] ?? '',
      cnicUrl: map['cnicUrl'] ?? '',
      licenseUrl: map['licenseUrl'] ?? '',
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

