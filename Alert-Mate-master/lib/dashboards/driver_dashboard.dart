import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../models/user.dart';
import '../models/vehicle.dart';
import '../models/driver_document_submission.dart';
import '../services/vehicle_service.dart';
import '../services/driver_document_submission_service.dart';
import '../widgets/driver_cnic_license_upload_panel.dart';
import '../services/monitoring_service.dart';
import '../services/driver_location_update_service.dart';
import '../screens/notifications_inbox_screen.dart';
import '../services/user_notifications_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/sign_out_flow.dart';
import '../widgets/shared/app_sidebar.dart';
import '../constants/app_colors.dart';
import '../constants/app_config.dart';
import '../screens/driver_history_screen.dart';
import '../widgets/email_verified_guard.dart';
import '../widgets/mobile_drawer_menu_button.dart';
import '../widgets/emergency_contacts_panel.dart';
import '../widgets/dashboard_detail_dialog_theme.dart';
import '../utils/dashboard_responsive.dart';
import '../widgets/shared/app_settings_page.dart';
import '../services/user_settings_service.dart';

class DriverDashboard extends StatefulWidget {
  final User user;

  const DriverDashboard({Key? key, required this.user}) : super(key: key);

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  DateTime? _lastBackPress;

  late User _currentUser;
  final UserSettingsService _userSettingsService = UserSettingsService();

  List<MenuItem> get _sidebarMenuItems => [
        const MenuItem(
          section: 'Monitoring',
          icon: Icons.monitor_heart_outlined,
          title: 'Drowsiness Monitoring',
        ),
        const MenuItem(
          section: 'Monitoring',
          icon: Icons.history,
          title: 'History',
        ),
        const MenuItem(
          section: 'Monitoring',
          icon: Icons.videocam_outlined,
          title: 'Live Monitoring',
        ),
        const MenuItem(
          section: 'Safety',
          icon: Icons.phone_outlined,
          title: 'Emergency',
        ),
        MenuItem(
          section: 'Account',
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          unreadBadgeStream: UserNotificationsService.unreadCountStream(_currentUser.id),
        ),
        const MenuItem(
          section: 'Account',
          icon: Icons.settings_outlined,
          title: 'Settings',
        ),
      ];

