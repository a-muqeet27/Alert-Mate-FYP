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
import '../models/emergency_contact.dart';
import '../models/driver_document_submission.dart';
import '../services/vehicle_service.dart';
import '../services/driver_document_submission_service.dart';
import '../widgets/driver_cnic_license_upload_panel.dart';
import '../services/emergency_contact_service.dart';
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
import '../widgets/dashboard_detail_dialog_theme.dart';
import '../utils/dashboard_responsive.dart';

class DriverDashboard extends StatefulWidget {
  final User user;

  const DriverDashboard({Key? key, required this.user}) : super(key: key);

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _selectedTab = 0;

  List<MenuItem> get _sidebarMenuItems => [
        const MenuItem(
          section: 'Monitoring',
          icon: Icons.home_outlined,
          title: 'Overview',
        ),
        const MenuItem(
          section: 'Monitoring',
          icon: Icons.show_chart_outlined,
          title: 'Alertness',
        ),
        const MenuItem(
          section: 'Monitoring',
          icon: Icons.videocam_outlined,
          title: 'Live Monitoring',
        ),
        const MenuItem(
          section: 'Monitoring',
          icon: Icons.tune_outlined,
          title: 'Alert Settings',
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
          unreadBadgeStream: UserNotificationsService.unreadCountStream(widget.user.id),
        ),
      ];

