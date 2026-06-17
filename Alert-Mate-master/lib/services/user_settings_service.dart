import 'package:shared_preferences/shared_preferences.dart';

class DriverAlertSettings {
  final bool audioAlertsEnabled;
  final String sensitivityLevel;

  const DriverAlertSettings({
    required this.audioAlertsEnabled,
    required this.sensitivityLevel,
  });

  static const DriverAlertSettings defaults = DriverAlertSettings(
    audioAlertsEnabled: true,
    sensitivityLevel: 'Medium',
  );
}

class UserSettingsService {
  static const _audioKeyPrefix = 'driver_audio_alerts_';
  static const _sensitivityKeyPrefix = 'driver_sensitivity_';

  Future<DriverAlertSettings> loadDriverAlertSettings(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return DriverAlertSettings(
      audioAlertsEnabled: prefs.getBool('$_audioKeyPrefix$userId') ?? true,
      sensitivityLevel: prefs.getString('$_sensitivityKeyPrefix$userId') ?? 'Medium',
    );
  }

  Future<void> saveDriverAudioAlerts(String userId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_audioKeyPrefix$userId', enabled);
  }

  Future<void> saveDriverSensitivity(String userId, String level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_sensitivityKeyPrefix$userId', level);
  }
}