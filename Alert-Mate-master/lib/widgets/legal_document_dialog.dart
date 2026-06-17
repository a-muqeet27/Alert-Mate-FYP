import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/legal_content.dart';
import '../utils/dashboard_responsive.dart';
import 'dashboard_detail_dialog_theme.dart';

Future<void> showLegalDocumentDialog(
  BuildContext context, {
  required String title,
  required List<String> bullets,
  required IconData icon,
  required Color accentColor,
}) {
  final isMobile = DashboardLayout.isMobile(context);
  final maxHeight = MediaQuery.sizeOf(context).height * (isMobile ? 0.82 : 0.78);
  final maxWidth = isMobile ? double.infinity : 560.0;

  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 20 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DashboardDetailDialogTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowMedium,
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LegalDocumentHeader(
                title: title,
                icon: icon,
                accentColor: accentColor,
                isMobile: isMobile,
                onClose: () => Navigator.pop(dialogContext),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 20,
                    isMobile ? 14 : 18,
                    isMobile ? 16 : 20,
                    isMobile ? 8 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < bullets.length; i++) ...[
                        _LegalDocumentBulletCard(
                          index: i + 1,
                          text: bullets[i],
                          accentColor: accentColor,
                          isMobile: isMobile,
                        ),
                        if (i < bullets.length - 1) SizedBox(height: isMobile ? 10 : 12),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 16 : 20,
                  8,
                  isMobile ? 16 : 20,
                  isMobile ? 16 : 18,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LegalDocumentHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final bool isMobile;
  final VoidCallback onClose;

  const _LegalDocumentHeader({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.isMobile,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 20, isMobile ? 16 : 18, 12, isMobile ? 16 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor,
            Color.lerp(accentColor, Colors.black, 0.18)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: Colors.white, size: isMobile ? 22 : 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 18 : 20,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Please read the following points carefully.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: isMobile ? 12 : 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Close',
            icon: Icon(
              Icons.close_rounded,
              color: Colors.white.withValues(alpha: 0.92),
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalDocumentBulletCard extends StatelessWidget {
  final int index;
  final String text;
  final Color accentColor;
  final bool isMobile;

  const _LegalDocumentBulletCard({
    required this.index,
    required this.text,
    required this.accentColor,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isMobile ? 28 : 30,
            height: isMobile ? 28 : 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                color: accentColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: isMobile ? 13.5 : 14,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showPrivacyPolicyDialog(BuildContext context) {
  return showLegalDocumentDialog(
    context,
    title: LegalContent.privacyPolicyTitle,
    bullets: LegalContent.privacyPolicyBullets,
    icon: Icons.privacy_tip_outlined,
    accentColor: AppColors.primary,
  );
}

Future<void> showTermsDialog(BuildContext context) {
  return showLegalDocumentDialog(
    context,
    title: LegalContent.termsTitle,
    bullets: LegalContent.termsBullets,
    icon: Icons.gavel_outlined,
    accentColor: AppColors.azure,
  );
}