  Widget _sidebarMainBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildDriverOverviewPage();
      case 1:
        return _buildDriverAlertnessPage();
      case 2:
        return _buildDriverLiveMonitoringPage();
      case 3:
        return _buildDriverSettingsPage();
      case 4:
        return _buildEmergency();
      case 5:
        return _buildDriverNotificationsPage();
      default:
        return _buildDriverOverviewPage();
    }
  }

  String get _currentPageTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Overview';
      case 1:
        return 'Alertness';
      case 2:
        return 'Live Monitoring';
      case 3:
        return 'Alert Settings';
      case 4:
        return 'Emergency';
      case 5:
        return 'Notifications';
      default:
        return 'Overview';
    }
  }

  String get _currentPageSubtitle {
    switch (_selectedIndex) {
      case 0:
        return 'Real-time drowsiness monitoring';
      case 1:
        return 'Current alertness level and eye metrics';
      case 2:
        return 'Real-time camera and drowsiness detection';
      case 3:
        return 'Audio alerts, contacts, and sensitivity';
      case 4:
        return 'Quick access to emergency services and contacts';
      case 5:
        return 'Alerts and system messages';
      default:
        return 'Real-time drowsiness monitoring';
    }
  }

  Widget _buildDriverNotificationsPage() {
    return _driverPageShell(
      title: 'Notifications',
      subtitle: 'Alerts and system messages',
      child: NotificationsInboxScreen(user: widget.user, embedded: true),
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

  Widget _buildDriverAlertnessPage() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final isTablet = MediaQuery.of(context).size.width < 1024 && !isMobile;
    final gap = isMobile ? 12.0 : (isTablet ? 16.0 : 20.0);
    return _driverPageShell(
      title: 'Alertness',
      subtitle: 'Current alertness level and eye metrics',
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
  }

  Widget _buildDriverLiveMonitoringPage() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return _driverPageShell(
      title: 'Live Monitoring',
      subtitle: 'Real-time camera and drowsiness detection',
      child: _buildLiveMonitoringTab(isMobile),
    );
  }

  Widget _buildDriverSettingsPage() {
    return _driverPageShell(
      title: 'Alert Settings',
      subtitle: 'Audio alerts, contacts, and sensitivity',
      child: _buildAlertSettingsTab(),
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
  final EmergencyContactService _emergencyContactService = EmergencyContactService();
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
      print('⚠️ Sync assigned vehicle status: $e');
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
  bool _emergencyContactsEnabled = true;
  String _sensitivityLevel = 'Medium';
  
  // Yawning detection tracking
  int _yawningFrameCount = 0;
  bool _buzzerPlayed = false;
  Timer? _drowsyBuzzerTimer;
  DateTime _lastBuzzerAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMetricsUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _buzzerCooldown = Duration(milliseconds: 1200);
  static const Duration _metricsUiThrottle = Duration(milliseconds: 300);
  /// EMA smoothing for alertness bar (0–1, higher = react faster to EAR/MAR).
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

  /// Maps EAR/MAR/eye closure into 0–100; blended with server [alertness] when present.
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

    // EAR: eyes open → higher ratio (typical open ~0.22–0.38 depending on model scale).
    const earOpen = 0.36;
    const earClosed = 0.14;
    final earSpan = earOpen - earClosed;
    final fromEar =
        earSpan <= 1e-6 ? 70.0 : (((e - earClosed) / earSpan) * 100.0).clamp(0.0, 100.0);

    // MAR: mouth open / yawning → lower alertness.
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

    // Mark driver as online (idle) in Firestore so the map shows them
    _locationUpdateService.goOnline(widget.user.id, widget.user.fullName);
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
        print('❌ Camera permission denied');
        return;
      }
      
      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        print('❌ No cameras available');
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
      
      print('✅ Camera initialized: ${camera.name}');
    } catch (e) {
      print('❌ Error initializing camera: $e');
    }
  }
  
  Future<void> _startCameraStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print('❌ Camera not initialized');
      return;
    }
    
    if (_channel == null) {
      print('❌ WebSocket not connected');
      return;
    }
    
    try {
      print('📸 Setting up camera frame capture...');
      
      // Use a slower rate to avoid overwhelming the connection
      // takePicture is slower but produces proper JPEG images
      int frameCount = 0;
      bool isCapturing = false;
      
      _frameCaptureTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        if (!_isMonitoring || _channel == null) {
          print('⏹️ Stopping camera capture timer');
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
              print('📤 Sending frame #$frameCount (${imageBytes.length} bytes)');
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
          print('❌ Error capturing frame: $e');
        } finally {
          isCapturing = false;
        }
      });
      
      print('✅ Camera stream started - capturing frames every 500ms');
    } catch (e) {
      print('❌ Error starting camera stream: $e');
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
    // ── ngrok public tunnel ─────────────────────────────────────────────────
    // Works on every platform (Android, iOS, Web, Desktop) without any
    // IP-address changes or mobile-hotspot setup.
    //
    // ngrok is HTTPS  →  WebSocket must use wss:// (secure), not ws://.
    // To update the URL when ngrok restarts, edit AppConfig.ngrokBaseUrl
    // in lib/constants/app_config.dart — change it in one place only.
    final url = AppConfig.wsMonitorUrl;
    print('🔌 Connecting to backend via ngrok: $url');
    return url;
  }

  void _startMonitoring() async {
    final driverId = widget.user.id;

    // Validate driver ID
    if (driverId == null) {
      print('❌ Driver ID is missing');
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

    print('🚀 Starting monitoring for driver: $driverId');

    try {
    // Start Firebase session
      _currentSessionId = await _monitoringService.startMonitoringSession(driverId);
      print('✅ Firebase session started: $_currentSessionId');
    } catch (e) {
      print('❌ Failed to start Firebase session: $e');
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
      print('❌ Camera not initialized, initializing now...');
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
      print('🔌 Connecting to FastAPI server at $wsUrl...');
      if (!kIsWeb) {
        // Platform.* is dart:io only — unavailable on Flutter Web
        print('📱 Platform: ${Platform.operatingSystem}');
        print('📱 Is Android: ${Platform.isAndroid}');
        print('📱 Is iOS: ${Platform.isIOS}');
      }

      // Connect to WebSocket with proper error handling
      try {
        print('🔌 Attempting to connect to $wsUrl...');
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        print('✅ WebSocket channel created');
      } catch (e) {
        print('❌ Error creating WebSocket channel: $e');
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
              print('✅ Connection confirmed - received first message from server');
            }
            
            print('📦 Received message (first 150 chars): ${message.toString().substring(0, min(150, message.toString().length))}...');

            final data = json.decode(message) as Map<String, dynamic>;
            
            // Handle error messages
            if (data.containsKey('error')) {
              print('❌ Error from server: ${data['error']}');
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
              print('ℹ️ Status update: ${data['status']}');
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
                print('🥱 Yawning detected (frame $_yawningFrameCount)');

                // Play buzzer when 5-7 frames detect yawning (only once per session)
                if (_yawningFrameCount >= 5 && _yawningFrameCount <= 7 && !_buzzerPlayed && _audioAlertsEnabled) {
                  _playBuzzerIfAllowed();
                  _buzzerPlayed = true;
                  print('🔔 Buzzer played - Yawning detected for $_yawningFrameCount frames');
                }

                // Reset after 7 frames to allow buzzer to play again
                if (_yawningFrameCount > 7) {
                  _yawningFrameCount = 0;
                  _buzzerPlayed = false;
                  print('🔄 Yawning counter reset');
                }
              } else {
                // Reset counter when not yawning
                if (_yawningFrameCount > 0) {
                  print('🔄 Yawning stopped, resetting counter');
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
                print('📊 Metrics - Alertness: ${_alertness.toStringAsFixed(1)}%, EAR: ${_ear.toStringAsFixed(2)}, MAR: ${_mar.toStringAsFixed(2)}');
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
                        '⚠️ Skipping incomplete/bad JPEG (${decodedFrame.length} B). '
                        'Often caused by WebSocket echo truncation or overlapping sessions.',
                      );
                    }
                  } else {
                    _updateCameraFrame(decodedFrame);
                    _decodedFrameDiagCount++;
                    if (_decodedFrameDiagCount <= 3 || _decodedFrameDiagCount % 25 == 0) {
                      print('📸 Camera frame (${decodedFrame.length} bytes)');
                    }
                  }
                } catch (e) {
                  print('❌ Error decoding frame: $e');
                }
              }

              _setDrowsyAlarmActive(isDrowsy);
            }
          } catch (e, stackTrace) {
            print('❌ Error parsing message: $e');
            print('Stack trace: $stackTrace');
          }
        },
        onError: (error) {
          print('❌ WebSocket error: $error');
          print('❌ Connection URL was: $wsUrl');
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
                    const Text('❌ Connection Error',
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
          print('🔌 WebSocket connection closed');
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

      print('✅ WebSocket listener attached successfully');
      
    } catch (e, stackTrace) {
      print('❌ Failed to connect to WebSocket server: $e');
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
                const Text('❌ Failed to connect to server',
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
    print('⏱️ Starting Firebase stats update timer (1s interval)');
    _statsUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isMonitoring) {
        timer.cancel();
        print('⏱️ Stats timer cancelled - monitoring stopped');
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

    print('✅ Monitoring started successfully');
  }
  void _stopMonitoring() async {
    print('🛑 Stopping monitoring...');

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
      print('⏱️ Update timer cancelled');
    }

    if (_statsUpdateTimer != null) {
      _statsUpdateTimer!.cancel();
      _statsUpdateTimer = null;
      print('⏱️ Stats timer cancelled');
    }
    
    // Close WebSocket connection
    if (_channel != null) {
      try {
        await _channel!.sink.close();
        print('🔌 WebSocket connection closed');
      } catch (e) {
        print('⚠️ Error closing WebSocket: $e');
      }
    _channel = null;
    }
    
    // Clear camera frame
    _updateCameraFrame(null);
    print('📸 Camera frame cleared');
    
    // End Firebase session
    if (_currentSessionId != null && driverId != null) {
      try {
      await _monitoringService.endMonitoringSession(driverId);
        print('✅ Firebase session ended: $_currentSessionId');
      _currentSessionId = null;
      } catch (e) {
        print('⚠️ Error ending Firebase session: $e');
      }
    }

    // Clear current stats from Realtime Database
    if (driverId != null) {
      try {
        await _monitoringService.clearCurrentStats(driverId);
        print('✅ Current stats cleared from Realtime Database');
      } catch (e) {
        print('⚠️ Error clearing current stats: $e');
      }
    }

    _lastSyncedFirestoreVehicleStatus = null;
    await _syncAssignedVehicleFirestoreStatus('Offline');

    // Revert driver to idle in Firestore and stop GPS updates
    _lastDrowsyState = false;
    await _locationUpdateService.goIdle(driverId);

    print('✅ Monitoring stopped successfully');

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

    print('🔍 Launching Python with:');
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
      print('📊 Python stdout: $line');
      try {
        final data = json.decode(line) as Map<String, dynamic>;
        
        if (data.containsKey('error')) {
          print('❌ Python error: ${data['error']}');
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
          print('✅ Python status: ${data['status']}');
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
              // Play buzzer when 5-7 frames detect yawning (only once per yawning session)
              if (_yawningFrameCount >= 5 && _yawningFrameCount <= 7 && !_buzzerPlayed && _audioAlertsEnabled) {
                _playBuzzerIfAllowed();
                _buzzerPlayed = true;
                print('🔔 Buzzer played - Yawning detected for $_yawningFrameCount frames');
              }
              // Reset after 7 frames to allow buzzer to play again if yawning continues
              if (_yawningFrameCount > 7) {
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
                content: Text('⚠️ DROWSINESS ALERT: $reasonText'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        print('❌ Error parsing JSON: $e, Line: $line');
      }
    });

    // Listen to stderr (errors and debug info)
    _monitorProcess!.stderr.transform(utf8.decoder).listen((error) {
      print('🔴 Python stderr: $error');
    });

    // When process exits
    _monitorProcess!.exitCode.then((exitCode) {
      print('🛑 Python process exited with code: $exitCode');
      if (mounted && _isMonitoring) {
        setState(() {
          _isMonitoring = false;
        });
        _setDrowsyAlarmActive(false);
      }
    });
    
    print('✅ Python process started successfully!');
    
  } catch (e) {
    print('💥 Error launching Python: $e');
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
    
    return Scaffold(
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
            user: widget.user,
            selectedIndex: _selectedIndex,
            onMenuItemTap: (index) => setState(() => _selectedIndex = index),
            menuItems: _sidebarMenuItems,
            accentColor: AppColors.primary,
            accentLightColor: AppColors.driverLight,
          ),
          body: _sidebarMainBody(),
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
          accentLightColor: AppColors.driverLight,
        ),
      ),
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
    final isMobile = MediaQuery.of(context).size.width < 768;
    return _driverPageShell(
      title: 'Overview',
      subtitle: 'Real-time drowsiness monitoring',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildOverviewMonitoringButton(isMobile),
                    const SizedBox(height: 10),
                    _buildOverviewHistoryButton(isMobile),
                  ],
                )
              : Row(
                  children: [
                    _buildOverviewMonitoringButton(isMobile),
                    const SizedBox(width: 12),
                    _buildOverviewHistoryButton(isMobile),
                  ],
                ),
          const SizedBox(height: 16),
          StreamBuilder<Vehicle?>(
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
                              return Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppColors.driverPrimary.withOpacity(0.25)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.schedule, color: AppColors.primary, size: isMobile ? 22 : 26),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'No vehicles in queue',
                                                style: TextStyle(
                                                  fontSize: isMobile ? 16 : 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'When an approved vehicle is waiting for you (or for any driver), you will be asked to upload CNIC and license for admin approval.',
                                          style: TextStyle(fontSize: isMobile ? 12 : 13, color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
                                      user: widget.user,
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
        ],
      ),
    );
  }

  Widget _buildOverviewMonitoringButton(bool isMobile) {
    return SizedBox(
      width: isMobile ? double.infinity : null,
      child: ElevatedButton.icon(
        onPressed: _isMonitoring ? _stopMonitoring : _startMonitoring,
        icon: Icon(_isMonitoring ? Icons.pause : Icons.visibility),
        label: Text(_isMonitoring ? 'Stop Monitoring' : 'Start Monitoring'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 20 : 24,
            vertical: isMobile ? 12 : 14,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildOverviewHistoryButton(bool isMobile) {
    return SizedBox(
      width: isMobile ? double.infinity : null,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DriverHistoryScreen(driverId: widget.user.id),
            ),
          );
        },
        icon: const Icon(Icons.history),
        label: const Text('View History'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 20 : 24,
            vertical: isMobile ? 12 : 14,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildAlertCard([bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Current Alertness',
                  style: TextStyle(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              Icon(Icons.show_chart, color: Colors.grey[400], size: isMobile ? 18 : 20),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Text(
            '${_alertness.clamp(0, 100).toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: isMobile ? 36 : 48,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          _buildAlertnessStatusBadge(),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final targetWidth =
                  (constraints.maxWidth * (_alertness.clamp(0, 100) / 100.0)).clamp(0.0, constraints.maxWidth);
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
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'EAR / MAR',
                  style: TextStyle(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              Icon(Icons.timeline, color: Colors.grey[400], size: isMobile ? 18 : 20),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Text(
            'EAR ${_ear.toStringAsFixed(2)} • MAR ${_mar.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isMobile ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Live from camera',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black54,
            ),
          ),
          if (!isMobile) const Spacer(),
        ],
      ),
    );
  }


  Widget _buildTabBar([bool isMobile = false]) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildTab('Live Monitoring', 0, isMobile),
          SizedBox(width: isMobile ? 8 : 8),
          _buildTab('Alert Settings', 1, isMobile),
        ],
      ),
    );
  }

  Widget _buildTab(String text, int index, [bool isMobile = false]) {
    final isActive = _selectedTab == index;
    return AnimatedScale(
      scale: isActive ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 20,
              vertical: isMobile ? 10 : 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? const Border(
              bottom: BorderSide(color: AppColors.primary, width: 2),
            )
                : null,
            boxShadow: isActive ? [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? AppColors.primary : Colors.black54,
            ),
            child: Text(text),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(bool isSmallScreen) {
    switch (_selectedTab) {
      case 0:
        return _buildLiveMonitoringTab(isSmallScreen);
      case 1:
        return _buildAlertSettingsTab();
      default:
        return _buildLiveMonitoringTab(isSmallScreen);
    }
  }

  Widget _buildLiveMonitoringTab(bool isSmallScreen) {
    return _buildRealtimeAlertness();
  }

  Widget _buildAlertSettingsTab() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alert Configuration',
            style: TextStyle(
              fontSize: isMobile ? 18 : 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Text(
            'Customize your Drowsiness Detection Alerts',
            style: TextStyle(
              fontSize: isMobile ? 12 : 14,
              color: Colors.black54,
            ),
          ),
          SizedBox(height: isMobile ? 24 : 32),
          _buildSettingRow(
            'Audio Alerts',
            'Sound alarm when drowsiness detected',
            _audioAlertsEnabled,
                (value) => setState(() => _audioAlertsEnabled = value),
            actionWidget: Switch(
              value: _audioAlertsEnabled,
              onChanged: (value) {
                setState(() => _audioAlertsEnabled = value);
                if (!value) {
                  _setDrowsyAlarmActive(false);
                } else if (_isMonitoring && _alertness < 80.0) {
                  _setDrowsyAlarmActive(true);
                }
              },
              activeColor: AppColors.primary,
            ),
          ),
          const Divider(height: 32),
          _buildSettingRowWithButton(
            'Change Alert Sound',
            'Open mobile sound settings',
            'Change Audio',
                () {
              _openSoundSettings();
            },
          ),
          const Divider(height: 48),
          _buildSettingRow(
            'Emergency Contacts',
            'Auto-notify contacts on critical alerts',
            _emergencyContactsEnabled,
                (value) => setState(() => _emergencyContactsEnabled = value),
            actionWidget: Switch(
              value: _emergencyContactsEnabled,
              onChanged: (value) => setState(() => _emergencyContactsEnabled = value),
              activeColor: AppColors.primary,
            ),
          ),
          const Divider(height: 48),
          _buildSettingRowWithButton(
            'Sensitivity Level',
            'Adjust detection sensitivity',
            _sensitivityLevel,
                () {
              _showSensitivityDialog();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(String title,
      String subtitle,
      bool value,
      Function(bool) onChanged, {
        Widget? actionWidget,
      }) {
    final isMobile = DashboardLayout.isMobile(context);
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isMobile ? 15 : 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: isMobile ? 13 : 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
    if (actionWidget == null) return label;
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: actionWidget),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: label),
        actionWidget,
      ],
    );
  }

  Widget _buildSettingRowWithButton(String title,
      String subtitle,
      String buttonText,
      VoidCallback onPressed,) {
    final isMobile = DashboardLayout.isMobile(context);
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isMobile ? 15 : 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: isMobile ? 13 : 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: onPressed,
              child: Text(buttonText),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: label),
        OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            side: BorderSide(color: Colors.grey[300]!),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            buttonText,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openSoundSettings() async {
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
    if (await openAppSettings()) {
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open sound settings automatically.'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  void _showSensitivityDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            backgroundColor: DashboardDetailDialogTheme.surface,
            surfaceTintColor: Colors.transparent,
            title: const Text('Sensitivity Level'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile(
                  title: const Text('Low'),
                  value: 'Low',
                  groupValue: _sensitivityLevel,
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    setState(() => _sensitivityLevel = value.toString());
                    Navigator.pop(context);
                  },
                ),
                RadioListTile(
                  title: const Text('Medium'),
                  value: 'Medium',
                  groupValue: _sensitivityLevel,
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    setState(() => _sensitivityLevel = value.toString());
                    Navigator.pop(context);
                  },
                ),
                RadioListTile(
                  title: const Text('High'),
                  value: 'High',
                  groupValue: _sensitivityLevel,
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    setState(() => _sensitivityLevel = value.toString());
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
    );
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
                  backgroundColor: const Color(0xFF6366F1),
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
                    ? 'Monitoring active'
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
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Real-time Alertness',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: isMobile ? 4 : 6),
          Text(
            'Live drowsiness detection from the camera',
            style: TextStyle(
              fontSize: isMobile ? 12 : 14,
              color: Colors.black54,
            ),
          ),
          SizedBox(height: isMobile ? 16 : 24),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
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
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildEmergencyContent(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            isMobile
                ? Column(
              children: [
                Row(
                  children: [
                    Expanded(
                  child: _buildEmergencyServiceCard(
                    'Police',
                    '15',
                        Icons.local_police_outlined,
                        const Color(0xFFE2A9F1),
                        const Color(0xFFF5E6FA),
                    isMobile,
                  ),
                ),
                    const SizedBox(width: 12),
                    Expanded(
                  child: _buildEmergencyServiceCard(
                    'Ambulance',
                    '1122',
                        Icons.local_hospital_outlined,
                        Colors.red[700]!,
                        Colors.red[50]!,
                    isMobile,
                  ),
                ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                  child: _buildEmergencyServiceCard(
                    'Fire Department',
                    '16',
                        Icons.local_fire_department_outlined,
                        Colors.orange[700]!,
                        Colors.orange[50]!,
                    isMobile,
                  ),
                ),
                    const SizedBox(width: 12),
                    Expanded(
                  child: _buildEmergencyServiceCard(
                    'Motorway Police',
                    '130',
                    Icons.car_crash,
                    const Color(0xFF4CAF50),
                    const Color(0xFFE8F5E9),
                    isMobile,
                  ),
                    ),
                  ],
                ),
              ],
            )
                : Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildEmergencyServiceCard(
                        'Police',
                        '15',
                        Icons.local_police_outlined,
                        const Color(0xFFE2A9F1),
                        const Color(0xFFF5E6FA),
                        isMobile,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildEmergencyServiceCard(
                        'Ambulance',
                        '1122',
                        Icons.local_hospital_outlined,
                        Colors.red[700]!,
                        Colors.red[50]!,
                        isMobile,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildEmergencyServiceCard(
                        'Fire Department',
                        '16',
                        Icons.local_fire_department_outlined,
                        Colors.orange[700]!,
                        Colors.orange[50]!,
                        isMobile,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildEmergencyServiceCard(
                        'Motorway Police',
                        '130',
                        Icons.car_crash,
                        const Color(0xFF4CAF50),
                        const Color(0xFFE8F5E9),
                        isMobile,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: isMobile ? 20 : 24),

        _buildEmergencyContactsTable(isMobile),
      ],
    );
  }

  Widget _buildEmergencyServiceCard(String title, String number, IconData icon,
      Color color, Color bgColor, [bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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

  // Add Contact Dialog
  void _showAddContactDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final relationshipController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    String priority = 'secondary';
    List<String> methods = ['call'];
    final scaffoldContext = context; // Store scaffold context

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Emergency Contact'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                  TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Name is required';
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 16),
                  TextFormField(
                  controller: relationshipController,
                  decoration: const InputDecoration(
                    labelText: 'Relationship *',
                    border: OutlineInputBorder(),
                  ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Relationship is required';
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 16),
                  TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                      hintText: '03XX-1234567',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                      _PhoneNumberFormatter(),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Phone number is required';
                      }
                      final phone = value.trim();
                      if (!RegExp(r'^03\d{2}-\d{7}$').hasMatch(phone)) {
                        return 'Phone must be in format 03XX-1234567';
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 16),
                  TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                          return 'Please enter a valid email address';
                        }
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'primary', child: Text('Primary')),
                    DropdownMenuItem(value: 'secondary', child: Text('Secondary')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      priority = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                  const Text('Contact Methods: *', style: TextStyle(fontWeight: FontWeight.bold)),
                CheckboxListTile(
                  title: const Text('Phone Call'),
                  value: methods.contains('call'),
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        methods.add('call');
                      } else {
                        methods.remove('call');
                      }
                    });
                  },
                ),
                CheckboxListTile(
                  title: const Text('Email'),
                  value: methods.contains('email'),
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        methods.add('email');
                      } else {
                        methods.remove('email');
                      }
                    });
                  },
                ),
                  if (methods.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'At least one contact method is required',
                        style: TextStyle(color: Colors.red[700], fontSize: 12),
                      ),
                    ),
              ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (methods.isEmpty) {
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please select at least one contact method'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                if (formKey.currentState!.validate()) {
                try {
                  await _emergencyContactService.addEmergencyContact(
                    userId: widget.user.id,
                    userRole: 'driver',
                    contactData: {
                        'name': nameController.text.trim(),
                        'relationship': relationshipController.text.trim(),
                        'phone': phoneController.text.trim(),
                        'email': emailController.text.trim(),
                      'priority': priority,
                      'methods': methods,
                      'enabled': true,
                    },
                  );
                  
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text('${nameController.text} added to emergency contacts'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text('Error adding contact: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    }
                  }
                }
              },
              child: const Text('Add Contact'),
            ),
          ],
        ),
      ),
    );
  }

  // Edit Contact Dialog
  void _showEditContactDialog(EmergencyContact contact) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: contact.name);
    final relationshipController = TextEditingController(text: contact.relationship);
    final phoneController = TextEditingController(text: contact.phone);
    final emailController = TextEditingController(text: contact.email);
    String priority = contact.priority;
    List<String> methods = List<String>.from(contact.methods);
    final scaffoldContext = context; // Store scaffold context

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Emergency Contact'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                  TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Name is required';
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 16),
                  TextFormField(
                  controller: relationshipController,
                  decoration: const InputDecoration(
                    labelText: 'Relationship *',
                    border: OutlineInputBorder(),
                  ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Relationship is required';
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 16),
                  TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                      hintText: '03XX-1234567',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                      _PhoneNumberFormatter(),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Phone number is required';
                      }
                      final phone = value.trim();
                      if (!RegExp(r'^03\d{2}-\d{7}$').hasMatch(phone)) {
                        return 'Phone must be in format 03XX-1234567';
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value != null && value.trim().isNotEmpty) {
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                        return 'Please enter a valid email address';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'primary', child: Text('Primary')),
                    DropdownMenuItem(value: 'secondary', child: Text('Secondary')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      priority = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                const Text('Contact Methods: *', style: TextStyle(fontWeight: FontWeight.bold)),
                CheckboxListTile(
                  title: const Text('Phone Call'),
                  value: methods.contains('call'),
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        methods.add('call');
                      } else {
                        methods.remove('call');
                      }
                    });
                  },
                ),
                CheckboxListTile(
                  title: const Text('Email'),
                  value: methods.contains('email'),
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        methods.add('email');
                      } else {
                        methods.remove('email');
                      }
                    });
                  },
                ),
                  if (methods.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'At least one contact method is required',
                        style: TextStyle(color: Colors.red[700], fontSize: 12),
                      ),
                    ),
              ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (methods.isEmpty) {
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please select at least one contact method'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                if (formKey.currentState!.validate()) {
                try {
                  await _emergencyContactService.updateEmergencyContact(
                    contactId: contact.id,
                    contactData: {
                        'name': nameController.text.trim(),
                        'relationship': relationshipController.text.trim(),
                        'phone': phoneController.text.trim(),
                        'email': emailController.text.trim(),
                      'priority': priority,
                      'methods': methods,
                      'enabled': contact.enabled,
                    },
                  );
                  
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text('${nameController.text} updated successfully'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text('Error updating contact: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    }
                  }
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyContactsTable([bool isMobile = false]) {
    return StreamBuilder<List<EmergencyContact>>(
      stream: _emergencyContactService.getEmergencyContactsStream(widget.user.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: EdgeInsets.all(isMobile ? 16 : 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('Error loading contacts: ${snapshot.error}'),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: EdgeInsets.all(isMobile ? 16 : 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }

        final contacts = snapshot.data ?? [];

        return Container(
          padding: EdgeInsets.all(isMobile ? 16 : 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardLayout.sectionHeader(
                context: context,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Contacts',
                      style: TextStyle(
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: isMobile ? 2 : 4),
                    Text(
                      'Manage your emergency contact list',
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                action: ElevatedButton.icon(
                  onPressed: _showAddContactDialog,
                  icon: Icon(Icons.add, size: isMobile ? 16 : 18),
                  label: Text('Add Contact', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 20,
                      vertical: isMobile ? 10 : 12,
                    ),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              SizedBox(height: isMobile ? 16 : 24),
              isMobile
                  ? contacts.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(isMobile ? 20 : 40),
                          child: Center(
                            child: Text(
                              'No emergency contacts added yet',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: contacts.map((contact) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildMobileContactCard(contact),
                              )).toList(),
                        )
                  : DashboardLayout.horizontalTable(
                      context: context,
                      minWidth: 800,
                      table: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.5),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.8),
                        3: FlexColumnWidth(1.0),
                        4: FlexColumnWidth(1.0),
                        5: FlexColumnWidth(0.8),
                        6: FlexColumnWidth(1.0),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          children: [
                            _buildTableHeader('Name', isMobile),
                            _buildTableHeader('Relationship', isMobile),
                            _buildTableHeader('Contact', isMobile),
                            _buildTableHeader('Priority', isMobile),
                            _buildTableHeader('Methods', isMobile),
                            _buildTableHeader('Status', isMobile),
                            _buildTableHeader('Actions', isMobile),
                          ],
                        ),
                        ...contacts.map((contact) => _buildEmergencyContactRow(contact, isMobile)),
                      ],
                    ),
                  ),
              SizedBox(height: isMobile ? 16 : 20),
              Row(
                children: [
                  Icon(Icons.info_outline, size: isMobile ? 14 : 16, color: Colors.grey[600]),
                  SizedBox(width: isMobile ? 6 : 8),
                  Flexible(
                    child: Text(
                      'Last system test: Just now • ${contacts.length} active contacts',
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildMobileContactCard(EmergencyContact contact) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  contact.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              _buildContactActionsCell(contact, true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            contact.relationship,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.phone, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(contact.phone, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.email, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  contact.email,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPriorityBadgeCell(contact.priority, true),
              ),
              const SizedBox(width: 8),
              _buildStatusToggleCell(contact, true),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildEmergencyContactRow(EmergencyContact contact, [bool isMobile = false]) {
    return TableRow(
      children: [
        _buildTableCell(contact.name, isMobile),
        _buildTableCell(contact.relationship, isMobile),
        _buildContactInfoCell(contact.phone, contact.email, isMobile),
        _buildPriorityBadgeCell(contact.priority, isMobile),
        _buildMethodsCell(contact.methods, isMobile),
        _buildStatusToggleCell(contact, isMobile),
        _buildContactActionsCell(contact, isMobile),
      ],
    );
  }

  Widget _buildTableHeader(String text, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 8 : 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isMobile ? 11 : 13,
          fontWeight: FontWeight.w600,
          color: Colors.black54,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 12 : 16),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isMobile ? 12 : 14,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildContactInfoCell(String phone, String email, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phone,
            style: TextStyle(
              fontSize: isMobile ? 12 : 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          if (email.isNotEmpty) ...[
            SizedBox(height: isMobile ? 2 : 4),
            Text(
              email,
              style: TextStyle(
                fontSize: isMobile ? 11 : 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriorityBadgeCell(String priority, [bool isMobile = false]) {
    final isPrimary = priority == 'primary';
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 16,
          vertical: isMobile ? 0 : 12),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 12,
            vertical: isMobile ? 4 : 6),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.red : const Color(0xFFFF6F00),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          priority,
          style: TextStyle(
            fontSize: isMobile ? 10 : 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildMethodsCell(List<dynamic> methods, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 8 : 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (methods.contains('call'))
            Icon(Icons.phone, size: isMobile ? 16 : 18, color: AppColors.primary),
          if (methods.contains('call')) SizedBox(width: isMobile ? 4 : 6),
          if (methods.contains('email'))
            Icon(Icons.email, size: isMobile ? 16 : 18, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildStatusToggleCell(EmergencyContact contact, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 16,
          vertical: isMobile ? 0 : 12),
      child: Switch(
        value: contact.enabled,
        onChanged: (value) async {
          try {
            await _emergencyContactService.toggleContactEnabled(contact.id, value);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error updating contact: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        activeColor: const Color(0xFF2196F3),
      ),
    );
  }

  Widget _buildContactActionsCell(EmergencyContact contact, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 8,
          vertical: isMobile ? 0 : 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.call_outlined, size: isMobile ? 18 : 20, color: Colors.green[700]),
            onPressed: () async {
              final uri = Uri.parse('tel:${contact.phone}');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          SizedBox(width: isMobile ? 4 : 8),
          IconButton(
            icon: Icon(Icons.edit_outlined, size: isMobile ? 18 : 20),
            onPressed: () {
              _showEditContactDialog(contact);
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          SizedBox(width: isMobile ? 4 : 8),
          IconButton(
            icon: Icon(Icons.delete_outline, size: isMobile ? 18 : 20),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Contact'),
                  content: Text('Are you sure you want to delete ${contact.name} from emergency contacts? This action cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                try {
                  await _emergencyContactService.deleteEmergencyContact(contact.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${contact.name} removed'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error deleting contact: $e')),
                    );
                  }
                }
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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
          padding: EdgeInsets.all(isMobile ? 14 : 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.driverPrimary.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.directions_car, color: AppColors.primary, size: isMobile ? 20 : 22),
                  SizedBox(width: isMobile ? 8 : 10),
                  Expanded(
                    child: Text(
                      'Assigned Vehicle: ${v.make} ${v.model} (${v.year})',
                      style: TextStyle(
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 10 : 12),
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