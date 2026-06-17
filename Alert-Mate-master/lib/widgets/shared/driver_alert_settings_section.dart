import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';

class DriverAlertSettingsSection extends StatelessWidget {
  final bool isMobile;
  final bool audioAlertsEnabled;
  final String sensitivityLevel;
  final ValueChanged<bool> onAudioAlertsChanged;
  final ValueChanged<String> onSensitivityChanged;

  const DriverAlertSettingsSection({
    super.key,
    this.isMobile = true,
    required this.audioAlertsEnabled,
    required this.sensitivityLevel,
    required this.onAudioAlertsChanged,
    required this.onSensitivityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSettingsGroup(
          children: [
            _settingTile(
              icon: Icons.notifications_active_outlined,
              title: 'Audio Alerts',
              subtitle: 'Play an alarm when drowsiness is detected',
              action: Switch.adaptive(
                value: audioAlertsEnabled,
                onChanged: onAudioAlertsChanged,
                activeColor: AppColors.primary,
              ),
            ),
            _groupDivider(),
            _settingTile(
              icon: Icons.music_note_outlined,
              title: 'Alert Sound',
              subtitle: 'Change the Alert Sound',
              action: OutlinedButton.icon(
                onPressed: () => _openSoundSettings(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Change Audio'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Detection Sensitivity',
          style: TextStyle(
            fontSize: isMobile ? 14 : 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _sensitivityDescription(sensitivityLevel),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        _buildSensitivitySelector(),
      ],
    );
  }

  Widget _buildSettingsGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: Column(children: children),
    );
  }

  Widget _groupDivider() => Divider(
        height: 1,
        thickness: 1,
        color: AppColors.border.withValues(alpha: 0.8),
        indent: 56,
      );

  Widget _buildSensitivitySelector() {
    const levels = ['Low', 'Medium', 'High'];
    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumn = isMobile && constraints.maxWidth < 420;
        if (useColumn) {
          return Column(
            children: levels
                .map(
                  (level) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _sensitivityChip(level, fullWidth: true),
                  ),
                )
                .toList(),
          );
        }
        return Row(
          children: levels
              .map(
                (level) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: level != 'High' ? 8 : 0),
                    child: _sensitivityChip(level),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _sensitivityChip(String level, {bool fullWidth = false}) {
    final selected = sensitivityLevel == level;
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSensitivityChanged(level),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(
                  _sensitivityIcon(level),
                  size: 20,
                  color: selected ? Colors.white : AppColors.primary,
                ),
                const SizedBox(height: 6),
                Text(
                  level,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _sensitivityIcon(String level) {
    switch (level) {
      case 'Low':
        return Icons.speed_outlined;
      case 'High':
        return Icons.bolt_outlined;
      default:
        return Icons.tune_rounded;
    }
  }

  static String _sensitivityDescription(String level) {
    switch (level) {
      case 'Low':
        return 'Lower Alert Sound';
      case 'High':
        return 'Louder Alert Sound';
      default:
        return 'Balanced Alert Sound';
    }
  }

  Future<void> _openSoundSettings(BuildContext context) async {
    final candidates = <Uri>[
      Uri.parse('intent:#Intent;action=android.settings.SOUND_SETTINGS;end'),
      Uri.parse('app-settings:'),
      Uri.parse('settings:'),
      Uri.parse('android.settings.SOUND_SETTINGS'),
    ];
    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }
    if (await openAppSettings()) return;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open sound settings automatically.'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                action,
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}
