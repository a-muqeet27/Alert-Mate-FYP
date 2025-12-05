import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/user.dart';
import '../models/vehicle.dart';
import '../models/emergency_contact.dart';
import '../services/vehicle_service.dart';
import '../services/emergency_contact_service.dart';
import '../services/monitoring_service.dart';
import 'package:firebase_database/firebase_database.dart';
import '../auth_screen.dart';
import '../widgets/shared/app_sidebar.dart';
import '../constants/app_colors.dart';
import '../screens/driver_history_screen.dart';

class DriverDashboard extends StatefulWidget {
  final User user;

  const DriverDashboard({Key? key, required this.user}) : super(key: key);

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  int _selectedTab = 0;
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
  
  Vehicle? _assignedVehicle;
  final VehicleService _vehicleService = VehicleService();
  final EmergencyContactService _emergencyContactService = EmergencyContactService();
  final MonitoringService _monitoringService = MonitoringService();
  Timer? _statsUpdateTimer;
  String? _currentSessionId;
  
  
  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  // Alert Settings
  bool _audioAlertsEnabled = true;
  bool _vibrationAlertsEnabled = true;
  String _sensitivityLevel = 'Medium';

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _updateTimer?.cancel();
    _statsUpdateTimer?.cancel();
    super.dispose();
  }

  String _getWebSocketUrl() {
    // Web: use browser's localhost (or change to your server IP/domain if hosting separately)
    if (kIsWeb) {
      return 'ws://localhost:8000/ws/monitor';
    }

    // Mobile / desktop platforms
    if (Platform.isAndroid) {
      // Android emulator: 10.0.2.2 points to host machine
      // For physical device, replace with your computer's LAN IP (e.g. ws://192.168.1.50:8000/ws/monitor)
      return 'ws://10.0.2.2:8000/ws/monitor';
    }

    // iOS simulator, desktop, etc.
    return 'ws://localhost:8000/ws/monitor';
  }

  void _startMonitoring() async {
    final driverId = widget.user.id;
    if (driverId == null) {
      // Silently ignore if driver ID is missing; you can add a visual indicator in the UI instead of a SnackBar
      return;
    }

    // Start Firebase session
    _currentSessionId =
        await _monitoringService.startMonitoringSession(driverId);

    // Mark monitoring active – this drives stats + live camera feed
    setState(() {
      _isMonitoring = true;
    });

    // Connect to FastAPI WebSocket
    try {
      final wsUrl = _getWebSocketUrl();
      print('🔌 Connecting to FastAPI server at $wsUrl...');
      _channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
      );
      
      print('✅ Connected! Listening for data...');
      
      _channel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message) as Map<String, dynamic>;
            
            if (data.containsKey('error')) {
              print('❌ Error from server: ${data['error']}');
              return;
            }
            
            if (data.containsKey('status')) {
              print('ℹ️ Status: ${data['status']}');
              return;
            }
            
            // Update UI with real stats from your models
            if (mounted) {
              setState(() {
                _alertness =
                    (data['alertness'] as num?)?.toDouble() ?? _alertness;
                _ear = (data['ear'] as num?)?.toDouble() ?? _ear;
                _mar = (data['mar'] as num?)?.toDouble() ?? _mar;
                _eyeClosurePercentage =
                    (data['eyeClosure'] as num?)?.toDouble() ??
                        _eyeClosurePercentage;

                // Decode and store camera frame if available (backend already throttles to 1s)
                if (data.containsKey('frame') && data['frame'] != null) {
                  try {
                    final frameBase64 = data['frame'] as String;
                    _cameraFrameBytes = base64Decode(frameBase64);
                  } catch (e) {
                    print('❌ Error decoding frame: $e');
                  }
                }
              });

              // Previously this showed a SnackBar for every drowsiness alert; removed to avoid persistent bottom popups.
            }
          } catch (e) {
            print('❌ Error parsing message: $e');
          }
        },
        onError: (error) {
          print('❌ WebSocket error: $error');
        },
        onDone: () {
          print('🔌 WebSocket connection closed');
        },
      );
      
    } catch (e) {
      print('❌ Failed to connect to server: $e');
    }
    
    // Update Firebase every second
    _statsUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _monitoringService.updateRealtimeStats(
        driverId: driverId,
        alertness: _alertness,
        ear: _ear,
        mar: _mar,
        eyeClosure: _eyeClosurePercentage,
        drowsinessDetected: _alertness < 70,
      );
    });
  }
  void _stopMonitoring() async {
    final driverId = widget.user.id;

    setState(() {
      _isMonitoring = false;
    });
    
    _updateTimer?.cancel();
    _statsUpdateTimer?.cancel();
    
    // Close WebSocket connection
    _channel?.sink.close();
    _channel = null;
    
    // Clear camera frame
    setState(() {
      _cameraFrameBytes = null;
    });
    
    // End Firebase session
    if (_currentSessionId != null && driverId != null) {
      await _monitoringService.endMonitoringSession(driverId);
      _currentSessionId = null;
    }
  }
 Future<void> _launchPythonMonitor() async {
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
          setState(() {
            _alertness = (data['alertness'] as num?)?.toDouble() ?? _alertness;
            _ear = (data['ear'] as num?)?.toDouble() ?? _ear;
            _mar = (data['mar'] as num?)?.toDouble() ?? _mar;
            _eyeClosurePercentage = (data['eyeClosure'] as num?)?.toDouble() ?? _eyeClosurePercentage;
          });
          
          // Show drowsiness alert
          if (data['isDrowsy'] == true) {
            final reason = data['reason'] as String? ?? 'unknown';
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
        _alertness = 70 + _random.nextDouble() * 25;
        _ear = _random.nextDouble() * 0.3;
        _mar = _random.nextDouble() * 0.3;
        _eyeClosurePercentage = _random.nextDouble() * 30;
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
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.black87),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          'Driver Dashboard',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.driverPrimary,
              child: Text(
                widget.user.firstName[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ) : null,
      body: isMobile
          ? _selectedIndex == 0 ? _buildDashboard() : _buildEmergency()
          : Row(
              children: [
                AppSidebar(
                  role: 'driver',
                  user: widget.user,
                  selectedIndex: _selectedIndex,
                  onMenuItemTap: (index) => setState(() => _selectedIndex = index),
                  menuItems: const [
                    MenuItem(icon: Icons.home_outlined, title: 'Dashboard'),
                    MenuItem(icon: Icons.phone_outlined, title: 'Emergency'),
                  ],
                  accentColor: AppColors.driverPrimary,
                  accentLightColor: AppColors.driverLight,
                ),
                Expanded(
                  child: _selectedIndex == 0 ? _buildDashboard() : _buildEmergency(),
                ),
              ],
            ),
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: AppSidebar(
          role: 'driver',
          user: widget.user,
          selectedIndex: _selectedIndex,
          onMenuItemTap: (index) {
            setState(() => _selectedIndex = index);
            Navigator.pop(context);
          },
          menuItems: const [
            MenuItem(icon: Icons.home_outlined, title: 'Dashboard'),
            MenuItem(icon: Icons.phone_outlined, title: 'Emergency'),
          ],
          accentColor: AppColors.driverPrimary,
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



  Widget _buildDashboard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = MediaQuery.of(context).size.width < 768;
        final isTablet = MediaQuery.of(context).size.width < 1024 && !isMobile;

        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : isTablet ? 24.0 : 40.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMobile) ...[
                          Text(
                            'Driver Dashboard',
                            style: TextStyle(
                              fontSize: isMobile ? 24 : isTablet ? 28 : 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Real-time drowsiness monitoring',
                            style: TextStyle(
                              fontSize: isMobile ? 13 : isTablet ? 14 : 16,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                  ],
                ),
                    SizedBox(
                      width: isMobile ? double.infinity : null,
                      child: ElevatedButton.icon(
                        onPressed: _isMonitoring
                            ? _stopMonitoring
                            : _startMonitoring,
                        icon: Icon(
                            _isMonitoring ? Icons.pause : Icons.visibility),
                        label: Text(_isMonitoring
                            ? 'Stop Monitoring'
                            : 'Start Monitoring'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.driverPrimary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 20 : 24,
                              vertical: isMobile ? 14 : 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: isMobile ? double.infinity : null,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DriverHistoryScreen(
                                driverId: widget.user.id,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.history),
                        label: const Text('View History'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.driverPrimary,
                          side: BorderSide(color: AppColors.driverPrimary),
                          padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 20 : 24,
                              vertical: isMobile ? 14 : 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                const SizedBox(height: 32),
                StreamBuilder<Vehicle?>(
                  stream: _vehicleService.getVehicleByDriverStream(widget.user.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text('Error loading vehicle: ${snapshot.error}');
                    }
                    
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final assignedVehicle = snapshot.data;
                    
                    // Update local state for other widgets if needed
                    if (assignedVehicle != null && _assignedVehicle?.id != assignedVehicle.id) {
                       WidgetsBinding.instance.addPostFrameCallback((_) {
                         if (mounted) setState(() => _assignedVehicle = assignedVehicle);
                       });
                    } else if (assignedVehicle == null && _assignedVehicle != null) {
                       WidgetsBinding.instance.addPostFrameCallback((_) {
                         if (mounted) setState(() => _assignedVehicle = null);
                       });
                    }

                    if (assignedVehicle == null) {
                      return const SizedBox.shrink(); // No vehicle assigned
                    }

                    final isMobile = MediaQuery.of(context).size.width < 768;
                    return Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(isMobile ? 16 : 24),
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
                                  Icon(Icons.directions_car, color: AppColors.driverPrimary, size: isMobile ? 20 : 24),
                                  SizedBox(width: isMobile ? 8 : 12),
                                  Expanded(
                                    child: Text(
                                      'Assigned Vehicle: ${assignedVehicle.make} ${assignedVehicle.model} (${assignedVehicle.year})',
                                      style: TextStyle(
                                        fontSize: isMobile ? 14 : 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isMobile ? 8 : 12),
                              _buildVehicleInfoChip(Icons.confirmation_number, assignedVehicle.licensePlate, isMobile),
                            ],
                          ),
                        ),
                        SizedBox(height: isMobile ? 24 : 32),
                      ],
                    );
                  },
                ),
                isMobile
                    ? Column(
                        children: [
                          _buildAlertCard(isMobile),
                          SizedBox(height: isMobile ? 16 : 20),
                          _buildEARMARCard(isMobile),
                          SizedBox(height: isMobile ? 16 : 20),
                          _buildSystemStatusCard(isMobile),
                        ],
                      )
                    : isTablet
                        ? Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _buildAlertCard(isMobile)),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildEARMARCard(isMobile)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildSystemStatusCard(isMobile),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: _buildAlertCard(isMobile)),
                              const SizedBox(width: 20),
                              Expanded(child: _buildEARMARCard(isMobile)),
                              const SizedBox(width: 20),
                              Expanded(child: _buildSystemStatusCard(isMobile)),
                            ],
                          ),
                SizedBox(height: isMobile ? 24 : 32),
                _buildTabBar(isMobile),
                SizedBox(height: isMobile ? 24 : 32),
                _buildTabContent(isMobile),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlertCard([bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 28),
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
          SizedBox(height: isMobile ? 16 : 24),
          Text(
            '${_alertness.toInt()}%',
            style: TextStyle(
              fontSize: isMobile ? 42 : 56,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Good',
              style: TextStyle(
                color: Color(0xFFFFA726),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: _alertness / 100,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.driverPrimary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEARMARCard([bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 28),
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
          SizedBox(height: isMobile ? 16 : 24),
          Text(
            'EAR ${_ear.toStringAsFixed(2)} • MAR ${_mar.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isMobile ? 18 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Live from camera',
            style: TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusCard([bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 28),
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
              Flexible(
                child: Text(
                  'System Status',
                  style: TextStyle(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              Icon(Icons.shield_outlined, color: Colors.grey[400], size: isMobile ? 18 : 20),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 24),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'All Systems Active',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.battery_full, color: Colors.grey[600], size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Battery: 87%',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
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
              bottom: BorderSide(color: AppColors.driverPrimary, width: 2),
            )
                : null,
            boxShadow: isActive ? [
              BoxShadow(
                color: AppColors.driverPrimary.withValues(alpha: 0.2),
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
              color: isActive ? AppColors.driverPrimary : Colors.black54,
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
            'Customize your drowsiness detection alerts',
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
            actionWidget: Text(
              'Enabled',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Divider(height: 48),
          _buildSettingRow(
            'Vibration Alerts',
            'Device vibration for alerts',
            _vibrationAlertsEnabled,
                (value) => setState(() => _vibrationAlertsEnabled = value),
            actionWidget: Text(
              'Enabled',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Divider(height: 48),
          _buildSettingRowWithButton(
            'Emergency Contacts',
            'Auto-notify contacts on critical alerts',
            'Configure',
                () {
              // Handle configure action
            },
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        if (actionWidget != null) actionWidget,
      ],
    );
  }

  Widget _buildSettingRowWithButton(String title,
      String subtitle,
      String buttonText,
      VoidCallback onPressed,) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
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

  void _showSensitivityDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Sensitivity Level'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile(
                  title: const Text('Low'),
                  value: 'Low',
                  groupValue: _sensitivityLevel,
                  onChanged: (value) {
                    setState(() => _sensitivityLevel = value.toString());
                    Navigator.pop(context);
                  },
                ),
                RadioListTile(
                  title: const Text('Medium'),
                  value: 'Medium',
                  groupValue: _sensitivityLevel,
                  onChanged: (value) {
                    setState(() => _sensitivityLevel = value.toString());
                    Navigator.pop(context);
                  },
                ),
                RadioListTile(
                  title: const Text('High'),
                  value: 'High',
                  groupValue: _sensitivityLevel,
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
                child: _cameraFrameBytes != null && (_isMonitoring || _isCameraTesting)
                    ? Image.memory(
                        _cameraFrameBytes!,
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
                      )
                    : Center(
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
                      ),
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
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _cameraFrameBytes != null && _isMonitoring
                    ? Image.memory(
                        _cameraFrameBytes!,
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
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isMonitoring ? Icons.videocam : Icons.videocam_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isMonitoring
                                  ? 'Waiting for camera feed...'
                                  : 'Camera feed will appear here',
                              style: TextStyle(color: Colors.grey[400], fontSize: 14),
                            ),
                          ],
                        ),
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
              border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
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
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Add this method to your dashboard state class
  Widget _buildEmergency() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emergency Contacts',
              style: TextStyle(
                fontSize: isMobile ? 24 : 36,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: isMobile ? 6 : 8),
            Text(
              'Quick access to emergency services and contacts',
              style: TextStyle(
                fontSize: isMobile ? 13 : 16,
                color: Colors.black54,
              ),
            ),
            SizedBox(height: isMobile ? 24 : 32),

            // Emergency Services Grid
            Wrap(
              spacing: isMobile ? 12 : 20,
              runSpacing: isMobile ? 12 : 20,
              children: [
                SizedBox(
                  width: isMobile ? double.infinity : 280,
                  child: _buildEmergencyServiceCard(
                    'Police',
                    '15',
                    Icons.local_police,
                    const Color(0xFF2196F3),
                    const Color(0xFFE3F2FD),
                    isMobile,
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 280,
                  child: _buildEmergencyServiceCard(
                    'Ambulance',
                    '1122',
                    Icons.local_hospital,
                    Colors.red,
                    const Color(0xFFFFEBEE),
                    isMobile,
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 280,
                  child: _buildEmergencyServiceCard(
                    'Fire Department',
                    '16',
                    Icons.local_fire_department,
                    const Color(0xFFFF6F00),
                    const Color(0xFFFFF3E0),
                    isMobile,
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 280,
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
            SizedBox(height: isMobile ? 24 : 32),

            // Emergency Contacts Table
            _buildEmergencyContactsTable(isMobile),
          ],
        ),
      ),
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
              onPressed: () {
                final msg = number == '911' ? 'Calling emergency services...' : 'Calling $number...';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: relationshipController,
                  decoration: const InputDecoration(
                    labelText: 'Relationship *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
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
                const Text('Contact Methods:', style: TextStyle(fontWeight: FontWeight.bold)),
                CheckboxListTile(
                  title: const Text('Phone Call'),
                  value: methods.contains('call'),
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
                  title: const Text('SMS'),
                  value: methods.contains('sms'),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        methods.add('sms');
                      } else {
                        methods.remove('sms');
                      }
                    });
                  },
                ),
                CheckboxListTile(
                  title: const Text('Email'),
                  value: methods.contains('email'),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty || 
                    relationshipController.text.isEmpty || 
                    phoneController.text.isEmpty) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    const SnackBar(content: Text('Please fill in all required fields')),
                  );
                  return;
                }
                
                try {
                  await _emergencyContactService.addEmergencyContact(
                    userId: widget.user.id,
                    userRole: 'driver',
                    contactData: {
                      'name': nameController.text,
                      'relationship': relationshipController.text,
                      'phone': phoneController.text,
                      'email': emailController.text,
                      'priority': priority,
                      'methods': methods,
                      'enabled': true,
                    },
                  );
                  
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(content: Text('${nameController.text} added to emergency contacts')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(content: Text('Error adding contact: $e')),
                    );
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: relationshipController,
                  decoration: const InputDecoration(
                    labelText: 'Relationship *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
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
                const Text('Contact Methods:', style: TextStyle(fontWeight: FontWeight.bold)),
                CheckboxListTile(
                  title: const Text('Phone Call'),
                  value: methods.contains('call'),
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
                  title: const Text('SMS'),
                  value: methods.contains('sms'),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        methods.add('sms');
                      } else {
                        methods.remove('sms');
                      }
                    });
                  },
                ),
                CheckboxListTile(
                  title: const Text('Email'),
                  value: methods.contains('email'),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty || 
                    relationshipController.text.isEmpty || 
                    phoneController.text.isEmpty) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    const SnackBar(content: Text('Please fill in all required fields')),
                  );
                  return;
                }
                
                try {
                  await _emergencyContactService.updateEmergencyContact(
                    contactId: contact.id,
                    contactData: {
                      'name': nameController.text,
                      'relationship': relationshipController.text,
                      'phone': phoneController.text,
                      'email': emailController.text,
                      'priority': priority,
                      'methods': methods,
                      'enabled': contact.enabled,
                    },
                  );
                  
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(content: Text('${nameController.text} updated successfully')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(content: Text('Error updating contact: $e')),
                    );
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
            child: const Center(child: CircularProgressIndicator()),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
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
                  ElevatedButton.icon(
                    onPressed: () {
                      _showAddContactDialog();
                    },
                    icon: Icon(Icons.add, size: isMobile ? 16 : 18),
                    label: Text('Add Contact', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 12 : 20,
                          vertical: isMobile ? 10 : 12),
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
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
                  : Table(
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
            Icon(Icons.phone, size: isMobile ? 16 : 18, color: Colors.green[600]),
          if (methods.contains('call')) SizedBox(width: isMobile ? 4 : 6),
          if (methods.contains('sms'))
            Icon(Icons.message, size: isMobile ? 16 : 18, color: Colors.blue[600]),
          if (methods.contains('sms')) SizedBox(width: isMobile ? 4 : 6),
          if (methods.contains('email'))
            Icon(Icons.email, size: isMobile ? 16 : 18, color: Colors.grey[600]),
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
                SnackBar(content: Text('Error updating contact: $e')),
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
                      SnackBar(content: Text('${contact.name} removed')),
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
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 12,
          vertical: isMobile ? 5 : 6),
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
}