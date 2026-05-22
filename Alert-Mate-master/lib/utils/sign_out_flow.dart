import 'package:flutter/material.dart';

import '../auth_screen.dart';
import '../constants/app_colors.dart';
import '../screens/admin_auth_screen.dart';
import '../services/firebase_auth_service.dart';
import 'page_transitions.dart';

/// Shows a confirmation dialog. Returns true only if the user confirms.
Future<bool> showSignOutConfirmationDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign Out?'),
      content: const Text(
        'You will be Signed-Out of ALERT MATE. You will need to Sign-In again to access your Dashboard.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Sign Out'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Confirms, signs out of Firebase, then replaces the stack with [AuthScreen].
Future<void> performSignOutAndGoToAuth(BuildContext context) async {
  await _performSignOutAndNavigate(context, const AuthScreen());
}

/// Signs out and returns to the admin web portal login screen.
Future<void> performSignOutAndGoToAdminAuth(BuildContext context) async {
  await _performSignOutAndNavigate(context, const AdminAuthScreen());
}

Future<void> _performSignOutAndNavigate(
  BuildContext context,
  Widget landingScreen,
) async {
  if (!await showSignOutConfirmationDialog(context)) return;
  if (!context.mounted) return;
  try {
    await FirebaseAuthService().signOut();
  } catch (_) {
    // Still navigate so the user is not stuck on a broken session UI.
  }
  if (!context.mounted) return;
  Navigator.pushReplacement(
    context,
    FadeScalePageRoute(page: landingScreen),
  );
}