  Widget _sidebarMainBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildDriverOverviewPage();
      case 1:
        return _buildDriverHistoryPage();
      case 2:
        return _buildDriverLiveMonitoringPage();
      case 3:
        return _buildEmergency();
      case 4:
        return _buildDriverNotificationsPage();
      case 5:
        return _buildDriverSettingsPage();
      default:
        return _buildDriverOverviewPage();
    }
  }

  String get _currentPageTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Drowsiness Monitoring';
      case 1:
        return 'History';
      case 2:
        return 'Live Monitoring';
      case 3:
        return 'Emergency';
      case 4:
        return 'Notifications';
      case 5:
        return 'Settings';
      default:
        return 'Drowsiness Monitoring';
    }
  }

  String get _currentPageSubtitle {
    switch (_selectedIndex) {
      case 0:
        return 'Start Monitoring your Drowsiness';
      case 1:
        return 'Past Driving Sessions and Alert History';
      case 2:
        return 'Live Camera Feed and Alertness Level';
      case 3:
        return 'Quick Access to Emergency Services and Contacts';
      case 4:
        return 'Alerts and System Messages';
      case 5:
        return 'Account, Security, and Alert Preferences';
      default:
        return 'Start Monitoring your Drowsiness';
    }
  }

  Widget _buildDriverNotificationsPage() {
    return _driverPageShell(
      title: 'Notifications',
      subtitle: 'Alerts and system messages',
      child: NotificationsInboxScreen(user: _currentUser, embedded: true),
    );
  }

  Widget _driverPageShell({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return DashboardLayout.scrollPage(
      context: context,
      desktopTitle: title,
      desktopSubtitle: subtitle,
      child: child,
    );
  }

  Widget _buildDriverHistoryPage() {
    final isMobile = DashboardLayout.isMobile(context);
    final history = DriverHistoryScreen(
      driverId: widget.user.id,
      embedded: true,
    );
    if (isMobile) {
      return Padding(
        padding: DashboardLayout.pagePadding(context),
        child: history,
      );
    }
    return _driverPageShell(
      title: 'History',
      subtitle: 'Past driving sessions and alert history',
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: history,
      ),
    );
  }

  Widget _buildDriverLiveMonitoringPage() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return _driverPageShell(
      title: 'Live Monitoring',
      subtitle: 'Real-time camera and drowsiness detection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isMonitoring)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _stopMonitoring();
                    setState(() => _selectedIndex = 0);
                  },
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Monitoring'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          _buildLiveMonitoringTab(isMobile),
        ],
      ),
    );
  }

  Widget _buildDriverSettingsPage() {
    return AppSettingsPage(
      user: _currentUser,
      sessionRole: 'driver',
      onUserUpdated: (user) => setState(() => _currentUser = user),
      showDriverAlerts: true,
      audioAlertsEnabled: _audioAlertsEnabled,
      sensitivityLevel: _sensitivityLevel,
      onAudioAlertsChanged: (value) async {
        setState(() => _audioAlertsEnabled = value);
        await _userSettingsService.saveDriverAudioAlerts(_currentUser.id, value);
        if (!value) {
          _setDrowsyAlarmActive(false);
        } else if (_isMonitoring && _alertness < 80.0) {
          _setDrowsyAlarmActive(true);
        }
      },
      onSensitivityChanged: (value) async {
        setState(() => _sensitivityLevel = value);
        await _userSettingsService.saveDriverSensitivity(_currentUser.id, value);
      },
    );
  }
  bool _isMonitoring = false;
  bool _isCameraTesting = false; // kept only to satisfy legacy Camera Test widget, not used in main UI
  Process? _monitorProcess;
  WebSocketChannel? _channel;
  double _alertness = 82.0;
  double _ear = 0.0;
  double _mar = 0.0;
  double _eyeClosurePercentage = 0.0;
  Timer? _updateTimer;
  final Random _random = Random();
  Uint8List? _cameraFrameBytes;
  final ValueNotifier<Uint8List?> _cameraFrameNotifier = ValueNotifier<Uint8List?>(null);
  
  // Camera controller
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  Timer? _frameCaptureTimer;
  
  final VehicleService _vehicleService = VehicleService();
  final DriverDocumentSubmissionService _docSubmissionService = DriverDocumentSubmissionService();
  final MonitoringService _monitoringService = MonitoringService();
  final DriverLocationUpdateService _locationUpdateService = DriverLocationUpdateService();
  Timer? _statsUpdateTimer;
  String? _currentSessionId;
  // Track last drowsy state to avoid unnecessary Firestore writes
  bool _lastDrowsyState = false;

  /// Last Firestore `vehicles.status` written during live monitoring (Active/Critical).
  String? _lastSyncedFirestoreVehicleStatus;

  Future<void> _syncAssignedVehicleFirestoreStatus(String status) async {
    try {
      final vehicles = await _vehicleService.getAssignedVehiclesForDriver(widget.user.id);
      if (vehicles.isEmpty) return;
      await _vehicleService.updateVehicleStatus(vehicles.first.id, status);
    } catch (e) {
      print('âš ï¸ Sync assigned vehicle status: $e');
    }
  }
  
  
  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  // Alert Settings
  bool _audioAlertsEnabled = true;
  String _sensitivityLevel = 'Medium';

  (int, int) get _yawningTriggerRange {
    switch (_sensitivityLevel) {
      case 'Low':
        return (7, 9);
      case 'High':
        return (3, 5);
      default:
        return (5, 7);
    }
  }

  int get _yawningResetAfter {
    switch (_sensitivityLevel) {
      case 'Low':
        return 9;
      case 'High':
        return 5;
      default:
        return 7;
    }
  }
  
  // Yawning detection tracking
  int _yawningFrameCount = 0;
  bool _buzzerPlayed = false;
  Timer? _drowsyBuzzerTimer;
  DateTime _lastBuzzerAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMetricsUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _buzzerCooldown = Duration(milliseconds: 1200);
  static const Duration _metricsUiThrottle = Duration(milliseconds: 300);
  /// EMA smoothing for alertness bar (0â€“1, higher = react faster to EAR/MAR).
  static const double _alertnessEmaAlpha = 0.32;

  int _decodedFrameDiagCount = 0;
  DateTime? _lastSkippedJpegLogAt;

  /// Last drowsy flag from ML / WebSocket (used with smoothed bar for Firebase).
  bool _serverSaysDrowsy = false;

  /// WebSocket echoes are often truncated; decoding them triggers
  /// `Invalid SOS parameters for sequential JPEG` in Chromium/SKIA.
  static bool _jpegLooksCompleteEnoughToDecode(Uint8List b) {
    final n = b.length;
    if (n < 500) return false;
    if (b[0] != 0xFF || b[1] != 0xD8) return false;

    var hasSos = false;
    for (var i = 2; i < n - 1; i++) {
      if (b[i] == 0xFF && b[i + 1] == 0xDA) {
        hasSos = true;
        break;
      }
    }
    if (!hasSos) return false;

    const tailScan = 16384;
    final start = n > tailScan ? n - tailScan : 0;
    for (var i = start; i < n - 1; i++) {
      if (b[i] == 0xFF && b[i + 1] == 0xD9) return true;
    }
    return false;
  }

  /// Maps EAR/MAR/eye closure into 0â€“100; blended with server [alertness] when present.
  double _instantAlertnessFromMetrics({
    required double ear,
    required double mar,
    required double eyeClosurePct,
    required double serverAlertness,
    required bool serverProvidedAlertness,
    required bool isDrowsy,
  }) {
    final e = ear > 1e-6 ? ear : 0.26;
    final m = mar > 1e-6 ? mar : 0.28;

    // EAR: eyes open â†’ higher ratio (typical open ~0.22â€“0.38 depending on model scale).
    const earOpen = 0.36;
    const earClosed = 0.14;
    final earSpan = earOpen - earClosed;
    final fromEar =
        earSpan <= 1e-6 ? 70.0 : (((e - earClosed) / earSpan) * 100.0).clamp(0.0, 100.0);

    // MAR: mouth open / yawning â†’ lower alertness.
    const marRest = 0.26;
    const marHigh = 0.58;
    final marSpan = marHigh - marRest;
    final marStress = marSpan <= 1e-6 ? 0.0 : (((m - marRest) / marSpan).clamp(0.0, 1.0));
    final fromMar = (100.0 * (1.0 - marStress)).clamp(0.0, 100.0);

    final fromEyelids = (100.0 - eyeClosurePct.clamp(0.0, 100.0));

    double blended = fromEar * 0.50 + fromMar * 0.32 + fromEyelids * 0.18;

    if (serverProvidedAlertness) {
      final s = serverAlertness.clamp(0.0, 100.0);
      blended = blended * 0.55 + s * 0.45;
    }

    if (isDrowsy) {
      blended = (blended * 0.58).clamp(0.0, 48.0);
    }

    return blended.clamp(0.0, 100.0);
  }

  double _smoothAlertness(double targetInstant) {
    const a = _alertnessEmaAlpha;
    return (_alertness * (1.0 - a) + targetInstant * a).clamp(0.0, 100.0);
  }

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    WidgetsBinding.instance.addObserver(this);
    // Vehicle data is now fetched via StreamBuilder

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
    
    _fadeController.forward();
    _slideController.forward();
    _scaleController.forward();
    
    // Request required runtime permissions on startup.
    _requestStartupPermissions();

    _loadDriverAlertSettings();

    // Mark driver as online (idle) in Firestore so the map shows them
    _locationUpdateService.goOnline(_currentUser.id, _currentUser.fullName);
  }

  Future<void> _loadDriverAlertSettings() async {
    final settings = await _userSettingsService.loadDriverAlertSettings(_currentUser.id);
    if (!mounted) return;
    setState(() {
      _audioAlertsEnabled = settings.audioAlertsEnabled;
      _sensitivityLevel = settings.sensitivityLevel;
    });
  }

  Future<void> _requestStartupPermissions() async {
    try {
      await [
        Permission.camera,
        Permission.microphone,
        Permission.locationWhenInUse,
      ].request();
    } catch (_) {}
    await _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _updateTimer?.cancel();
    _statsUpdateTimer?.cancel();
    _cameraController?.dispose();
    _frameCaptureTimer?.cancel();
    _setDrowsyAlarmActive(false);
    _cameraFrameNotifier.dispose();
    // Mark driver offline so they disappear from all maps
    _locationUpdateService.goOffline(widget.user.id);
    _locationUpdateService.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      // Stop the frame capture timer when app goes inactive
      _frameCaptureTimer?.cancel();
      _frameCaptureTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_isMonitoring && _frameCaptureTimer == null) {
        _startCameraStream();
      }
    }
  }
  
  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.status;
      if (!status.isGranted) {
        print('âŒ Camera permission denied');
        return;
      }
      
      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        print('âŒ No cameras available');
        return;
      }
      
      // Use front camera (index 1) if available, otherwise use first camera
      final camera = _cameras!.length > 1 ? _cameras![1] : _cameras![0];
      
      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      
      setState(() {
        _isCameraInitialized = true;
      });
      
      print('âœ… Camera initialized: ${camera.name}');
    } catch (e) {
      print('âŒ Error initializing camera: $e');
    }
  }
  
  Future<void> _startCameraStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print('âŒ Camera not initialized');
      return;
    }
    
    if (_channel == null) {
      print('âŒ WebSocket not connected');
      return;
    }
    
    try {
      print('ðŸ“¸ Setting up camera frame capture...');
      
      // Use a slower rate to avoid overwhelming the connection
      // takePicture is slower but produces proper JPEG images
      int frameCount = 0;
      bool isCapturing = false;
      
      _frameCaptureTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        if (!_isMonitoring || _channel == null) {
          print('â¹ï¸ Stopping camera capture timer');
          timer.cancel();
          return;
        }
        
        // Prevent concurrent captures
        if (isCapturing) {
          return;
        }
        
        isCapturing = true;
        
        try {
          if (_cameraController != null && _cameraController!.value.isInitialized) {
            final image = await _cameraController!.takePicture();
            final imageBytes = await image.readAsBytes();
            
            // Convert to base64
            final base64Image = base64Encode(imageBytes);
            
            frameCount++;
            if (frameCount == 1 || frameCount % 10 == 0) {
              print('ðŸ“¤ Sending frame #$frameCount (${imageBytes.length} bytes)');
            }
            
            // Send frame to backend
            _channel!.sink.add(json.encode({
              'frame': base64Image,
              'format': 'jpeg',
            }));
            
            // Delete temporary image file
            try {
              final file = File(image.path);
              if (await file.exists()) {
                await file.delete();
              }
            } catch (_) {}
          }
        } catch (e) {
          print('âŒ Error capturing frame: $e');
        } finally {
          isCapturing = false;
        }
      });
      
      print('âœ… Camera stream started - capturing frames every 500ms');
    } catch (e) {
      print('âŒ Error starting camera stream: $e');
    }
  }

  void _updateCameraFrame(Uint8List? frameBytes) {
    _cameraFrameBytes = frameBytes;
    _cameraFrameNotifier.value = frameBytes;
  }

  Future<void> _playBuzzerIfAllowed({bool force = false}) async {
    if (!_audioAlertsEnabled) return;
    if (kIsWeb) {
      HapticFeedback.heavyImpact();
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastBuzzerAt) < _buzzerCooldown) return;
    _lastBuzzerAt = now;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await FlutterRingtonePlayer().play(
          android: AndroidSounds.alarm,
          ios: IosSounds.alarm,
          volume: 1.0,
          looping: false,
          asAlarm: true,
        );
      } else {
        await FlutterRingtonePlayer().playNotification(volume: 1.0, asAlarm: false);
      }
    } catch (_) {
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
    HapticFeedback.heavyImpact();
  }

  void _setDrowsyAlarmActive(bool active) {
    if (!active || !_audioAlertsEnabled) {
      _drowsyBuzzerTimer?.cancel();
      _drowsyBuzzerTimer = null;
      try {
        FlutterRingtonePlayer().stop();
      } catch (_) {}
      return;
    }

    if (_drowsyBuzzerTimer != null) return;
    _playBuzzerIfAllowed(force: true);
    _drowsyBuzzerTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isMonitoring || !_audioAlertsEnabled) {
        _setDrowsyAlarmActive(false);
        return;
      }
      _playBuzzerIfAllowed();
    });
  }

  String _getWebSocketUrl() {
    // â”€â”€ ngrok public tunnel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Works on every platform (Android, iOS, Web, Desktop) without any
    // IP-address changes or mobile-hotspot setup.
    //
    // ngrok is HTTPS  â†’  WebSocket must use wss:// (secure), not ws://.
    // To update the URL when ngrok restarts, edit AppConfig.ngrokBaseUrl
    // in lib/constants/app_config.dart â€” change it in one place only.
    final url = AppConfig.wsMonitorUrl;
    print('ðŸ”Œ Connecting to backend via ngrok: $url');
    return url;
  }

  Future<void> _startMonitoring() async {
    final driverId = widget.user.id;

    // Validate driver ID
    if (driverId == null) {
      print('âŒ Driver ID is missing');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Driver ID is missing'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    print('ðŸš€ Starting monitoring for driver: $driverId');

    try {
    // Start Firebase session
      _currentSessionId = await _monitoringService.startMonitoringSession(driverId);
      print('âœ… Firebase session started: $_currentSessionId');
    } catch (e) {
      print('âŒ Failed to start Firebase session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start session: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Check camera availability
    if (!_isCameraInitialized || _cameraController == null) {
      print('âŒ Camera not initialized, initializing now...');
      await _initializeCamera();
      if (!_isCameraInitialized || _cameraController == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Camera not available. Please grant camera permission.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    // Mark monitoring active
    setState(() {
      _isMonitoring = true;
    });

    // Connect to FastAPI WebSocket
    try {
      final wsUrl = _getWebSocketUrl();
      print('ðŸ”Œ Connecting to FastAPI server at $wsUrl...');
      if (!kIsWeb) {
        // Platform.* is dart:io only â€” unavailable on Flutter Web
        print('ðŸ“± Platform: ${Platform.operatingSystem}');
        print('ðŸ“± Is Android: ${Platform.isAndroid}');
        print('ðŸ“± Is iOS: ${Platform.isIOS}');
      }

      // Connect to WebSocket with proper error handling
      try {
        print('ðŸ”Œ Attempting to connect to $wsUrl...');
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        print('âœ… WebSocket channel created');
      } catch (e) {
        print('âŒ Error creating WebSocket channel: $e');
        throw Exception('Failed to create WebSocket connection: $e');
      }

      // Set up a connection timeout check
      bool hasReceivedData = false;
      bool connectionConfirmed = false;

      // Listen for incoming messages
      _channel!.stream.timeout(
        const Duration(seconds: 10),
        onTimeout: (sink) {
          if (!hasReceivedData && mounted) {
            throw TimeoutException(
              'Failed to connect to server at $wsUrl.\n\n'
              'Please check:\n'
              '1. Backend is running (python backend.py)\n'
              '2. Correct IP address - Current: $wsUrl\n'
              '   For Android: Use your PC\'s IP (check ipconfig on Windows)\n'
              '   Common IPs: 192.168.137.1 (Windows Hotspot) or 192.168.1.X (WiFi)\n'
              '3. Firewall allows port 8000\n'
              '4. Phone and PC are on same network',
            );
          }
        },
      ).listen(
        (message) {
          try {
            // Mark that we've received data (connection is working)
            if (!hasReceivedData) {
              hasReceivedData = true;
              connectionConfirmed = true;
              print('âœ… Connection confirmed - received first message from server');
            }
            
            print('ðŸ“¦ Received message (first 150 chars): ${message.toString().substring(0, min(150, message.toString().length))}...');

            final data = json.decode(message) as Map<String, dynamic>;
            
            // Handle error messages
            if (data.containsKey('error')) {
              print('âŒ Error from server: ${data['error']}');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Server error: ${data['error']}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }
            
            // Handle status messages
            if (data.containsKey('status')) {
              print('â„¹ï¸ Status update: ${data['status']}');
              return;
            }
            
            // Process monitoring data
            if (mounted) {
              final reason = data['reason'] as String? ?? 'alert';
              final isYawning = reason == 'yawning';
              final nextAlertness = (data['alertness'] as num?)?.toDouble() ?? _alertness;
              final nextEar = (data['ear'] as num?)?.toDouble() ?? _ear;
              final nextMar = (data['mar'] as num?)?.toDouble() ?? _mar;
              final nextEyeClosure =
                  (data['eyeClosure'] as num?)?.toDouble() ?? _eyeClosurePercentage;
              final isDrowsy = (data['isDrowsy'] == true) ||
                  reason == 'eyes_closed' ||
                  reason == 'yawning';

              // Track yawning frames for buzzer
              if (isYawning) {
                _yawningFrameCount++;
                print('ðŸ¥± Yawning detected (frame $_yawningFrameCount)');

                // Play buzzer when sensitivity range detects yawning (only once per session)
                final (triggerMin, triggerMax) = _yawningTriggerRange;
                if (_yawningFrameCount >= triggerMin &&
                    _yawningFrameCount <= triggerMax &&
                    !_buzzerPlayed &&
                    _audioAlertsEnabled) {
                  _playBuzzerIfAllowed();
                  _buzzerPlayed = true;
                  print('ðŸ”” Buzzer played - Yawning detected for $_yawningFrameCount frames');
                }

                // Reset after threshold to allow buzzer to play again
                if (_yawningFrameCount > _yawningResetAfter) {
                  _yawningFrameCount = 0;
                  _buzzerPlayed = false;
                  print('ðŸ”„ Yawning counter reset');
                }
              } else {
                // Reset counter when not yawning
                if (_yawningFrameCount > 0) {
                  print('ðŸ”„ Yawning stopped, resetting counter');
                }
                _yawningFrameCount = 0;
                _buzzerPlayed = false;
              }

              _serverSaysDrowsy = isDrowsy;
              _ear = nextEar;
              _mar = nextMar;
              _eyeClosurePercentage = nextEyeClosure;
              final serverHasAlertness =
                  data.containsKey('alertness') && data['alertness'] != null;
              final instantA = _instantAlertnessFromMetrics(
                ear: nextEar,
                mar: nextMar,
                eyeClosurePct: nextEyeClosure,
                serverAlertness: nextAlertness,
                serverProvidedAlertness: serverHasAlertness,
                isDrowsy: isDrowsy,
              );
              _alertness = _smoothAlertness(instantA);

              final now = DateTime.now();
              if (now.difference(_lastMetricsUiUpdate) >= _metricsUiThrottle) {
                _lastMetricsUiUpdate = now;
                setState(() {});
              }

              // Log metrics periodically (every 10th second to avoid spam)
              if (DateTime.now().second % 10 == 0) {
                print('ðŸ“Š Metrics - Alertness: ${_alertness.toStringAsFixed(1)}%, EAR: ${_ear.toStringAsFixed(2)}, MAR: ${_mar.toStringAsFixed(2)}');
              }

              if (data.containsKey('frame') && data['frame'] != null) {
                try {
                  final frameBase64 = data['frame'] as String;
                  final decodedFrame = base64Decode(frameBase64);
                  if (!_jpegLooksCompleteEnoughToDecode(decodedFrame)) {
                    final now = DateTime.now();
                    if (_lastSkippedJpegLogAt == null ||
                        now.difference(_lastSkippedJpegLogAt!) > const Duration(seconds: 20)) {
                      _lastSkippedJpegLogAt = now;
                      print(
                        'âš ï¸ Skipping incomplete/bad JPEG (${decodedFrame.length} B). '
                        'Often caused by WebSocket echo truncation or overlapping sessions.',
                      );
                    }
                  } else {
                    _updateCameraFrame(decodedFrame);
                    _decodedFrameDiagCount++;
                    if (_decodedFrameDiagCount <= 3 || _decodedFrameDiagCount % 25 == 0) {
                      print('ðŸ“¸ Camera frame (${decodedFrame.length} bytes)');
                    }
                  }
                } catch (e) {
                  print('âŒ Error decoding frame: $e');
                }
              }

              _setDrowsyAlarmActive(isDrowsy);
            }
          } catch (e, stackTrace) {
            print('âŒ Error parsing message: $e');
            print('Stack trace: $stackTrace');
          }
        },
        onError: (error) {
          print('âŒ WebSocket error: $error');
          print('âŒ Connection URL was: $wsUrl');
          if (mounted) {
            setState(() {
              _isMonitoring = false;
            });
            _setDrowsyAlarmActive(false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('âŒ Connection Error',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Error: $error', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('URL: $wsUrl', style: const TextStyle(fontSize: 11)),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 10),
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () {
                    _startMonitoring();
                  },
                ),
              ),
            );
          }
        },
        onDone: () {
          print('ðŸ”Œ WebSocket connection closed');
          if (mounted && _isMonitoring) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Connection closed unexpectedly. Tap to reconnect.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );

            // Auto-stop monitoring when connection closes
            setState(() {
              _isMonitoring = false;
              _yawningFrameCount = 0;
              _buzzerPlayed = false;
            });
            _setDrowsyAlarmActive(false);
          }
        },
      );

      print('âœ… WebSocket listener attached successfully');
      
    } catch (e, stackTrace) {
      print('âŒ Failed to connect to WebSocket server: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isMonitoring = false;
        });
        _setDrowsyAlarmActive(false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('âŒ Failed to connect to server',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('URL: ${_getWebSocketUrl()}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text('Error: ${e.toString()}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                _startMonitoring();
              },
            ),
          ),
        );
      }
      return;
    }

    // Start camera stream to send frames to backend
    await _startCameraStream();

    // Mark driver on_trip in Firestore and start periodic GPS updates
    await _locationUpdateService.goOnTrip(driverId);
    
    // Start Firebase stats update timer
    print('â±ï¸ Starting Firebase stats update timer (1s interval)');
    _statsUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isMonitoring) {
        timer.cancel();
        print('â±ï¸ Stats timer cancelled - monitoring stopped');
        return;
      }

      final isDrowsy = _serverSaysDrowsy || _alertness < 76;

      _monitoringService.updateRealtimeStats(
        driverId: driverId,
        alertness: _alertness,
        ear: _ear,
        mar: _mar,
        eyeClosure: _eyeClosurePercentage,
        drowsinessDetected: isDrowsy,
      );

      // Sync drowsinessAlert to Firestore only when it changes (avoid excessive writes)
      if (isDrowsy != _lastDrowsyState) {
        _lastDrowsyState = isDrowsy;
        _locationUpdateService.updateDrowsinessAlert(driverId, isDrowsy);
      }

      final desiredVehicleStatus = isDrowsy ? 'Critical' : 'Active';
      if (desiredVehicleStatus != _lastSyncedFirestoreVehicleStatus) {
        _lastSyncedFirestoreVehicleStatus = desiredVehicleStatus;
        unawaited(_syncAssignedVehicleFirestoreStatus(desiredVehicleStatus));
      }
    });

    _lastSyncedFirestoreVehicleStatus = 'Active';
    unawaited(_syncAssignedVehicleFirestoreStatus('Active'));

    print('âœ… Monitoring started successfully');
  }
  void _stopMonitoring() async {
    print('ðŸ›‘ Stopping monitoring...');

    final driverId = widget.user.id;

    // Stop camera stream
    _frameCaptureTimer?.cancel();
    _frameCaptureTimer = null;

    // Update UI state
    setState(() {
      _isMonitoring = false;
      _yawningFrameCount = 0;
      _buzzerPlayed = false;
      _serverSaysDrowsy = false;
    });
    _setDrowsyAlarmActive(false);

    // Cancel timers
    if (_updateTimer != null) {
      _updateTimer!.cancel();
      _updateTimer = null;
      print('â±ï¸ Update timer cancelled');
    }

    if (_statsUpdateTimer != null) {
      _statsUpdateTimer!.cancel();
      _statsUpdateTimer = null;
      print('â±ï¸ Stats timer cancelled');
    }
    
    // Close WebSocket connection
    if (_channel != null) {
      try {
        await _channel!.sink.close();
        print('ðŸ”Œ WebSocket connection closed');
      } catch (e) {
        print('âš ï¸ Error closing WebSocket: $e');
      }
    _channel = null;
    }
    
    // Clear camera frame
    _updateCameraFrame(null);
    print('ðŸ“¸ Camera frame cleared');
    
    // End Firebase session
    if (_currentSessionId != null && driverId != null) {
      try {
      await _monitoringService.endMonitoringSession(driverId);
        print('âœ… Firebase session ended: $_currentSessionId');
      _currentSessionId = null;
      } catch (e) {
        print('âš ï¸ Error ending Firebase session: $e');
      }
    }

    // Clear current stats from Realtime Database
    if (driverId != null) {
      try {
        await _monitoringService.clearCurrentStats(driverId);
        print('âœ… Current stats cleared from Realtime Database');
      } catch (e) {
        print('âš ï¸ Error clearing current stats: $e');
      }
    }

    _lastSyncedFirestoreVehicleStatus = null;
    await _syncAssignedVehicleFirestoreStatus('Offline');

    // Revert driver to idle in Firestore and stop GPS updates
    _lastDrowsyState = false;
    await _locationUpdateService.goIdle(driverId);

    print('âœ… Monitoring stopped successfully');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Monitoring stopped'),
          backgroundColor: Colors.grey,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
 Future<void> _launchPythonMonitor() async {
  if (kIsWeb) return; // dart:io (Platform, Process, Directory) unavailable on web
  try {
    final projectRoot = Directory.current.path;
    
    final scriptPath = Platform.isWindows
        ? '$projectRoot\\python\\drowsiness_monitor_flutter.py'
        : '$projectRoot/python/drowsiness_monitor_flutter.py';
    
    // Models in same python folder
    final landmarkModelPath = Platform.isWindows
        ? '$projectRoot\\python\\landmark_detector.pth'
        : '$projectRoot/python/landmark_detector.pth';
    
    final drowsyModelPath = Platform.isWindows
        ? '$projectRoot\\python\\drowsiness_classifier.pkl'
        : '$projectRoot/python/drowsiness_classifier.pkl';

    print('ðŸ” Launching Python with:');
    print('Script: $scriptPath');
    print('Landmark: $landmarkModelPath');
    print('Drowsy: $drowsyModelPath');

    // Use 'py' on Windows (Python launcher)
    final pythonCommand = Platform.isWindows ? 'py' : 'python3';

    _monitorProcess = await Process.start(
      pythonCommand,
      [
        scriptPath,
        '--landmark-model', landmarkModelPath,
        '--drowsy-model', drowsyModelPath,
        '--camera', '0'
      ],
      runInShell: true,
      mode: ProcessStartMode.normal,
    );

    // Listen to stdout (JSON data)
    _monitorProcess!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      print('ðŸ“Š Python stdout: $line');
      try {
        final data = json.decode(line) as Map<String, dynamic>;
        
        if (data.containsKey('error')) {
          print('âŒ Python error: ${data['error']}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Camera error: ${data['error']}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        if (data.containsKey('status')) {
          print('âœ… Python status: ${data['status']}');
          return;
        }
        
        // Update UI with real stats
        if (mounted) {
            final reason = data['reason'] as String? ?? 'alert';
            final isYawning = reason == 'yawning';
            final nextAlertness = (data['alertness'] as num?)?.toDouble() ?? _alertness;
            final nextEar = (data['ear'] as num?)?.toDouble() ?? _ear;
            final nextMar = (data['mar'] as num?)?.toDouble() ?? _mar;
            final nextEyeClosure =
                (data['eyeClosure'] as num?)?.toDouble() ?? _eyeClosurePercentage;
            final isDrowsy = (data['isDrowsy'] == true) ||
                reason == 'eyes_closed' ||
                reason == 'yawning';
            
            // Track yawning frames
            if (isYawning) {
              _yawningFrameCount++;
              // Play buzzer when sensitivity range detects yawning (only once per yawning session)
              final (triggerMin, triggerMax) = _yawningTriggerRange;
              if (_yawningFrameCount >= triggerMin &&
                  _yawningFrameCount <= triggerMax &&
                  !_buzzerPlayed &&
                  _audioAlertsEnabled) {
                _playBuzzerIfAllowed();
                _buzzerPlayed = true;
                print('ðŸ”” Buzzer played - Yawning detected for $_yawningFrameCount frames');
              }
              // Reset after threshold to allow buzzer to play again if yawning continues
              if (_yawningFrameCount > _yawningResetAfter) {
                _yawningFrameCount = 0;
                _buzzerPlayed = false;
              }
            } else {
              // Reset counter when not yawning
              _yawningFrameCount = 0;
              _buzzerPlayed = false;
            }
            
          _serverSaysDrowsy = isDrowsy;
          _ear = nextEar;
          _mar = nextMar;
          _eyeClosurePercentage = nextEyeClosure;
          final pyServerHasAlertness =
              data.containsKey('alertness') && data['alertness'] != null;
          final instantPy = _instantAlertnessFromMetrics(
            ear: nextEar,
            mar: nextMar,
            eyeClosurePct: nextEyeClosure,
            serverAlertness: nextAlertness,
            serverProvidedAlertness: pyServerHasAlertness,
            isDrowsy: isDrowsy,
          );
          _alertness = _smoothAlertness(instantPy);
          final now = DateTime.now();
          if (now.difference(_lastMetricsUiUpdate) >= _metricsUiThrottle) {
            _lastMetricsUiUpdate = now;
            setState(() {});
          }
          _setDrowsyAlarmActive(isDrowsy);
          
          // Show drowsiness alert
          if (data['isDrowsy'] == true) {
            final reasonText = reason == 'eyes_closed' ? 'Eyes Closed' : 
                             reason == 'yawning' ? 'Yawning Detected' : 'Alert';
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('âš ï¸ DROWSINESS ALERT: $reasonText'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        print('âŒ Error parsing JSON: $e, Line: $line');
      }
    });

    // Listen to stderr (errors and debug info)
    _monitorProcess!.stderr.transform(utf8.decoder).listen((error) {
      print('ðŸ”´ Python stderr: $error');
    });

    // When process exits
    _monitorProcess!.exitCode.then((exitCode) {
      print('ðŸ›‘ Python process exited with code: $exitCode');
      if (mounted && _isMonitoring) {
        setState(() {
          _isMonitoring = false;
        });
        _setDrowsyAlarmActive(false);
      }
    });
    
    print('âœ… Python process started successfully!');
    
  } catch (e) {
    print('ðŸ’¥ Error launching Python: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start camera: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    
    // Fallback to mock data if launching fails
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        _ear = 0.12 + _random.nextDouble() * 0.28;
        _mar = 0.20 + _random.nextDouble() * 0.45;
        _eyeClosurePercentage = _random.nextDouble() * 42;
        final inst = _instantAlertnessFromMetrics(
          ear: _ear,
          mar: _mar,
          eyeClosurePct: _eyeClosurePercentage,
          serverAlertness: _alertness,
          serverProvidedAlertness: false,
          isDrowsy: false,
        );
        _alertness = _smoothAlertness(inst);
      });
    });
  }
}
  void _killPythonMonitor() {
    try {
      _monitorProcess?.kill(ProcessSignal.sigint);
      _monitorProcess = null;
    } catch (_) {}
  }


  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return;
        }
        final now = DateTime.now();
        if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2)),
          );
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        drawer: isMobile ? _buildMobileDrawer() : null,
        appBar: isMobile ? AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: Builder(
            builder: (context) => MobileDrawerMenuButton(
              unreadBadgeStream: UserNotificationsService.unreadCountStream(widget.user.id),
            ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentPageTitle,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _currentPageSubtitle,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              tooltip: 'Sign out',
              icon: Icon(Icons.logout_rounded, color: AppColors.primary, size: 26),
              onPressed: () => performSignOutAndGoToAuth(context),
            ),
          ),
        ],
      ) : null,
      body: EmailVerifiedGuard(
        child: DashboardLayout.scaffoldBody(
          context: context,
          sidebar: AppSidebar(
            role: 'Driver',
            user: _currentUser,
            selectedIndex: _selectedIndex,
            onMenuItemTap: (index) => setState(() => _selectedIndex = index),
            menuItems: _sidebarMenuItems,
            accentColor: AppColors.primary,
            accentLightColor: AppColors.primaryLight,
          ),
          body: _sidebarMainBody(),
        ),
      ),
      ),
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: AppSidebar(
          role: 'Driver',
          user: widget.user,
          selectedIndex: _selectedIndex,
          onMenuItemTap: (index) {
            setState(() => _selectedIndex = index);
            Navigator.pop(context);
          },
          menuItems: _sidebarMenuItems,
          accentColor: AppColors.primary,
          accentLightColor: AppColors.primaryLight,
        ),
      ),
    );
  }

  Widget _buildDriverSectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    bool isMobile = false,
    String? subtitle,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: isMobile ? 12 : 13,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
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

  Widget _buildDriverSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
    bool isMobile = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _driverSettingTileHeader(icon, title, subtitle, isMobile),
                const SizedBox(height: 12),
                action,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _driverSettingTileHeader(icon, title, subtitle, isMobile)),
                action,
              ],
            ),
    );
  }

  Widget _driverSettingTileHeader(IconData icon, String title, String subtitle, bool isMobile) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: isMobile ? 22 : 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 15 : 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStaggeredItem(Widget child, int index) {
    final Animation<double> fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Interval(index * 0.1, 1.0, curve: Curves.easeOut),
      ),
    );
    final Animation<Offset> slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Interval(index * 0.1, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: child,
      ),
    );
  }



  Widget _buildDriverOverviewPage() {
    final isMobile = DashboardLayout.isMobile(context);
    return _driverPageShell(
      title: 'Drowsiness Monitoring',
      subtitle: 'Start a session and manage your assigned vehicle',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDriverSectionCard(
            isMobile: isMobile,
            icon: Icons.monitor_heart_outlined,
            title: 'Monitoring Session',
            subtitle: _isMonitoring
                ? 'Session is Active. Drowsiness Detector is Running'
                : 'Start Monitoring to Begin Live Alertness Tracking',
            child: _buildOverviewMonitoringButton(isMobile),
          ),
          SizedBox(height: isMobile ? 14 : 18),
          _buildDriverSectionCard(
            isMobile: isMobile,
            icon: Icons.directions_car_outlined,
            title: 'Your Vehicle',
            subtitle: 'Assigned Vehicle and Owner Details',
            child: StreamBuilder<Vehicle?>(
                  stream: _vehicleService.getVehicleByDriverStream(widget.user.id),
                  builder: (context, vehicleSnap) {
                    if (vehicleSnap.hasError) {
                      return Text('Error loading vehicle: ${vehicleSnap.error}');
                    }
                    final assignedVehicle = vehicleSnap.data;
                    final vehicleBusy =
                        vehicleSnap.connectionState == ConnectionState.waiting && assignedVehicle == null;
                    if (vehicleBusy) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                    }

                    if (assignedVehicle != null) {
                      final isMobile = MediaQuery.of(context).size.width < 768;
                      return Column(
                        children: [
                          _DriverAssignedVehicleCard(
                            key: ValueKey(assignedVehicle.id),
                            vehicle: assignedVehicle,
                            isMobile: isMobile,
                          ),
                        ],
                      );
                    }

                    return StreamBuilder<bool>(
                      stream: _vehicleService.hasOwnerPendingVehiclesStream(widget.user.id),
                      builder: (context, ownerSnap) {
                        return StreamBuilder<bool>(
                          stream: _vehicleService.hasGeneralPendingVehiclesStream(),
                          builder: (context, generalSnap) {
                            final ownerPending = ownerSnap.data ?? false;
                            final generalPending = generalSnap.data ?? false;

                            if (ownerSnap.hasError || generalSnap.hasError) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Could not load vehicle queue status.',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              );
                            }

                            final waiting =
                                ownerSnap.connectionState == ConnectionState.waiting ||
                                generalSnap.connectionState == ConnectionState.waiting;

                            if (waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                              );
                            }

                            final isMobile = MediaQuery.of(context).size.width < 768;

                            // If there is no vehicle waiting for this driver, do NOT ask for CNIC/license.
                            if (!ownerPending && !generalPending) {
                              return Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(isMobile ? 16 : 20),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.hourglass_empty_rounded,
                                        color: AppColors.primary, size: isMobile ? 28 : 32),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'No Vehicle Available Right Now',
                                            style: TextStyle(
                                              fontSize: isMobile ? 15 : 17,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'When a Vehicle is Available, It will be Assigned to You.',
                                            style: TextStyle(
                                              fontSize: isMobile ? 12 : 13,
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

                            return StreamBuilder<DriverDocumentSubmission?>(
                              stream: _docSubmissionService.watchLatestForDriver(widget.user.id),
                              builder: (context, subSnap) {
                                if (subSnap.hasError) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      'Could not load document status: ${subSnap.error}',
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  );
                                }

                                if (subSnap.connectionState == ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                                  );
                                }

                                return Column(
                                  children: [
                                    DriverCnicLicenseUploadPanel(
                                      user: _currentUser,
                                      latestSubmission: subSnap.data,
                        ),
                      ],
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewMonitoringButton(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isMonitoring)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Live Monitoring Active',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ),
                Text(
                  '${_alertness.clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              if (_isMonitoring) {
                _stopMonitoring();
              } else {
                await _startMonitoring();
                if (mounted && _isMonitoring) {
                  setState(() => _selectedIndex = 2);
                }
              }
            },
            icon: Icon(_isMonitoring ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            label: Text(_isMonitoring ? 'Stop Monitoring' : 'Start Monitoring'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isMonitoring ? AppColors.danger : AppColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 20 : 24,
                vertical: isMobile ? 14 : 16,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertCard([bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: AppColors.primary, size: isMobile ? 22 : 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Current Alertness',
                  style: TextStyle(
                    fontSize: isMobile ? 15 : 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (_isMonitoring) _buildAlertnessStatusBadge(),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Text(
            _isMonitoring ? '${_alertness.clamp(0, 100).toStringAsFixed(1)}%' : '--',
            style: TextStyle(
              fontSize: isMobile ? 36 : 48,
              fontWeight: FontWeight.bold,
              color: _isMonitoring ? Colors.black87 : Colors.grey[400],
            ),
          ),
          if (_isMonitoring) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final targetWidth = (constraints.maxWidth *
                        (_alertness.clamp(0, 100) / 100.0))
                    .clamp(0.0, constraints.maxWidth);
                return Stack(
                  children: [
                    Container(
                      height: 10,
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: targetWidth,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _getAlertnessColor(),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                );
              },
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Start Monitoring to See Live Alertness',
              style: TextStyle(fontSize: isMobile ? 12 : 13, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Color _getAlertnessColor() {
    if (_alertness >= 80) {
      return const Color(0xFF4CAF50); // Green
    } else if (_alertness >= 70) {
      return const Color(0xFFFFA726); // Orange
    } else if (_alertness >= 50) {
      return const Color(0xFFFF9800); // Deep Orange
    } else {
      return const Color(0xFFE53935); // Red
    }
  }

  Widget _buildAlertnessStatusBadge() {
    String statusText;
    Color backgroundColor;
    Color textColor;
    
    if (_alertness >= 80) {
      statusText = 'Excellent';
      backgroundColor = const Color(0xFFE8F5E9);
      textColor = const Color(0xFF4CAF50);
    } else if (_alertness >= 70) {
      statusText = 'Good';
      backgroundColor = const Color(0xFFFFF3E0);
      textColor = const Color(0xFFFFA726);
    } else if (_alertness >= 50) {
      statusText = 'Fair';
      backgroundColor = const Color(0xFFFFE0B2);
      textColor = const Color(0xFFFF9800);
    } else {
      statusText = 'Low';
      backgroundColor = const Color(0xFFFFEBEE);
      textColor = const Color(0xFFE53935);
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildEARMARCard([bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, color: AppColors.primary, size: isMobile ? 22 : 24),
              Icon(Icons.visibility_outlined, color: AppColors.primary, size: isMobile ? 22 : 24),
              const SizedBox(width: 10),
              Text(
                'Eye and Mouth Metrics',
                style: TextStyle(
                  fontSize: isMobile ? 15 : 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 14 : 18),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip('EAR', _ear.toStringAsFixed(2), isMobile),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip('MAR', _mar.toStringAsFixed(2), isMobile),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isMonitoring ? 'Updating Live from Camera' : 'Available when Monitoring is Active',
            style: TextStyle(fontSize: isMobile ? 12 : 13, color: AppColors.textSecondary),
          ),
          if (!isMobile) const Spacer(),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 14, vertical: isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isMobile ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildLiveMonitoringTab(bool isSmallScreen) {
    return _buildRealtimeAlertness();
  }

  Widget _buildCameraTestTab() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Camera Test',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Test camera access separately from face detection',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _isCameraTesting = !_isCameraTesting);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Text(_isCameraTesting ? 'Stop Test' : 'Test Camera'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text(
                'Status: ',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _isMonitoring
                    ? 'Monitoring Active'
                    : _isCameraTesting
                        ? 'Testing...'
                        : 'Ready to test',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ValueListenableBuilder<Uint8List?>(
                    valueListenable: _cameraFrameNotifier,
                    builder: (context, frameBytes, _) {
                      if (frameBytes != null && _isMonitoring) {
                        return Image.memory(
                          frameBytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Error loading camera feed',
                                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      }
                      return Center(
                        child: _isCameraTesting
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Camera is testing...',
                                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                  ),
                                ],
                              )
                            : Text(
                                'Click "Test Camera" to start',
                                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                              ),
                      );
                    })
                    ,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeAlertness() {
    final isMobile = DashboardLayout.isMobile(context);
    final isTablet = DashboardLayout.isTablet(context);
    final gap = isMobile ? 14.0 : (isTablet ? 16.0 : 18.0);

    final metricsSection = _buildDriverSectionCard(
      isMobile: isMobile,
      icon: Icons.speed_outlined,
      title: 'Live Metrics',
      subtitle: _isMonitoring
          ? 'Real-Time Alertness and EAR & MAR Values'
          : 'Metrics Appear when you Start Monitoring',
      child: isMobile
          ? Column(
              children: [
                _buildAlertCard(isMobile),
                SizedBox(height: gap),
                _buildEARMARCard(isMobile),
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildAlertCard(isMobile)),
                  SizedBox(width: gap),
                  Expanded(child: _buildEARMARCard(isMobile)),
                ],
              ),
            ),
    );

    final cameraChild = AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ValueListenableBuilder<Uint8List?>(
            valueListenable: _cameraFrameNotifier,
            builder: (context, frameBytes, _) {
              if (frameBytes != null && _isMonitoring) {
                return Image.memory(
                  frameBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  width: double.infinity,
                  height: double.infinity,
                );
              }
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isMonitoring ? Icons.videocam_off_outlined : Icons.videocam_outlined,
                      size: isMobile ? 48 : 56,
                      color: Colors.white38,
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _isMonitoring
                            ? 'Waiting for Camera Frame...'
                            : 'Start Monitoring from Drowsiness Monitoring to View the Live Feed',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isMobile ? 13 : 14,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        metricsSection,
        SizedBox(height: isMobile ? 14 : 18),
        _buildDriverSectionCard(
          isMobile: isMobile,
          icon: Icons.videocam_outlined,
          title: 'Camera Feed',
          subtitle: _isMonitoring
              ? 'Live Drowsiness Detection from your Device Camera'
              : 'Camera Preview starts when Monitoring is Active',
          trailing: _isMonitoring
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fiber_manual_record, size: 10, color: AppColors.danger),
                      SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          child: cameraChild,
        ),
      ],
    );
  }

 Widget _buildEyeClosureDetection() {
  return Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Eye Closure Detection',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Percentage of time with eyes closed',
          style: TextStyle(
            fontSize: 14,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          height: 420,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFE0E0E0),
              width: 1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_eyeClosurePercentage.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Eyes Closed',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildEmergency() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return _driverPageShell(
      title: 'Emergency',
      subtitle: 'Quick access to emergency services and contacts',
      child: _buildEmergencyContent(isMobile),
    );
  }

  Widget _buildEmergencyServicesGrid(bool isMobile) {
    final police = _buildEmergencyServiceCard(
      'Police', '15', Icons.local_police_outlined,
      AppColors.police, AppColors.policeLight, isMobile,
    );
    final ambulance = _buildEmergencyServiceCard(
      'Ambulance', '1122', Icons.local_hospital_outlined,
      AppColors.ambulance, AppColors.ambulanceLight, isMobile,
    );
    final fire = _buildEmergencyServiceCard(
      'Fire Department', '16', Icons.local_fire_department_outlined,
      AppColors.fire, AppColors.fireLight, isMobile,
    );
    final motorway = _buildEmergencyServiceCard(
      'Motorway Police', '130', Icons.car_crash,
      AppColors.motorway, AppColors.motorwayLight, isMobile,
    );

    if (isMobile) {
      return Column(
        children: [
          Row(children: [Expanded(child: police), const SizedBox(width: 12), Expanded(child: ambulance)]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: fire), const SizedBox(width: 12), Expanded(child: motorway)]),
        ],
      );
    }
    return Column(
      children: [
        Row(children: [Expanded(child: police), const SizedBox(width: 16), Expanded(child: ambulance)]),
        const SizedBox(height: 16),
        Row(children: [Expanded(child: fire), const SizedBox(width: 16), Expanded(child: motorway)]),
      ],
    );
  }

  Widget _buildEmergencyContent(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDriverSectionCard(
          isMobile: isMobile,
          icon: Icons.emergency_outlined,
          title: 'Emergency Services',
          subtitle: 'One-Tap Access to Local Emergency Helplines',
          child: _buildEmergencyServicesGrid(isMobile),
        ),
        SizedBox(height: isMobile ? 14 : 18),
        _buildDriverSectionCard(
          isMobile: isMobile,
          icon: Icons.contacts_outlined,
          title: 'Emergency Contacts',
          subtitle: 'Manage People Notified During Emergency',
          child: EmergencyContactsPanel(user: widget.user, userRole: 'driver'),
        ),
      ],
    );
  }

  Widget _buildEmergencyServiceCard(String title, String number, IconData icon,
      Color color, Color bgColor, [bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Container(
            width: isMobile ? 56 : 64,
            height: isMobile ? 56 : 64,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: isMobile ? 28 : 32),
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Text(
            number,
            style: TextStyle(
              fontSize: isMobile ? 24 : 32,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final Uri url = Uri.parse('tel:$number');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not launch dialer'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.phone, size: 18),
              label: const Text('Call Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildVehicleInfoChip(IconData icon, String label, [bool isMobile = false]) {
    return _vehicleInfoChip(icon, label, isMobile);
  }
}

/// One-shot owner fetch per [vehicle.id] to avoid flicker from repeated stream rebuilds.
class _DriverAssignedVehicleCard extends StatefulWidget {
  const _DriverAssignedVehicleCard({
    super.key,
    required this.vehicle,
    required this.isMobile,
  });

  final Vehicle vehicle;
  final bool isMobile;

  @override
  State<_DriverAssignedVehicleCard> createState() => _DriverAssignedVehicleCardState();
}

class _DriverAssignedVehicleCardState extends State<_DriverAssignedVehicleCard> {
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _ownerDocFuture =
      FirebaseFirestore.instance.collection('users').doc(widget.vehicle.ownerId).get();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _ownerDocFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }

        final ownerDoc = snapshot.data;
        final owner = (ownerDoc != null && ownerDoc.exists) ? (ownerDoc.data() ?? {}) : <String, dynamic>{};
        final ownerName =
            '${owner['firstName'] ?? ''} ${owner['lastName'] ?? ''}'.trim();
        final ownerPhone = (owner['phone'] as String?) ?? '';

        final v = widget.vehicle;
        final isMobile = widget.isMobile;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 16 : 20),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.directions_car_filled_outlined,
                        color: AppColors.primary, size: isMobile ? 22 : 26),
                  ),
                  SizedBox(width: isMobile ? 12 : 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${v.make} ${v.model}',
                          style: TextStyle(
                            fontSize: isMobile ? 17 : 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Year ${v.year} • ${v.type}',
                          style: TextStyle(
                            fontSize: isMobile ? 12 : 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 14 : 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _vehicleInfoChip(Icons.confirmation_number, v.licensePlate, isMobile),
                  if ((v.ownerEmail ?? '').isNotEmpty)
                    _vehicleInfoChip(Icons.person_outline, 'Owner: ${v.ownerEmail}', isMobile),
                  if (ownerName.isNotEmpty)
                    _vehicleInfoChip(Icons.badge_outlined, 'Owner Name: $ownerName', isMobile),
                ],
              ),
              if (ownerPhone.isNotEmpty) ...[
                SizedBox(height: isMobile ? 10 : 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('tel:$ownerPhone');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                  ),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Call Owner'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

Widget _vehicleInfoChip(IconData icon, String label, bool isMobile) {
  return Container(
    padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 12, vertical: isMobile ? 5 : 6),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: isMobile ? 14 : 16, color: Colors.grey[600]),
        SizedBox(width: isMobile ? 6 : 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isMobile ? 12 : 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// Custom formatter for phone number input (03XX-1234567 format)
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Limit to 11 digits (03XX1234567)
    if (text.length > 11) {
      return oldValue;
    }
    
    String formatted = text;
    
    // Insert dash after 4 digits if not already present
    if (text.length > 4 && !text.contains('-')) {
      formatted = '${text.substring(0, 4)}-${text.substring(4)}';
    } else if (text.length <= 4) {
      formatted = text;
    }
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
