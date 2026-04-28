/// Central configuration for backend connectivity.
///
/// When you restart ngrok, update [ngrokBaseUrl] here — nowhere else.
///
/// ngrok gives an HTTPS URL  →  WebSocket must use  wss://  (not ws://)
///                           →  HTTP calls must use https://  (not http://)
class AppConfig {
  /// The public ngrok HTTPS base URL for the Python drowsiness backend.
  /// ⚠️  No trailing slash.
  static const String ngrokBaseUrl =
      'http://192.168.44.1:8000';

  /// WebSocket endpoint for real-time drowsiness monitoring.
  /// Converts https:// → wss:// automatically.
  static String get wsMonitorUrl {
    final base = ngrokBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '$base/ws/monitor';
  }
}
