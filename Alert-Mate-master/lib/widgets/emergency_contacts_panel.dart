import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../models/emergency_contact.dart';
import '../models/user.dart';
import '../services/emergency_contact_service.dart';
import '../utils/dashboard_responsive.dart';
import '../utils/emergency_call_helper.dart';
import '../utils/phone_input_formatters.dart';
import 'emergency_contact_ui.dart';
import 'owner_form_dialog_ui.dart';

/// Shared emergency contacts UI: add/edit form, list, user call toggle, dialer rules.
class EmergencyContactsPanel extends StatefulWidget {
  final User user;
  final String userRole;

  const EmergencyContactsPanel({
    super.key,
    required this.user,
    required this.userRole,
  });

  @override
  State<EmergencyContactsPanel> createState() => _EmergencyContactsPanelState();
}

class _EmergencyContactsPanelState extends State<EmergencyContactsPanel> {
  final EmergencyContactService _service = EmergencyContactService();

  int _enabledCount(List<EmergencyContact> contacts) =>
      contacts.where((c) => c.enabled).length;

  Future<void> _showContactFormDialog({EmergencyContact? contact}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: contact?.name ?? '');
    final relationshipController = TextEditingController(text: contact?.relationship ?? '');
    final phoneController = TextEditingController(text: contact?.phone ?? '');
    String contactType = contact?.priority ?? 'primary';
    bool contactEnabled = contact?.enabled ?? true;
    final scaffoldContext = context;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return OwnerFormDialogUi.themedDialog(
              title: contact == null ? 'Add Emergency Contact' : 'Edit Emergency Contact',
              subtitle: contact == null
                  ? 'Saved Contacts can be called from this'
                  : 'Update Details or Enable/Disable calling',
              icon: Icons.contact_emergency_outlined,
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: nameController,
                      cursorColor: AppColors.primary,
                      decoration: OwnerFormDialogUi.fieldDecoration('Name *'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: relationshipController,
                      cursorColor: AppColors.primary,
                      decoration: OwnerFormDialogUi.fieldDecoration('Relationship (optional)'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: phoneController,
                      cursorColor: AppColors.primary,
                      decoration: OwnerFormDialogUi.fieldDecoration(
                        'Phone number *',
                        hint: '03XX-1234567',
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                        PakistaniPhoneInputFormatter(),
                      ],
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Phone number is required';
                        }
                        if (!isValidPakistaniMobile(value)) {
                          return 'Use format 03XX-1234567';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    EmergencyContactUi.contactTypeDropdown(
                      value: contactType,
                      onChanged: (value) => setDialogState(() => contactType = value),
                    ),
                    const SizedBox(height: 10),
                    OwnerFormDialogUi.infoBanner(
                      message:
                          'Primary is called first. If no Primary is enabled, Secondary is used.',
                      icon: Icons.info_outline,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 8),
                    EmergencyContactUi.contactEnabledSwitchRow(
                      value: contactEnabled,
                      onChanged: (value) => setDialogState(() => contactEnabled = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OwnerFormDialogUi.cancelButtonStyle,
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: OwnerFormDialogUi.primaryButtonStyle,
                  onPressed: () async {
                    if (formKey.currentState?.validate() != true) return;
                    final data = <String, dynamic>{
                      'name': nameController.text.trim(),
                      'relationship': relationshipController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'email': '',
                      'priority': contactType,
                      'contactType': contactType,
                      'methods': <String>['call'],
                      'enabled': contactEnabled,
                    };
                    try {
                      if (widget.user.id.trim().isEmpty) {
                        throw Exception('Missing user account. Please sign in again.');
                      }
                      if (contact == null) {
                        await _service.addEmergencyContact(
                          userId: widget.user.id.trim(),
                          userRole: widget.userRole,
                          contactData: data,
                        );
                      } else {
                        await _service.updateEmergencyContact(
                          contactId: contact.id,
                          contactData: data,
                        );
                      }
                      if (scaffoldContext.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              contact == null
                                  ? 'Emergency contact added'
                                  : 'Emergency contact updated',
                            ),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      }
                    } catch (e) {
                      if (scaffoldContext.mounted) {
                        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(contact == null ? 'Add Contact' : 'Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    relationshipController.dispose();
    phoneController.dispose();
  }

  Future<void> _confirmDelete(EmergencyContact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text(
          'Remove ${contact.name} from Emergency Contacts? This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _service.deleteEmergencyContact(contact.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${contact.name} removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _setContactEnabled(EmergencyContact contact, bool enabled) async {
    try {
      await _service.toggleContactEnabled(contact.id, enabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildCallStatusBanner({
    required bool callsEnabled,
    required List<EmergencyContact> contacts,
  }) {
    if (!callsEnabled) {
      return EmergencyContactUi.statusBanner(
        icon: Icons.phone_disabled_outlined,
        title: 'Emergency Calls are Off',
        message: EmergencyCallHelper.masterToggleOffMessage,
        color: AppColors.warning,
      );
    }
    if (contacts.isEmpty) {
      return EmergencyContactUi.statusBanner(
        icon: Icons.person_add_alt_1_outlined,
        title: 'No Contacts Yet',
        message: EmergencyCallHelper.noContactsMessage,
        color: AppColors.textSecondary,
      );
    }
    if (_enabledCount(contacts) == 0) {
      return EmergencyContactUi.statusBanner(
        icon: Icons.toggle_off_outlined,
        title: 'Contacts are Disabled',
        message: EmergencyCallHelper.contactsDisabledMessage,
        color: AppColors.warning,
      );
    }

    return EmergencyContactUi.statusBanner(
      icon: Icons.phone_in_talk_outlined,
      title: 'Ready to Call',
      message:
          'Tap Call Emergency Contact. ${EmergencyCallHelper.dialStatusMessage(contacts)}',
      color: AppColors.success,
    );
  }

  Widget _buildContactCard(EmergencyContact contact, bool isMobile) {
    final disabled = !contact.enabled;

    return Opacity(
      opacity: disabled ? 0.88 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: disabled ? AppColors.background : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: disabled
                ? AppColors.warning.withValues(alpha: 0.45)
                : AppColors.primary.withValues(alpha: 0.2),
            width: disabled ? 1.5 : 1,
          ),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: AppColors.shadowLight,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: isMobile ? 22 : 24,
                        backgroundColor: disabled
                            ? Colors.grey.shade200
                            : AppColors.primaryLight,
                        child: Icon(
                          Icons.person_outline,
                          color: disabled ? Colors.grey : AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    contact.name,
                                    style: TextStyle(
                                      fontSize: isMobile ? 16 : 17,
                                      fontWeight: FontWeight.w700,
                                      color: disabled
                                          ? AppColors.textSecondary
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                EmergencyContactUi.contactTypeBadge(
                                  contact.priority,
                                  compact: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.phone_outlined,
                                  size: 15,
                                  color: disabled
                                      ? Colors.grey
                                      : AppColors.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  contact.phone,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (contact.relationship.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                contact.relationship,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                disabled ? 'Disabled for Calls' : 'Enabled for Calls',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: disabled
                                      ? AppColors.warning
                                      : AppColors.success,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                disabled
                                    ? 'Turn on to include in emergency dialing'
                                    : 'Included when you place an emergency call',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: contact.enabled,
                          onChanged: (v) => _setContactEnabled(contact, v),
                          activeThumbColor: AppColors.primary,
                          activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showContactFormDialog(contact: contact),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmDelete(contact),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.6)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (disabled)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(13),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enable this Contact to allow emergency calling.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isMobile) {
    return EmergencyContactUi.panelSection(
      padding: EdgeInsets.all(isMobile ? 28 : 36),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.contact_phone_outlined, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'No Emergency Contacts Yet',
            style: TextStyle(
              fontSize: isMobile ? 17 : 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: () => _showContactFormDialog(),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Add Your First Contact'),
            style: OwnerFormDialogUi.primaryButtonStyle,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = DashboardLayout.isMobile(context);

    return StreamBuilder<bool>(
      stream: _service.watchEmergencyCallsEnabled(widget.user.id),
      builder: (context, toggleSnap) {
        final callsEnabled = toggleSnap.data ?? true;

        return StreamBuilder<List<EmergencyContact>>(
          stream: _service.getEmergencyContactsStream(widget.user.id),
          builder: (context, contactsSnap) {
            if (contactsSnap.hasError) {
              return EmergencyContactUi.statusBanner(
                icon: Icons.error_outline,
                title: 'Could not load contacts',
                message: '${contactsSnap.error}',
                color: AppColors.danger,
              );
            }
            if (contactsSnap.connectionState == ConnectionState.waiting &&
                !contactsSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }

            final contacts = contactsSnap.data ?? <EmergencyContact>[];
            final enabled = _enabledCount(contacts);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EmergencyContactUi.panelSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.emergency_outlined,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Emergency Calling',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      EmergencyContactUi.emergencyCallsMasterToggle(
                        value: callsEnabled,
                        isMobile: isMobile,
                        onChanged: (v) async {
                          try {
                            await _service.setEmergencyCallsEnabled(widget.user.id, v);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                      ),
                      SizedBox(height: isMobile ? 12 : 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => EmergencyCallHelper.attemptEmergencyCall(
                            context: context,
                            emergencyCallsEnabled: callsEnabled,
                            contacts: contacts,
                          ),
                          icon: const Icon(Icons.phone_in_talk_outlined, size: 22),
                          label: const Text('Call Emergency Contact'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isMobile ? 12 : 14),
                _buildCallStatusBanner(callsEnabled: callsEnabled, contacts: contacts),
                SizedBox(height: isMobile ? 14 : 18),
                if (contacts.isNotEmpty) ...[
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Your Contacts',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$enabled of ${contacts.length} Enabled',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _showContactFormDialog(),
                        icon: const Icon(Icons.person_add_outlined),
                        color: AppColors.primary,
                        tooltip: 'Add Contact',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...contacts.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildContactCard(c, isMobile),
                    ),
                  ),
                ] else
                  _buildEmptyState(isMobile),
              ],
            );
          },
        );
      },
    );
  }
}
