import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Themed form controls and badges for emergency contact management.
class EmergencyContactUi {
  EmergencyContactUi._();

  static InputDecoration inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
    );
  }

  static Widget contactTypeDropdown({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: inputDecoration('Contact type *'),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
      items: const [
        DropdownMenuItem(value: 'primary', child: Text('Primary')),
        DropdownMenuItem(value: 'secondary', child: Text('Secondary')),
      ],
      onChanged: (String? value) {
        if (value != null) onChanged(value);
      },
    );
  }

  /// @deprecated Use [contactTypeDropdown].
  static Widget priorityDropdown({
    required String value,
    required ValueChanged<String> onChanged,
  }) =>
      contactTypeDropdown(value: value, onChanged: onChanged);

  static Widget emergencyCallsMasterToggle({
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isMobile = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 14, vertical: isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Enable Emergency Calls',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
        value: value,
        activeColor: AppColors.primary,
        activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
        onChanged: onChanged,
      ),
    );
  }

  static Widget contactMethodsSection({
    required Set<String> methods,
    required ValueChanged<Set<String>> onChanged,
    bool includeSms = true,
  }) {
    void toggle(String key, bool? checked) {
      final next = Set<String>.from(methods);
      if (checked == true) {
        next.add(key);
      } else {
        next.remove(key);
      }
      onChanged(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact Methods *',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Phone Call'),
          value: methods.contains('call'),
          activeColor: AppColors.primary,
          checkColor: Colors.white,
          onChanged: (v) => toggle('call', v),
        ),
        if (includeSms)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('SMS'),
            value: methods.contains('sms'),
            activeColor: AppColors.primary,
            checkColor: Colors.white,
            onChanged: (v) => toggle('sms', v),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Email'),
          value: methods.contains('email'),
          activeColor: AppColors.primary,
          checkColor: Colors.white,
          onChanged: (v) => toggle('email', v),
        ),
      ],
    );
  }

  static Widget contactEnabledSwitchRow({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Enable Emergency Calls',
        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        'Include this contact when placing emergency calls',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      value: value,
      activeColor: AppColors.primary,
      activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
      onChanged: onChanged,
    );
  }

  static Widget contactTypeBadge(String contactType, {bool compact = false}) {
    final isPrimary = contactType.toLowerCase() == 'primary';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: isPrimary ? AppColors.primary : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPrimary ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        isPrimary ? 'Primary' : 'Secondary',
        style: TextStyle(
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w600,
          color: isPrimary ? Colors.white : AppColors.primaryDark,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// @deprecated Use [contactTypeBadge].
  static Widget priorityBadge(String priority, {bool compact = false}) =>
      contactTypeBadge(priority, compact: compact);

  static Widget methodsRow(List<dynamic> methods, {double iconSize = 18}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (methods.contains('call')) ...[
          Icon(Icons.phone, size: iconSize, color: AppColors.primary),
          const SizedBox(width: 6),
        ],
        if (methods.contains('sms')) ...[
          Icon(Icons.message_outlined, size: iconSize, color: AppColors.primary),
          const SizedBox(width: 6),
        ],
        if (methods.contains('email'))
          Icon(Icons.email_outlined, size: iconSize, color: AppColors.primary),
      ],
    );
  }

  static Switch themedSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primary,
      activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
      inactiveThumbColor: Colors.grey.shade400,
      inactiveTrackColor: Colors.grey.shade300,
    );
  }

  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    elevation: 0,
  );

  static Widget panelSection({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  static Widget statusBanner({
    required IconData icon,
    required String title,
    required String message,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
