import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';
import '../models/emergency_contact.dart';
import 'phone_input_formatters.dart';

/// Resolves which emergency contact to dial (Primary first, then Secondary).
class EmergencyCallHelper {
  EmergencyCallHelper._();

  static const String masterToggleOffMessage =
      'Please enable Emergency Contacts to allow calling.';
  static const String noContactsMessage =
      'No Emergency Contacts found. Please Add a Contact.';
  static const String contactsDisabledMessage =
      'You have emergency contacts, but they are disabled. Please enable at least one contact to allow calling.';

  /// @deprecated Use [masterToggleOffMessage].
  static const String disabledMessage = masterToggleOffMessage;

  static List<EmergencyContact> activeContacts(List<EmergencyContact> contacts) {
    return contacts
        .where((c) => c.enabled && c.phone.trim().isNotEmpty)
        .toList();
  }

  static List<EmergencyContact> activePrimary(List<EmergencyContact> contacts) {
    return activeContacts(contacts).where((c) => c.isPrimary).toList();
  }

  static List<EmergencyContact> activeSecondary(List<EmergencyContact> contacts) {
    return activeContacts(contacts).where((c) => c.isSecondary).toList();
  }

  /// First enabled contact for status display (legacy).
  static EmergencyContact? pickDialContact(List<EmergencyContact> contacts) {
    final primary = activePrimary(contacts);
    if (primary.isNotEmpty) return primary.first;
    final secondary = activeSecondary(contacts);
    if (secondary.isNotEmpty) return secondary.first;
    return null;
  }

  static bool needsContactPicker(List<EmergencyContact> contacts) {
    final primary = activePrimary(contacts);
    if (primary.length > 1) return true;
    if (primary.isNotEmpty) return false;
    return activeSecondary(contacts).length > 1;
  }

  static String dialStatusMessage(List<EmergencyContact> contacts) {
    final primary = activePrimary(contacts);
    if (primary.length == 1) {
      final c = primary.first;
      return '${c.name} will be called.';
    }
    if (primary.length > 1) {
      return 'You have ${primary.length} Primary Contacts. You will choose who to call.';
    }
    final secondary = activeSecondary(contacts);
    if (secondary.length == 1) {
      final c = secondary.first;
      return '${c.name} will be called.';
    }
    if (secondary.length > 1) {
      return 'You have ${secondary.length} Secondary Contacts. You will choose who to call.';
    }
    return 'Enable at least ONE Contact to place a call.';
  }

  /// Primary tier first; auto-dial if one primary; picker if multiple.
  /// Secondary only when no enabled primary exists.
  static Future<EmergencyContact?> resolveDialTarget(
    BuildContext context,
    List<EmergencyContact> contacts,
  ) async {
    final primary = activePrimary(contacts);
    if (primary.isNotEmpty) {
      if (primary.length == 1) return primary.first;
      return _showContactPicker(
        context,
        candidates: primary,
        title: 'Choose Contact',
        subtitle: 'Multiple Primary Contacts are enabled. Who should we call?',
      );
    }

    final secondary = activeSecondary(contacts);
    if (secondary.isNotEmpty) {
      if (secondary.length == 1) return secondary.first;
      return _showContactPicker(
        context,
        candidates: secondary,
        title: 'Choose secondary contact',
        subtitle: 'No primary contact is enabled. Who should we call?',
      );
    }

    return null;
  }

  static Future<EmergencyContact?> _showContactPicker(
    BuildContext context, {
    required List<EmergencyContact> candidates,
    required String title,
    required String subtitle,
  }) async {
    if (candidates.length == 1) return candidates.first;
    if (!context.mounted) return null;

    return showDialog<EmergencyContact>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                ...candidates.map((c) {
                  final relation = c.relationship.trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.pop(ctx, c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.primaryLight,
                                child: Icon(
                                  Icons.person_outline,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      c.phone,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (relation.isNotEmpty)
                                      Text(
                                        relation,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.phone_outlined, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> attemptEmergencyCall({
    required BuildContext context,
    required bool emergencyCallsEnabled,
    required List<EmergencyContact> contacts,
  }) async {
    if (!emergencyCallsEnabled) {
      await _showAlert(context, masterToggleOffMessage);
      return;
    }

    if (contacts.isEmpty) {
      await _showAlert(context, noContactsMessage);
      return;
    }

    if (activeContacts(contacts).isEmpty) {
      await _showAlert(context, contactsDisabledMessage);
      return;
    }

    final target = await resolveDialTarget(context, contacts);
    if (target == null || !context.mounted) return;

    await dialPhone(context, target.phone);
  }

  static Future<void> dialPhone(BuildContext context, String rawPhone) async {
    final sanitized = sanitizePhoneForDial(rawPhone);
    if (sanitized.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No phone number available')),
        );
      }
      return;
    }

    final uri = Uri(scheme: 'tel', path: sanitized);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the phone dialer on this device')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start call: $e')),
        );
      }
    }
  }

  static Future<void> _showAlert(BuildContext context, String message) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emergency Call'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
