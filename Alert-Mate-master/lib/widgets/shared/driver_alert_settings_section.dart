import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../widgets/dashboard_detail_dialog_theme.dart';

class DriverAlertSettingsSection extends StatelessWidget {
  final bool audioAlertsEnabled;
  final String sensitivityLevel;
  final ValueChanged<bool> onAudioAlertsChanged;
  final ValueChanged<String> onSensitivityChanged;

  const DriverAlertSettingsSection({
    super.key,
    required this.audioAlertsEnabled,
    required this.sensitivityLevel,
    required this.onAudioAlertsChanged,
    required this.onSensitivityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionCard(
          isMobile: isMobile,
          icon: Icons.volume_up_outlined,
          title: 'Audio Alerts',
          subtitle: 'Sound preferences for drowsiness warnings',
          child: Column(
            children: [
              _settingTile(
                isMobile: isMobile,
                icon: Icons.notifications_active_outlined,
                title: 'Enable Audio Alerts',
                subtitle: 'Play an alarm when drowsiness is detected',
                action: Switch(
                  value: audioAlertsEnabled,
                  onChanged: onAudioAlertsChanged,
                  activeThumbColor: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              _settingTile(
                isMobile: isMobile,
                icon: Icons.music_note_outlined,
                title: 'Alert Sound',
                subtitle: 'Open device sound settings to change sound',
                action: ElevatedButton(
                  onPressed: () => _openSoundSettings(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'Change Audio',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: isMobile ? 14 : 18),
        _sectionCard(
          isMobile: isMobile,
          icon: Icons.tune,
          title: 'Detection Sensitivity',
          subtitle: 'How quickly drowsiness triggers an alert',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              sensitivityLevel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          child: _settingTile(
            isMobile: isMobile,
            icon: Icons.sensors,
            title: 'Sensitivity Level',
            subtitle: _sensitivityDescription(sensitivityLevel),
            action: ElevatedButton(
              onPressed: () => _showSensitivityDialog(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                'Set: $sensitivityLevel',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _sensitivityDescription(String level) {
    switch (level) {
      case 'Low':
        return 'Low = fewer alerts, slower to trigger';
      case 'High':
        return 'High = more alerts, faster to trigger';
      default:
        return 'Medium = balanced alert timing';
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

  void _showSensitivityDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DashboardDetailDialogTheme.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Sensitivity Level'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Low', 'Medium', 'High']
              .map(
                (level) => RadioListTile<String>(
                  title: Text(level),
                  value: level,
                  groupValue: sensitivityLevel,
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    if (value != null) {
                      onSensitivityChanged(value);
                    }
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required bool isMobile,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _settingTile({
    required bool isMobile,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: action),
        ],
      );
    }

    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
        action,
      ],
    );
  }
}