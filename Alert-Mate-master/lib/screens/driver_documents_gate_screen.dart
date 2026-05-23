import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/user.dart';
import '../services/driver_document_submission_service.dart';
import '../services/vehicle_service.dart';
import '../widgets/driver_cnic_license_upload_panel.dart';
import '../dashboards/driver_dashboard.dart';
import '../auth_screen.dart';

class DriverDocumentsGateScreen extends StatelessWidget {
  final User user;

  DriverDocumentsGateScreen({Key? key, required this.user}) : super(key: key);

  final DriverDocumentSubmissionService _docService = DriverDocumentSubmissionService();
  final VehicleService _vehicleService = VehicleService();

  Stream<bool> _docsApprovedStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.id)
        .snapshots()
        .map((d) => (d.data()?['driverDocsApproved'] as bool?) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const AuthScreen(
                  initialDashboardIndex: 0,
                  initialIsSignIn: true,
                ),
              ),
            );
          },
        ),
        title: const Text(
          'Driver Verification',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.verified_user_outlined, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Upload CNIC & Driving License and Choose your Preferred Vehicle',
                            style: TextStyle(
                              fontSize: isMobile ? 18 : 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder(
                stream: _docService.watchLatestForDriver(user.id),
                builder: (context, subSnap) {
                  return DriverCnicLicenseUploadPanel(
                    user: user,
                    latestSubmission: subSnap.data,
                  );
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<bool>(
                stream: _docsApprovedStream(),
                builder: (context, approvedSnap) {
                  final approved = approvedSnap.data ?? false;
                  if (!approved) return const SizedBox.shrink();

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: AppColors.success),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Approved! You can Continue to the Dashboard.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              StreamBuilder<bool>(
                stream: _docsApprovedStream(),
                builder: (context, approvedSnap) {
                  final approved = approvedSnap.data ?? false;
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: approved
                          ? () async {
                              try {
                                final sub = await _docService.watchLatestForDriver(user.id).first;
                                final preferredType = sub?.preferredVehicleType ??
                                    sub?.preferredTypeDisplay;
                                if (preferredType != null && preferredType.isNotEmpty) {
                                  await _vehicleService.assignPendingVehicleByType(
                                    preferredType: preferredType,
                                    driverId: user.id,
                                    driverEmail: user.email,
                                  );
                                } else {
                                  final preferredId = sub?.preferredVehicleId;
                                  if (preferredId != null && preferredId.isNotEmpty) {
                                    await _vehicleService.assignPreferredVehicleToDriver(
                                      vehicleId: preferredId,
                                      driverId: user.id,
                                      driverEmail: user.email,
                                    );
                                  }
                                }
                              } catch (_) {}

                              try {
                                await _docService.markDriverDocsGateCompleted(user.id);
                              } catch (_) {}

                              if (context.mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => DriverDashboard(user: user)),
                                );
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Continue to Dashboard'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
