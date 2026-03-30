import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/app_colors.dart';
import '../models/driver_vehicle_submission.dart';
import '../models/user.dart';
import '../services/driver_vehicle_submission_service.dart';

/// Shown when the driver has no assigned vehicle: upload documents and vehicle details, or pending/rejected states.
class DriverVehicleRegistrationPanel extends StatefulWidget {
  final User user;
  final DriverVehicleSubmission? latestSubmission;

  const DriverVehicleRegistrationPanel({
    Key? key,
    required this.user,
    required this.latestSubmission,
  }) : super(key: key);

  @override
  State<DriverVehicleRegistrationPanel> createState() => _DriverVehicleRegistrationPanelState();
}

class _DriverVehicleRegistrationPanelState extends State<DriverVehicleRegistrationPanel> {
  final _formKey = GlobalKey<FormState>();
  final _service = DriverVehicleSubmissionService();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _plateController = TextEditingController();
  String _vehicleType = 'Car';
  Uint8List? _cnicBytes;
  Uint8List? _licenseBytes;
  Uint8List? _regBytes;
  Uint8List? _insuranceBytes;
  bool _submitting = false;

  Future<bool> _ensureGalleryPermission() async {
    // Windows/macOS typically don't need explicit runtime photo permissions.
    if (kIsWeb) return true;

    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.android) {
      // Android 13+: photo access is usually `photos`. Older Android uses `storage`.
      final photos = await Permission.photos.request();
      final storage = await Permission.storage.request();
      if (photos.isGranted || storage.isGranted) return true;

      if (photos.isPermanentlyDenied || storage.isPermanentlyDenied) {
        return false;
      }
      return false;
    }

    if (platform == TargetPlatform.iOS) {
      final photos = await Permission.photos.request();
      return photos.isGranted;
    }

    return true;
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _plateController.dispose();
    super.dispose();
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
      switch (which) {
        case 'cnic':
          _cnicBytes = bytes;
          break;
        case 'license':
          _licenseBytes = bytes;
          break;
        case 'reg':
          _regBytes = bytes;
          break;
        case 'insurance':
          _insuranceBytes = bytes;
          break;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cnicBytes == null || _licenseBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CNIC and driving license images are required'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await _service.submitRegistration(
        driverId: widget.user.id,
        driverEmail: widget.user.email,
        driverName: widget.user.fullName.trim().isEmpty ? widget.user.email : widget.user.fullName,
        make: _makeController.text.trim(),
        model: _modelController.text.trim(),
        year: _yearController.text.trim(),
        licensePlate: _plateController.text.trim(),
        type: _vehicleType,
        cnicBytes: _cnicBytes!,
        licenseBytes: _licenseBytes!,
        vehicleRegistrationBytes: _regBytes,
        insuranceBytes: _insuranceBytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Submitted for admin approval. You will be notified when a vehicle is assigned.'),
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

    if (sub != null && sub.isPending) {
      return _statusCard(
        isMobile,
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFFF9800),
        title: 'Pending admin approval',
        body:
            'Your vehicle registration and documents (CNIC, license, etc.) are being reviewed. You cannot be assigned a vehicle until an administrator approves.',
      );
    }

    if (sub != null && sub.isApproved) {
      return _statusCard(
        isMobile,
        icon: Icons.verified_outlined,
        color: const Color(0xFF4CAF50),
        title: 'Documents approved',
        body:
            'Your documents were approved. If a vehicle is available in the fleet, it will appear here automatically. Otherwise, contact your administrator.',
      );
    }

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
                Icon(Icons.app_registration, color: AppColors.primary, size: isMobile ? 22 : 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Register your vehicle',
                    style: TextStyle(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isMobile ? 8 : 10),
            Text(
              'Provide vehicle details and upload CNIC, driving license, and optional documents. An admin must approve before a vehicle can be assigned.',
              style: TextStyle(fontSize: isMobile ? 12 : 13, color: Colors.black54),
            ),
            if (sub != null && sub.isRejected) ...[
              SizedBox(height: isMobile ? 12 : 14),
              Material(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.red.shade800, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sub.rejectedReason != null && sub.rejectedReason!.isNotEmpty
                              ? 'Previous submission was rejected: ${sub.rejectedReason}'
                              : 'Previous submission was rejected. Please update and submit again.',
                          style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SizedBox(height: isMobile ? 16 : 20),
            DropdownButtonFormField<String>(
              value: _vehicleType,
              decoration: const InputDecoration(labelText: 'Vehicle type *', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'Car', child: Text('Car')),
                DropdownMenuItem(value: 'Bus', child: Text('Bus')),
                DropdownMenuItem(value: 'Van', child: Text('Van')),
                DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                DropdownMenuItem(value: 'Rickshaw', child: Text('Rickshaw')),
              ],
              onChanged: (v) => setState(() => _vehicleType = v ?? 'Car'),
            ),
            SizedBox(height: isMobile ? 12 : 14),
            TextFormField(
              controller: _makeController,
              decoration: const InputDecoration(labelText: 'Make *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Required' : null,
            ),
            SizedBox(height: isMobile ? 12 : 14),
            TextFormField(
              controller: _modelController,
              decoration: const InputDecoration(labelText: 'Model *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            SizedBox(height: isMobile ? 12 : 14),
            TextFormField(
              controller: _yearController,
              decoration: const InputDecoration(labelText: 'Year *', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              validator: (v) => (v == null || v.trim().length < 4) ? 'Enter a valid year' : null,
            ),
            SizedBox(height: isMobile ? 12 : 14),
            TextFormField(
              controller: _plateController,
              decoration: const InputDecoration(labelText: 'License plate *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            SizedBox(height: isMobile ? 16 : 20),
            Text('Documents', style: TextStyle(fontWeight: FontWeight.w600, fontSize: isMobile ? 14 : 15)),
            const SizedBox(height: 8),
            _docRow('CNIC (front/back) *', _cnicBytes != null, () => _pick('cnic'), isMobile),
            _docRow('Driving license *', _licenseBytes != null, () => _pick('license'), isMobile),
            _docRow('Vehicle registration (optional)', _regBytes != null, () => _pick('reg'), isMobile),
            _docRow('Insurance (optional)', _insuranceBytes != null, () => _pick('insurance'), isMobile),
            SizedBox(height: isMobile ? 16 : 20),
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
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: isMobile ? 13 : 14)),
          ),
          TextButton.icon(
            onPressed: onTap,
            icon: Icon(done ? Icons.check_circle : Icons.upload_file, size: 18, color: done ? Colors.green : AppColors.primary),
            label: Text(done ? 'Change' : 'Upload'),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(bool isMobile, {required IconData icon, required Color color, required String title, required String body}) {
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
