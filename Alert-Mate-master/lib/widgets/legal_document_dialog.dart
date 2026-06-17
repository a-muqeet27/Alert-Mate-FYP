import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/legal_content.dart';

Future<void> showLegalDocumentDialog(
  BuildContext context, {
  required String title,
  required List<String> bullets,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: bullets
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('-  ', style: TextStyle(fontSize: 15)),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showPrivacyPolicyDialog(BuildContext context) {
  return showLegalDocumentDialog(
    context,
    title: LegalContent.privacyPolicyTitle,
    bullets: LegalContent.privacyPolicyBullets,
  );
}

Future<void> showTermsDialog(BuildContext context) {
  return showLegalDocumentDialog(
    context,
    title: LegalContent.termsTitle,
    bullets: LegalContent.termsBullets,
  );
}