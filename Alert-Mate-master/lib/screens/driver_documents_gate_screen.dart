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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
          onPressed: () {
            // Since this screen is often shown via pushReplacement, we explicitly navigate back.
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const AuthScreen(
                  initialDashboardIndex: 0, // Driver
                  initialIsSignIn: true,
                ),
              ),
            );
          },
        ),
        title: const Text(
          'Driver Verification',
          style: TextStyle(color: Colors.black87),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upload CNIC & driving license',
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You must be approved by admin before you can access the driver dashboard.',
                style: TextStyle(fontSize: isMobile ? 13 : 14, color: Colors.black54),
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
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified, color: Colors.green.shade700),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Approved! Redirecting to dashboard…',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                              // Try assignment again (safe if nothing available).
                              await FirebaseFirestore.instance.collection('users').doc(user.id).get();
                              try {
                                await _vehicleService.assignOwnerPendingVehicles(user.id, user.email);
                                await _vehicleService.assignGeneralPendingVehiclesToNewDriver(user.id, user.email);
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Continue to dashboard'),
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

