import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/app_colors.dart';
import '../models/driver_document_submission.dart';
import '../models/user.dart';
import '../services/driver_document_submission_service.dart';

class DriverCnicLicenseUploadPanel extends StatefulWidget {
  final User user;
  final DriverDocumentSubmission? latestSubmission;

  const DriverCnicLicenseUploadPanel({
    Key? key,
    required this.user,
    required this.latestSubmission,
  }) : super(key: key);

  @override
  State<DriverCnicLicenseUploadPanel> createState() => _DriverCnicLicenseUploadPanelState();
}

class _DriverCnicLicenseUploadPanelState extends State<DriverCnicLicenseUploadPanel> {
  final _formKey = GlobalKey<FormState>();
  final _service = DriverDocumentSubmissionService();

  Uint8List? _cnicBytes;
  Uint8List? _licenseBytes;
  bool _submitting = false;
  String? _localSubmissionStatus; // for instant UI feedback

  Future<bool> _ensureGalleryPermission() async {
    if (kIsWeb) return true;

    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.android) {
      final photos = await Permission.photos.request();
      final storage = await Permission.storage.request();
      if (photos.isGranted || storage.isGranted) return true;
      return !(photos.isPermanentlyDenied || storage.isPermanentlyDenied) ? false : false;
    }

    if (platform == TargetPlatform.iOS) {
      final photos = await Permission.photos.request();
      return photos.isGranted;
    }

    return true;
  }

  Future<void> _pick(String which) async {
    final ok = await _ensureGalleryPermission();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please allow photo/gallery permission to upload documents.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;

    final bytes = await x.readAsBytes();
    setState(() {
      if (which == 'cnic') {
        _cnicBytes = bytes;
      } else {
        _licenseBytes = bytes;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cnicBytes == null || _licenseBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CNIC and driving license images are required'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _service.submitDocuments(
        driverId: widget.user.id,
        driverEmail: widget.user.email,
        driverName: widget.user.fullName.trim().isEmpty ? widget.user.email : widget.user.fullName,
        cnicBytes: _cnicBytes!,
        licenseBytes: _licenseBytes!,
      );
      setState(() => _localSubmissionStatus = 'pending_review');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Submitted for admin approval.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.latestSubmission;
    final isMobile = MediaQuery.of(context).size.width < 768;

    // If upload succeeded but Firestore stream hasn't refreshed yet, show pending instantly.
    final effectiveStatus = sub?.status ?? _localSubmissionStatus;
    final effectiveIsPending = effectiveStatus == 'pending_review';
    final effectiveIsApproved = sub?.isApproved ?? false;
    final effectiveIsRejected = sub?.isRejected ?? false;

    if (effectiveIsPending) {
      return _statusCard(
        isMobile,
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFFF9800),
        title: 'Pending admin approval',
        body: 'Your CNIC + driving license are being reviewed. You will get a vehicle after approval.',
      );
    }

    if (effectiveIsApproved) {
      return _statusCard(
        isMobile,
        icon: Icons.verified_outlined,
        color: const Color(0xFF4CAF50),
        title: 'Documents approved',
        body: 'Your documents are approved. Waiting for an approved vehicle to be assigned.',
      );
    }

    if (effectiveIsRejected) {
      final rejectedReason = sub?.rejectedReason;
      return Column(
        children: [
          _statusCard(
            isMobile,
            icon: Icons.error_outline,
            color: Colors.red,
            title: 'Documents rejected',
            body: rejectedReason != null && rejectedReason.isNotEmpty
                ? rejectedReason
                : 'Please re-upload your CNIC and driving license.',
          ),
          const SizedBox(height: 16),
          _uploadForm(isMobile),
        ],
      );
    }

    return _uploadForm(isMobile);
  }

  Widget _uploadForm(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.driverPrimary.withOpacity(0.35)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.perm_identity, color: AppColors.primary, size: isMobile ? 22 : 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Upload CNIC & License',
                    style: TextStyle(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Admin approval is required before any vehicle can be assigned to you.',
              style: TextStyle(fontSize: isMobile ? 12 : 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            _docRow('CNIC *', _cnicBytes != null, () => _pick('cnic'), isMobile),
            _docRow('Driving license *', _licenseBytes != null, () => _pick('license'), isMobile),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit for approval'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docRow(String label, bool done, VoidCallback onTap, bool isMobile) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: isMobile ? 13 : 14))),
          TextButton.icon(
            onPressed: onTap,
            icon: Icon(done ? Icons.check_circle : Icons.upload_file, size: 18, color: done ? Colors.green : AppColors.primary),
            label: Text(done ? 'Change' : 'Upload'),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(
    bool isMobile, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: isMobile ? 24 : 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 10 : 12),
          Text(body, style: TextStyle(fontSize: isMobile ? 13 : 14, color: Colors.black54, height: 1.4)),
        ],
      ),
    );
  }
}

