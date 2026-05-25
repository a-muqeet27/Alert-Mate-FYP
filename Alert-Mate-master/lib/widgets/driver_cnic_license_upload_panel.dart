import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/vehicle_catalog.dart';
import '../models/driver_document_submission.dart';
import '../models/user.dart';
import '../services/driver_document_submission_service.dart';
import 'owner_form_dialog_ui.dart';

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
  String? _cnicFileName;
  String? _licenseFileName;
  bool _submitting = false;
  String? _localSubmissionStatus;
  String? _selectedVehicleType;

  @override
  void initState() {
    super.initState();
    if (VehicleCatalog.vehicleTypes.isNotEmpty) {
      _selectedVehicleType = VehicleCatalog.vehicleTypes.first;
    }
  }

  Future<Uint8List?> _readPdfBytes(PlatformFile file) async => file.bytes;

  Future<void> _pickPdf(String which) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final name = file.name.trim();
    if (!name.toLowerCase().endsWith('.pdf')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only PDF files are allowed'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final bytes = await _readPdfBytes(file);
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read the PDF file'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      if (which == 'cnic') {
        _cnicBytes = bytes;
        _cnicFileName = name;
      } else {
        _licenseBytes = bytes;
        _licenseFileName = name;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cnicBytes == null || _licenseBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CNIC and driving license PDFs are required'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final type = _selectedVehicleType?.trim();
    if (type == null || type.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your preferred vehicle type'),
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
        cnicFileName: _cnicFileName,
        licenseFileName: _licenseFileName,
        preferredVehicleType: type,
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
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
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

    final effectiveStatus = sub?.status ?? _localSubmissionStatus;
    final effectiveIsPending = effectiveStatus == 'pending_review';
    final effectiveIsApproved = sub?.isApproved ?? false;
    final effectiveIsRejected = sub?.isRejected ?? false;

    if (effectiveIsPending) {
      final pref = sub?.preferredTypeDisplay;
      return _statusCard(
        isMobile,
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFFF9800),
        title: 'Pending Admin Approval',
        body: pref != null && pref.isNotEmpty
            ? 'Your Documents are Under Review \n Preferred Type: $pref'
            : 'Your CNIC and driving license PDFs are being reviewed.',
      );
    }

    if (effectiveIsApproved) {
      final pref = sub?.preferredTypeDisplay;
      return _statusCard(
        isMobile,
        icon: Icons.verified_outlined,
        color: AppColors.success,
        title: 'Documents Approved',
        body: pref != null && pref.isNotEmpty
            ? 'Congratulations! A Pending $pref Vehicle will be Assigned When Available.'
            : 'Congratulations!',
      );
    }

    if (effectiveIsRejected) {
      final rejectedReason = sub?.rejectedReason;
      return Column(
        children: [
          _statusCard(
            isMobile,
            icon: Icons.error_outline,
            color: AppColors.danger,
            title: 'Documents Rejected',
            body: rejectedReason != null && rejectedReason.isNotEmpty
                ? rejectedReason
                : 'Please Re-Upload your CNIC and Driving License as PDF files.',
          ),
          const SizedBox(height: 16),
          _buildUploadForm(isMobile),
        ],
      );
    }

    return _buildUploadForm(isMobile);
  }

  Widget _buildSectionCard({
    required bool isMobile,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isMobile ? 16 : 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildUploadForm(bool isMobile) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionCard(
            isMobile: isMobile,
            icon: Icons.category_outlined,
            title: 'Preferred Vehicle Type *',
            subtitle: 'After Approval, Only a Vehicle of This Type will be Assigned to You.',
            child: OwnerFormDialogUi.listPanel(
              child: Column(
                children: VehicleCatalog.vehicleTypes
                    .map(
                      (type) => RadioListTile<String>(
                        value: type,
                        groupValue: _selectedVehicleType,
                        onChanged: (v) => setState(() => _selectedVehicleType = v),
                        activeColor: AppColors.primary,
                        secondary: Icon(VehicleCatalog.iconForType(type), color: AppColors.primary, size: 22),
                        title: Text(
                          type,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          SizedBox(height: isMobile ? 14 : 18),
          _buildSectionCard(
            isMobile: isMobile,
            icon: Icons.picture_as_pdf_outlined,
            title: 'Submit Documents',
            subtitle: 'Upload CNIC and Driving License as PDF Files Only.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _docUploadTile(
                  label: 'CNIC (Front & Back) *',
                  fileName: _cnicFileName,
                  done: _cnicBytes != null,
                  onTap: () => _pickPdf('cnic'),
                  isMobile: isMobile,
                ),
                const SizedBox(height: 10),
                _docUploadTile(
                  label: 'Driving License (Front & Back) *',
                  fileName: _licenseFileName,
                  done: _licenseBytes != null,
                  onTap: () => _pickPdf('license'),
                  isMobile: isMobile,
                ),
              ],
            ),
          ),
          SizedBox(height: isMobile ? 14 : 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: OwnerFormDialogUi.primaryButtonStyle.copyWith(
                minimumSize: WidgetStatePropertyAll(
                  Size(double.infinity, isMobile ? 48 : 50),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit for Approval'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _docUploadTile({
    required String label,
    required bool done,
    required VoidCallback onTap,
    required bool isMobile,
    String? fileName,
  }) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: isMobile ? 14 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: done ? AppColors.success.withValues(alpha: 0.5) : AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: done ? AppColors.success.withValues(alpha: 0.12) : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  done ? Icons.check_circle : Icons.picture_as_pdf_outlined,
                  color: done ? AppColors.success : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: isMobile ? 14 : 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (fileName != null && fileName.isNotEmpty)
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              Text(
                done ? 'Change' : 'Choose PDF',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
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
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45),
          ),
        ],
      ),
    );
  }
}
