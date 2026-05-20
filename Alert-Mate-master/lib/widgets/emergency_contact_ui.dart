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

  static Widget priorityDropdown({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: inputDecoration('Priority'),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
      items: const [
        DropdownMenuItem(value: 'primary', child: Text('Primary')),
        DropdownMenuItem(value: 'secondary', child: Text('Secondary')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
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

  static Widget enabledSwitchRow({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Enabled', style: TextStyle(color: AppColors.textPrimary)),
      value: value,
      activeColor: AppColors.primary,
      activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
      onChanged: onChanged,
    );
  }

  static Widget priorityBadge(String priority, {bool compact = false}) {
    final isPrimary = priority.toLowerCase() == 'primary';
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
}
