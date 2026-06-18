import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../models/vehicle.dart';
import '../services/vehicle_service.dart';
import '../services/monitoring_service.dart';
import '../services/owner_vehicle_submission_service.dart';
import '../services/firebase_auth_service.dart';
import '../constants/app_colors.dart';
import '../widgets/shared/app_sidebar.dart';
import '../widgets/shared/live_map.dart';
import '../screens/notifications_inbox_screen.dart';
import '../services/user_notifications_service.dart';
import '../screens/driver_documents_gate_screen.dart';
import '../utils/sign_out_flow.dart';
import '../widgets/email_verified_guard.dart';
import '../widgets/mobile_drawer_menu_button.dart';
import '../widgets/emergency_contacts_panel.dart';
import '../constants/vehicle_catalog.dart';
import '../widgets/owner_form_dialog_ui.dart';
import '../widgets/owner_add_vehicle_dialog.dart';
import '../utils/dashboard_responsive.dart';
import '../widgets/shared/app_settings_page.dart';

/// Matches driver realtime monitoring thresholds (alertness / drowsiness flag).
bool ownerLiveMetricsCritical(Map<String, dynamic> stats) {
  final alertness = stats['alertness'];
  final drowsinessDetected = stats['drowsinessDetected'] == true;
  if (alertness == null) return false;
  final alertnessValue = (alertness as num).toDouble();
  return drowsinessDetected || alertnessValue < 76;
}

class OwnerDashboard extends StatefulWidget {
  final User user;

  const OwnerDashboard({Key? key, required this.user}) : super(key: key);

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> with TickerProviderStateMixin {
  final VehicleService _vehicleService = VehicleService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OwnerVehicleSubmissionService _ownerVehicleSubmissionService = OwnerVehicleSubmissionService();
  final MonitoringService _monitoringService = MonitoringService();

  int _selectedIndex = 0;
  bool _isLoading = false;
  late User _currentUser;
  DateTime? _lastBackPress;

  List<MenuItem> get _sidebarMenuItems => [
        const MenuItem(
          section: 'Fleet',
          icon: Icons.home_outlined,
          title: 'Overview',
        ),
        const MenuItem(
          section: 'Fleet',
          icon: Icons.directions_car_outlined,
          title: 'Vehicle Management',
        ),
        const MenuItem(
          section: 'Fleet',
          icon: Icons.map_outlined,
          title: 'Live Map',
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
        return _buildOwnerOverviewPage();
      case 1:
        return _buildOwnerFleetPage();
      case 2:
        return _buildOwnerLiveMapPage();
      case 3:
        return _buildEmergency();
      case 4:
        return _buildOwnerNotificationsPage();
      case 5:
        return _buildOwnerSettingsPage();
      default:
        return _buildOwnerOverviewPage();
    }
  }

  String get _currentPageTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Overview';
      case 1:
        return 'Vehicle Management';
      case 2:
        return 'Live Map';
      case 3:
        return 'Emergency';
      case 4:
        return 'Notifications';
      case 5:
        return 'Settings';
      default:
        return 'Overview';
    }
  }

  String get _currentPageSubtitle {
    switch (_selectedIndex) {
      case 0:
      return 'Monitor and Manage Your Vehicle Fleet';
      case 1:
      return 'Search and Manage Your Vehicles';
      case 2:
        return 'Track Drivers Assigned To Your Vehicles';
      case 3:
        return 'Quick Access To Emergency Services and Contacts';
      case 4:
        return 'Alerts and System Messages';
      case 5:
        return 'Account, Security, and Alert Preferences';
      default:
        return 'Monitor and Manage Your Vehicle Fleet';
    }
  }

  Widget _buildOwnerNotificationsPage() {
    return _ownerPageShell(
      title: 'Notifications',
      subtitle: 'Alerts and system messages',
      child: NotificationsInboxScreen(user: _currentUser, embedded: true),
    );
  }

  Widget _buildOwnerSettingsPage() {
    return AppSettingsPage(
      user: _currentUser,
      sessionRole: 'owner',
      onUserUpdated: (user) => setState(() => _currentUser = user),
    );
  }

  Widget _ownerPageShell({
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

  Widget _buildOwnerFleetPage() {
    final isMobile = DashboardLayout.isMobile(context);
    final fleetLayout = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: _buildFleetOverview(),
          ),
        ),
        _buildFleetBottomActionBar(isMobile),
      ],
    );
    if (isMobile) {
      return Padding(
        padding: DashboardLayout.pagePadding(context).copyWith(bottom: 8),
        child: fleetLayout,
      );
    }
    return _ownerPageShell(
      title: 'Fleet Management',
      subtitle: 'View and Manage All Registered Vehicles',
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: fleetLayout,
      ),
    );
  }

  Widget _buildOwnerLiveMapPage() {
    return _ownerPageShell(
      title: 'Live Map',
      subtitle: 'Track drivers assigned to your vehicles',
      child: _buildOwnerLiveMapSection(),
    );
  }
  String _statusFilter = 'All Status';
  String _typeFilter = 'All Types';
  final TextEditingController _vehicleSearchController = TextEditingController();
  String _vehicleSearchQuery = '';


  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _isLoading = false;

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _vehicleSearchController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  bool _vehicleMatchesSearch(Vehicle vehicle, String query) {
    if (query.isEmpty) return true;
    final plate = vehicle.licensePlate.toLowerCase();
    final makeModel = '${vehicle.make} ${vehicle.model}'.toLowerCase();
    final driver = (vehicle.driverName ?? '').toLowerCase();
    return plate.contains(query) ||
        makeModel.contains(query) ||
        driver.contains(query) ||
        vehicle.type.toLowerCase().contains(query);
  }

  Widget _buildOwnerSectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    bool isMobile = false,
    String? subtitle,
    Widget? trailing,
  }) =>
      _buildFleetSectionCard(
        icon: icon,
        title: title,
        child: child,
        isMobile: isMobile,
        subtitle: subtitle,
        trailing: trailing,
      );

  Widget _buildFleetSectionCard({
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

  Widget _buildFleetSearchField(bool isMobile) {
    return TextField(
      controller: _vehicleSearchController,
      textCapitalization: TextCapitalization.characters,
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        hintText: 'Plate, Make, Model, or Driver',
        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
        suffixIcon: _vehicleSearchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 20, color: AppColors.primary),
                onPressed: () {
                  _vehicleSearchController.clear();
                  setState(() => _vehicleSearchQuery = '');
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        filled: true,
        fillColor: AppColors.background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      onChanged: (v) => setState(() => _vehicleSearchQuery = v),
    );
  }

  Future<void> _dialPhoneNumber(String rawPhone) async {
    final trimmed = rawPhone.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No phone number available')),
        );
      }
      return;
    }
    final sanitized = trimmed.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final uri = Uri(scheme: 'tel', path: sanitized);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot make phone call on this device')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start call: $e')),
        );
      }
    }
  }

  Future<bool> _ensureGalleryPermission() async {
    if (kIsWeb) return true;

    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.android) {
      final photos = await Permission.photos.request();
      final storage = await Permission.storage.request();
      if (photos.isGranted || storage.isGranted) return true;
      return false;
    }

    if (platform == TargetPlatform.iOS) {
      final photos = await Permission.photos.request();
      return photos.isGranted;
    }

    return true;
  }

  Future<Uint8List?> _pickImageBytes() async {
    final ok = await _ensureGalleryPermission();
    if (!ok) return null;

    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return null;
    return x.readAsBytes();
  }

  Future<VehicleBookPdfPick?> _pickVehicleBookPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final name = file.name.trim();
    if (!name.toLowerCase().endsWith('.pdf')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only PDF files are allowed for the vehicle ID-card/book'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return null;
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read the PDF file'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return null;
    }

    if (bytes.length >= 4 &&
        !(bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected file is not a valid PDF'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return null;
    }

    return VehicleBookPdfPick(bytes: bytes, fileName: name);
  }

  // Build a map of driverId -> hasActiveSession for all vehicles
  Future<Map<String, bool>> _buildActiveSessionMap(List<Vehicle> vehicles) async {
    final Map<String, bool> activeSessionMap = {};
    
    // Get unique driver IDs
    final driverIds = vehicles
        .where((v) => v.assignedDriverId != null && v.assignedDriverId!.isNotEmpty)
        .map((v) => v.assignedDriverId!)
        .toSet()
        .toList();
    
    // Check active session for each driver
    for (final driverId in driverIds) {
      try {
        activeSessionMap[driverId] = await _monitoringService.hasActiveSession(driverId);
      } catch (e) {
        print('Error checking active session for driver $driverId: $e');
        activeSessionMap[driverId] = false;
      }
    }
    
    return activeSessionMap;
  }

  Future<Map<String, bool>> _getActiveSessionMapFuture(List<Vehicle> vehicles) {
    return _buildActiveSessionMap(vehicles);
  }

  Future<void> _showAddVehicleDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => OwnerAddVehicleDialog(
        user: widget.user,
        vehicleService: _vehicleService,
        submissionService: _ownerVehicleSubmissionService,
        pickVehicleBookPdf: _pickVehicleBookPdf,
      ),
    );
  }

  void _showDriverRegistrationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Driver Registration Required'),
        content: const Text(
            'You need to register as a driver before you can be assigned to a vehicle. '
                'Would you like to register as a driver now?'
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Vehicle added to your fleet. It will be auto-assigned when a driver signs up.'),
                  backgroundColor: AppColors.success,
                  duration: Duration(seconds: 4),
                ),
              );

            },
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final authService = FirebaseAuthService();
                await authService.addDriverRoleForOwner(widget.user.id);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Driver access enabled. Complete document verification to continue.'),
                    backgroundColor: AppColors.success,
                  ),
                );

                final upgradedUser = User(
                  id: widget.user.id,
                  firstName: widget.user.firstName,
                  lastName: widget.user.lastName,
                  email: widget.user.email,
                  phone: widget.user.phone,
                  role: 'driver',
                  roles: {
                    ...(widget.user.roles ?? <String>[]),
                    'owner',
                    'driver',
                  }.toList(),
                );

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DriverDocumentsGateScreen(user: upgradedUser),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceFirst('Exception: ', '')),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Register as Driver'),
          ),
        ],
      ),
    );
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
            role: 'owner',
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
          role: 'owner',
          user: widget.user is User ? widget.user : null,
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

  Widget _buildOwnerOverviewPage() {
    final isMobile = DashboardLayout.isMobile(context);
    return _ownerPageShell(
      title: 'Overview',
      subtitle: 'Monitor and Manage Your Vehicle Fleet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStaggeredItem(
            _buildOwnerSectionCard(
              isMobile: isMobile,
              icon: Icons.dashboard_outlined,
              title: 'Fleet Overview',
              subtitle: 'Key Metrics For Your Registered Vehicles And Drivers',
              child: StreamBuilder<List<Vehicle>>(
                  stream: _vehicleService.getVehiclesByOwnerStream(widget.user.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      );
                    }
                    if (snapshot.hasError) {
                      return Text('Error loading fleet: ${snapshot.error}');
                    }
                    final vehicles = snapshot.data ?? [];
                    final isMobileInner = DashboardLayout.isMobile(context);
                    final isTablet = DashboardLayout.isTablet(context);

                    return isMobileInner
                          ? Column(
                        children: [
                          _buildStatCard(
                            'Total Vehicles',
                            vehicles.length.toString(),
                            'Registered in System',
                            Icons.directions_car_outlined,
                            AppColors.primary,
                            isMobile,
                            () => _showOwnerStatDetails(
                              'All Vehicles',
                              vehicles.map(_buildOwnerVehicleSummaryTile).toList(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _OwnerDashboardActiveDriversCard(
                            vehicles: vehicles,
                            monitoringService: _monitoringService,
                            isMobile: isMobile,
                            builder: (context, activeDriverCount, activeDriverTiles) => _buildStatCard(
                              'Active Drivers',
                              activeDriverCount.toString(),
                              'Currently Driving',
                              Icons.people_outline,
                              AppColors.success,
                              isMobile,
                              () => _showOwnerStatDetails('Active Drivers', activeDriverTiles),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _OwnerDashboardCriticalAlertsCard(
                            vehicles: vehicles,
                            isMobile: isMobile,
                            monitoringService: _monitoringService,
                            builder: (context, criticalVehicles) => _buildStatCard(
                              'Critical Alerts',
                              criticalVehicles.length.toString(),
                              'Requires Attention',
                              Icons.warning_amber_rounded,
                              AppColors.danger,
                              isMobile,
                              () => _showOwnerStatDetails(
                                'Critical Alerts',
                                criticalVehicles
                                    .map(
                                      (v) => ListTile(
                                        dense: true,
                                        title: Text('${v.licensePlate} · ${v.make} ${v.model}'),
                                        subtitle: Text('Driver: ${v.driverName ?? "Unassigned"}'),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _OwnerDashboardLiveSafetyScoreCard(
                            vehicles: vehicles,
                            isMobile: isMobile,
                            monitoringService: _monitoringService,
                            builder: (context, scoreText, color, details) => _buildStatCard(
                              'Safety Score',
                              scoreText,
                              'Live Monitoring Score',
                              Icons.shield_outlined,
                              color,
                              isMobile,
                              () => _showOwnerStatDetails('Vehicle Safety Scores', details),
                            ),
                          ),
                        ],
                      )
                          : isTablet
                          ? Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildStatCard(
                                'Total Vehicles',
                                vehicles.length.toString(),
                                'Registered in System',
                                Icons.directions_car_outlined,
                                AppColors.primary,
                                isMobile,
                                () => _showOwnerStatDetails(
                                  'All Vehicles',
                                  vehicles.map(_buildOwnerVehicleSummaryTile).toList(),
                                ),
                              )),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _OwnerDashboardActiveDriversCard(
                                  vehicles: vehicles,
                                  monitoringService: _monitoringService,
                                  isMobile: isMobile,
                                  builder: (context, activeDriverCount, activeDriverTiles) => _buildStatCard(
                                    'Active Drivers',
                                    activeDriverCount.toString(),
                                    'Currently Driving',
                                    Icons.people_outline,
                                    AppColors.success,
                                    isMobile,
                                    () => _showOwnerStatDetails('Active Drivers', activeDriverTiles),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _OwnerDashboardCriticalAlertsCard(
                                  vehicles: vehicles,
                                  isMobile: isMobile,
                                  monitoringService: _monitoringService,
                                  builder: (context, criticalVehicles) => _buildStatCard(
                                    'Critical Alerts',
                                    criticalVehicles.length.toString(),
                                    'Requires attention',
                                    Icons.warning_amber_rounded,
                                    AppColors.danger,
                                    isMobile,
                                    () => _showOwnerStatDetails(
                                      'Critical Alerts',
                                      criticalVehicles
                                          .map(
                                            (v) => ListTile(
                                              dense: true,
                                              title: Text('${v.licensePlate} · ${v.make} ${v.model}'),
                                              subtitle: Text('Driver: ${v.driverName ?? "Unassigned"}'),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _OwnerDashboardLiveSafetyScoreCard(
                                  vehicles: vehicles,
                                  isMobile: isMobile,
                                  monitoringService: _monitoringService,
                                  builder: (context, scoreText, color, details) => _buildStatCard(
                                    'Safety Score',
                                    scoreText,
                                    'Live monitoring score',
                                    Icons.shield_outlined,
                                    color,
                                    isMobile,
                                    () => _showOwnerStatDetails('Vehicle Safety Scores', details),
                                  ),
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
                              Expanded(child: _buildStatCard(
                                'Total Vehicles',
                                vehicles.length.toString(),
                                'Registered in System',
                                Icons.directions_car_outlined,
                                AppColors.primary,
                                isMobile,
                                () => _showOwnerStatDetails(
                                  'All Vehicles',
                                  vehicles.map(_buildOwnerVehicleSummaryTile).toList(),
                                ),
                              )),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _OwnerDashboardActiveDriversCard(
                                  vehicles: vehicles,
                                  monitoringService: _monitoringService,
                                  isMobile: isMobile,
                                  builder: (context, activeDriverCount, activeDriverTiles) => _buildStatCard(
                                    'Active Drivers',
                                    activeDriverCount.toString(),
                                    'Currently Driving',
                                    Icons.people_outline,
                                    AppColors.success,
                                    isMobile,
                                    () => _showOwnerStatDetails('Active Drivers', activeDriverTiles),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _OwnerDashboardCriticalAlertsCard(
                                  vehicles: vehicles,
                                  isMobile: isMobile,
                                  monitoringService: _monitoringService,
                                  builder: (context, criticalVehicles) => _buildStatCard(
                                    'Critical Alerts',
                                    criticalVehicles.length.toString(),
                                    'Requires attention',
                                    Icons.warning_amber_rounded,
                                    AppColors.danger,
                                    isMobile,
                                    () => _showOwnerStatDetails(
                                      'Critical Alerts',
                                      criticalVehicles
                                          .map(
                                            (v) => ListTile(
                                              dense: true,
                                              title: Text('${v.licensePlate} · ${v.make} ${v.model}'),
                                              subtitle: Text('Driver: ${v.driverName ?? "Unassigned"}'),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _OwnerDashboardLiveSafetyScoreCard(
                                  vehicles: vehicles,
                                  isMobile: isMobile,
                                  monitoringService: _monitoringService,
                                  builder: (context, scoreText, color, details) => _buildStatCard(
                                    'Safety Score',
                                    scoreText,
                                    'Live monitoring score',
                                    Icons.shield_outlined,
                                    color,
                                    isMobile,
                                    () => _showOwnerStatDetails('Vehicle Safety Scores', details),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                  },
                ),
            ),
            1,
          ),
        ],
      ),
    );
  }

  /// Builds the LiveMap section filtered to only show drivers assigned
  /// to this owner's vehicles.
  Widget _buildOwnerLiveMapSection() {
    final isMobile = DashboardLayout.isMobile(context);
    return StreamBuilder<List<Vehicle>>(
      stream: _vehicleService.getVehiclesByOwnerStream(widget.user.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }
        final vehicles = snapshot.data ?? [];
        final driverIds = vehicles
            .where((v) => v.assignedDriverId != null && v.assignedDriverId!.isNotEmpty)
            .map((v) => v.assignedDriverId!)
            .toSet()
            .toList();

        if (driverIds.isEmpty) {
          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: isMobile ? 28 : 40, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.map_outlined, size: isMobile ? 48 : 56, color: Colors.grey[400]),
                const SizedBox(height: 12),
                const Text(
                  'No assigned drivers on map',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Assign drivers to your vehicles to see their live locations',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return SizedBox(
          height: DashboardLayout.liveMapHeight(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LiveMap(
              filterDriverIds: driverIds,
              showHeader: true,
              height: DashboardLayout.liveMapHeight(context),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaggeredItem(Widget child, int index) {
    return AnimatedBuilder(
      animation: _slideController,
      builder: (context, _) {
        final double slideValue = Curves.easeOutQuad.transform(_slideController.value);
        final double fadeValue = Curves.easeOut.transform(_fadeController.value);
        final double itemDelay = index * 0.1;
        final double itemSlide = (slideValue - itemDelay).clamp(0.0, 1.0);
        final double itemFade = (fadeValue - itemDelay).clamp(0.0, 1.0);

        return Opacity(
          opacity: itemFade,
          child: Transform.translate(
            offset: Offset(0, 50 * (1 - itemSlide)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, IconData icon, Color color, [bool isMobile = false, VoidCallback? onTap]) {
    final card = Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: isMobile ? 26 : 30),
          ),
          SizedBox(width: isMobile ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isMobile ? 30 : 34,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: isMobile ? 6 : 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isMobile ? 15 : 16,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: isMobile ? 2 : 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.touch_app_outlined, size: 14, color: AppColors.primary.withValues(alpha: 0.9)),
                      const SizedBox(width: 6),
                      Text(
                        'Tap for Details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded, color: AppColors.primary.withValues(alpha: 0.7), size: isMobile ? 24 : 28),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: AppColors.primary.withValues(alpha: 0.12),
        highlightColor: AppColors.primaryLight.withValues(alpha: 0.5),
        child: card,
      ),
    );
  }

  ButtonStyle get _fleetClearButtonStyle => TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  void _showFleetSearchBottomSheet(bool isMobile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OwnerFormDialogUi.bottomSheetHeader(
              title: 'Search Vehicle',
              subtitle: 'Find by License Plate, Make, Model, or Driver\'s Name',
              icon: Icons.search,
              onClose: () => Navigator.pop(sheetContext),
            ),
            const SizedBox(height: 16),
            _buildFleetSearchField(isMobile),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(sheetContext),
              style: OwnerFormDialogUi.primaryButtonStyle.copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 48)),
              ),
              child: const Text('Apply Search'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFleetFilterBottomSheet(bool isMobile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OwnerFormDialogUi.bottomSheetHeader(
              title: 'Filter Vehicles',
              subtitle: 'Narrow Vehicles by Live Status and Type',
              icon: Icons.tune,
              onClose: () => Navigator.pop(sheetContext),
            ),
            const SizedBox(height: 16),
            _buildFleetFiltersContent(isMobile),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _statusFilter = 'All Status';
                        _typeFilter = 'All Types';
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: OwnerFormDialogUi.primaryButtonStyle,
                    child: const Text('Apply Filters'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFleetBottomActionBar(bool isMobile) {
    final searchActive = _vehicleSearchQuery.trim().isNotEmpty;
    final filterActive = _statusFilter != 'All Status' || _typeFilter != 'All Types';

    Widget actionTile({
      required String label,
      required IconData icon,
      required bool active,
      required VoidCallback onTap,
    }) {
      return Material(
        color: active ? AppColors.primaryLight : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? AppColors.primary : AppColors.border,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: active,
                  smallSize: 8,
                  backgroundColor: AppColors.primary,
                  child: Icon(icon, size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: active ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      elevation: 8,
      color: Colors.white,
      shadowColor: AppColors.primary.withValues(alpha: 0.15),
      borderRadius: isMobile ? null : const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.primary.withValues(alpha: 0.2), width: 1.5),
            ),
          ),
          padding: EdgeInsets.fromLTRB(isMobile ? 14 : 18, 12, isMobile ? 14 : 18, isMobile ? 10 : 14),
          child: Row(
            children: [
              Expanded(
                child: actionTile(
                  label: 'Search',
                  icon: Icons.search,
                  active: searchActive,
                  onTap: () => _showFleetSearchBottomSheet(isMobile),
                ),
              ),
              SizedBox(width: isMobile ? 12 : 14),
              Expanded(
                child: actionTile(
                  label: 'Filter',
                  icon: Icons.tune,
                  active: filterActive,
                  onTap: () => _showFleetFilterBottomSheet(isMobile),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFleetAddVehicleButton(bool isMobile) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showAddVehicleDialog,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Register New Vehicle'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: isMobile ? 14 : 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  String _ownerOperationalStatusLabel(bool hasActiveSession, Map<String, dynamic>? stats) {
    if (!hasActiveSession) return 'Offline';
    if (stats == null || stats.isEmpty) return 'Active';
    if (ownerLiveMetricsCritical(stats)) return 'Critical';
    return 'Active';
  }

  Widget _vehicleDetailStatusTile(Vehicle vehicle) {
    final driverId = vehicle.assignedDriverId;
    if (driverId == null || driverId.isEmpty) {
      return const ListTile(title: Text('Status'), subtitle: Text('Offline'));
    }
    return StreamBuilder<bool>(
      stream: _monitoringService.watchHasActiveMonitoringSession(driverId),
      builder: (context, sessionSnap) {
        final active = sessionSnap.data == true;
        return StreamBuilder<Map<String, dynamic>>(
          stream: _monitoringService.getCurrentStats(driverId),
          builder: (context, statsSnap) {
            final label = _ownerOperationalStatusLabel(active, statsSnap.data);
            return ListTile(title: const Text('Status'), subtitle: Text(label));
          },
        );
      },
    );
  }

  Future<void> _showOwnerStatDetails(String title, List<Widget> children) async {
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.78;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 820, maxHeight: maxDialogHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(
                    bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.15)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.insights_outlined, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  children: children
                      .map(
                        (child) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
                          ),
                          child: child,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerVehicleSummaryTile(Vehicle vehicle) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(VehicleCatalog.iconForType(vehicle.type), color: AppColors.primary, size: 20),
      ),
      title: Text(
        '${vehicle.licensePlate} · ${vehicle.make} ${vehicle.model}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (vehicle.assignedDriverId == null || vehicle.assignedDriverId!.isEmpty)
              const Text('Status: Offline')
            else
              StreamBuilder<bool>(
                stream: _monitoringService.watchHasActiveMonitoringSession(vehicle.assignedDriverId!),
                builder: (context, sessionSnap) {
                  final active = sessionSnap.data == true;
                  return StreamBuilder<Map<String, dynamic>>(
                    stream: _monitoringService.getCurrentStats(vehicle.assignedDriverId!),
                    builder: (context, statsSnap) {
                      return Text('Status: ${_ownerOperationalStatusLabel(active, statsSnap.data)}');
                    },
                  );
                },
              ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red, size: isMobile ? 18 : 20),
              tooltip: 'Delete',
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: () => _confirmDeleteVehicle(vehicle),
            ),
          ],
        ),
      ),
    );
  }

  Color _fleetStatusColorForOption(String option) {
    switch (option.toLowerCase()) {
      case 'active':
        return AppColors.success;
      case 'critical':
        return AppColors.danger;
      case 'offline':
        return Colors.grey;
      default:
        return AppColors.primary;
    }
  }

  Widget _buildFleetStatusFilterDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    Widget statusRow(String option) {
      return Row(
        children: [
          Icon(Icons.circle, size: 14, color: _fleetStatusColorForOption(option)),
          const SizedBox(width: 10),
          Expanded(child: Text(option)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
              selectedItemBuilder: (context) =>
                  options.map((o) => Align(alignment: Alignment.centerLeft, child: statusRow(o))).toList(),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: statusRow(o)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFleetFilterDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    IconData Function(String option)? iconForOption,
    IconData icon = Icons.category_outlined,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
              items: options
                  .map(
                    (o) => DropdownMenuItem(
                      value: o,
                      child: VehicleCatalog.dropdownMenuLabel(
                        o,
                        icon: iconForOption?.call(o) ?? icon,
                        iconColor: AppColors.primary.withValues(alpha: 0.85),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFleetFiltersContent(bool isMobile) {
    final statusOptions = const ['All Status', 'Active', 'Critical', 'Offline'];
    final typeOptions = const ['All Types', 'Car', 'Bus', 'Van', 'Truck', 'Rickshaw'];
    if (isMobile) {
      return Column(
        children: [
          _buildFleetStatusFilterDropdown(
            label: 'Status',
            value: _statusFilter,
            options: statusOptions,
            onChanged: (v) => setState(() => _statusFilter = v),
          ),
          const SizedBox(height: 14),
          _buildFleetFilterDropdown(
            label: 'Vehicle type',
            value: _typeFilter,
            options: typeOptions,
            iconForOption: VehicleCatalog.iconForFilterOption,
            onChanged: (v) => setState(() => _typeFilter = v),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildFleetStatusFilterDropdown(
            label: 'Status',
            value: _statusFilter,
            options: statusOptions,
            onChanged: (v) => setState(() => _statusFilter = v),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildFleetFilterDropdown(
            label: 'Vehicle type',
            value: _typeFilter,
            options: typeOptions,
            iconForOption: VehicleCatalog.iconForFilterOption,
            onChanged: (v) => setState(() => _typeFilter = v),
          ),
        ),
      ],
    );
  }

  Widget _buildFleetActiveFiltersBar(bool isMobile, {
    required bool searchActive,
    required int resultCount,
  }) {
    final hasFilters = searchActive ||
        _statusFilter != 'All Status' ||
        _typeFilter != 'All Types';
    if (!hasFilters) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 14, vertical: isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(
            '$resultCount result${resultCount == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (searchActive)
            TextButton(
              onPressed: () {
                _vehicleSearchController.clear();
                setState(() => _vehicleSearchQuery = '');
              },
              style: _fleetClearButtonStyle,
              child: const Text('Clear search', style: TextStyle(fontSize: 13)),
            ),
          if (_statusFilter != 'All Status')
            TextButton(
              onPressed: () => setState(() => _statusFilter = 'All Status'),
              style: _fleetClearButtonStyle,
              child: const Text('Clear status', style: TextStyle(fontSize: 13)),
            ),
          if (_typeFilter != 'All Types')
            TextButton(
              onPressed: () => setState(() => _typeFilter = 'All Types'),
              style: _fleetClearButtonStyle,
              child: const Text('Clear Type', style: TextStyle(fontSize: 13)),
            ),
          if (searchActive &&
              (_statusFilter != 'All Status' || _typeFilter != 'All Types'))
            TextButton.icon(
              onPressed: () {
                _vehicleSearchController.clear();
                setState(() {
                  _vehicleSearchQuery = '';
                  _statusFilter = 'All Status';
                  _typeFilter = 'All Types';
                });
              },
              icon: const Icon(Icons.clear_all, size: 16, color: AppColors.primary),
              label: const Text('Clear all', style: TextStyle(fontSize: 13)),
              style: _fleetClearButtonStyle,
            ),
        ],
      ),
    );
  }

  Widget _buildFleetVehicleListContent({
    required bool isMobile,
    required List<Vehicle> filteredVehicles,
    required bool searchActive,
  }) {
    if (filteredVehicles.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: isMobile ? 28 : 40, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(
              searchActive ||
                      _statusFilter != 'All Status' ||
                      _typeFilter != 'All Types'
                  ? Icons.filter_alt_off
                  : Icons.directions_car_outlined,
              size: isMobile ? 44 : 52,
              color: Colors.grey[400],
            ),
            SizedBox(height: isMobile ? 12 : 16),
            Text(
              searchActive ||
                      _statusFilter != 'All Status' ||
                      _typeFilter != 'All Types'
                  ? 'No Vehicles Match your Search or Filters'
                  : 'No vehicles in your fleet yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isMobile ? 14 : 16,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (searchActive ||
                _statusFilter != 'All Status' ||
                _typeFilter != 'All Types') ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  _vehicleSearchController.clear();
                  setState(() {
                    _vehicleSearchQuery = '';
                    _statusFilter = 'All Status';
                    _typeFilter = 'All Types';
                  });
                },
                style: _fleetClearButtonStyle,
                child: const Text('Clear Search & Filters'),
              ),
            ] else ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _showAddVehicleDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add your first vehicle'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (isMobile) {
      return Column(
        children: filteredVehicles.map((vehicle) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildMobileVehicleCard(vehicle),
          );
        }).toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - 200,
            ),
            child: Table(
              columnWidths: const {
                0: FixedColumnWidth(200),
                1: FixedColumnWidth(260),
              },
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade200),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: AppColors.primaryLight.withValues(alpha: 0.35)),
                  children: [
                    _buildTableHeader('License Plate', isMobile),
                    _buildTableHeader('Vehicle Name', isMobile),
                  ],
                ),
                ...filteredVehicles.map((vehicle) => _buildVehicleRow(vehicle, isMobile)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFleetOverview() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    
    return StreamBuilder<List<Vehicle>>(
      stream: _vehicleService.getVehiclesByOwnerStream(widget.user.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildFleetSectionCard(
            isMobile: isMobile,
            icon: Icons.directions_car_filled_outlined,
            title: 'Vehicle Information',
            subtitle: 'Loading your fleet...',
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            ),
          );
        }

        final vehicles = snapshot.data ?? [];

        // Build map of driverId -> hasActiveSession for filtering
        return FutureBuilder<Map<String, bool>>(
          future: _getActiveSessionMapFuture(vehicles),
          builder: (context, sessionSnapshot) {
            if (sessionSnapshot.connectionState == ConnectionState.waiting) {
              return _buildFleetSectionCard(
                isMobile: isMobile,
                icon: Icons.directions_car_filled_outlined,
                title: 'Vehicle Information',
                subtitle: 'Checking live driver sessions...',
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                ),
              );
            }

            final activeSessionMap = sessionSnapshot.data ?? {};

            // --- FILTERING ---
            final statusFilterActive = _statusFilter != 'All Status';
            final typeFilterActive = _typeFilter != 'All Types';
            final searchQuery = _vehicleSearchQuery.trim().toLowerCase();
            final searchActive = searchQuery.isNotEmpty;
            
            List<Vehicle> filteredVehicles = vehicles.where((vehicle) {
              if (!_vehicleMatchesSearch(vehicle, searchQuery)) return false;
              // Only check filters if they're active
              bool matchesStatusFilter = true;
              if (statusFilterActive) {
                final filterStatusLower = _statusFilter.toLowerCase();
                
                // Determine real-time status: Active/Critical/Offline only
                // A vehicle is Active if it has an assigned driver AND that driver has an active monitoring session
                final hasActiveSession = vehicle.assignedDriverId != null && 
                                       vehicle.assignedDriverId!.isNotEmpty &&
                                       (activeSessionMap[vehicle.assignedDriverId] == true);
                final computedStatus = hasActiveSession ? 'active' : 'offline';
                
                // Filter based on real-time session status
                if (filterStatusLower == 'active') {
                  matchesStatusFilter = hasActiveSession;
                } else if (filterStatusLower == 'offline') {
                  matchesStatusFilter = !hasActiveSession;
                } else {
                  // For critical, check stored status
                  final vehicleStatusLower = vehicle.status.toLowerCase();
                  matchesStatusFilter = filterStatusLower == 'critical'
                      ? vehicleStatusLower == 'critical'
                      : computedStatus == filterStatusLower;
                }
              }
              
              bool matchesTypeFilter = !typeFilterActive || vehicle.type == _typeFilter;

              return matchesStatusFilter && matchesTypeFilter;
            }).toList();

            final vehicleInfoSubtitle = filteredVehicles.isEmpty
                ? (searchActive ||
                        _statusFilter != 'All Status' ||
                        _typeFilter != 'All Types'
                    ? 'No Vehicles Match your Search or Filters'
                    : 'Add a vehicle above to see it listed here')
                : '${filteredVehicles.length} Vehicle${filteredVehicles.length == 1 ? '' : 's'} Shown';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFleetSectionCard(
                  isMobile: isMobile,
                  icon: Icons.add_circle_outline,
                  title: 'Add Vehicle',
                  subtitle: 'Register a New Vehicle To Your Fleet',
                  child: _buildFleetAddVehicleButton(isMobile),
                ),
                if (searchActive || _statusFilter != 'All Status' || _typeFilter != 'All Types') ...[
                  SizedBox(height: isMobile ? 12 : 14),
                  _buildFleetActiveFiltersBar(
                    isMobile,
                    searchActive: searchActive,
                    resultCount: filteredVehicles.length,
                  ),
                ],
                SizedBox(height: isMobile ? 14 : 18),
                _buildFleetSectionCard(
                  isMobile: isMobile,
                  icon: Icons.directions_car_filled_outlined,
                  title: 'Vehicle Information',
                  subtitle: vehicleInfoSubtitle,
                  trailing: filteredVehicles.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${filteredVehicles.length}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : null,
                  child: _buildFleetVehicleListContent(
                    isMobile: isMobile,
                    filteredVehicles: filteredVehicles,
                    searchActive: searchActive,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
  Widget _buildEmergency() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return _ownerPageShell(
      title: 'Emergency',
      subtitle: 'Quick access to emergency services and contacts',
      child: _buildEmergencyContent(isMobile),
    );
  }

  Widget _buildOwnerEmergencyServicesGrid(bool isMobile) {
    final police = _buildEmergencyServiceCard(
      'Police', '15', Icons.local_police, AppColors.police, AppColors.policeLight, isMobile,
    );
    final ambulance = _buildEmergencyServiceCard(
      'Ambulance', '1122', Icons.local_hospital, AppColors.ambulance, AppColors.ambulanceLight, isMobile,
    );
    final fire = _buildEmergencyServiceCard(
      'Fire Department', '16', Icons.local_fire_department, AppColors.fire, AppColors.fireLight, isMobile,
    );
    final motorway = _buildEmergencyServiceCard(
      'Motorway Police', '130', Icons.car_crash, AppColors.motorway, AppColors.motorwayLight, isMobile,
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
        _buildOwnerSectionCard(
          isMobile: isMobile,
          icon: Icons.emergency_outlined,
          title: 'Emergency Services',
          subtitle: 'One-tap access to local emergency helplines',
          child: _buildOwnerEmergencyServicesGrid(isMobile),
        ),
        SizedBox(height: isMobile ? 14 : 18),
        _buildOwnerSectionCard(
          isMobile: isMobile,
          icon: Icons.contacts_outlined,
          title: 'Emergency Contacts',
          subtitle: 'Manage people notified during critical alerts',
          child: EmergencyContactsPanel(user: widget.user, userRole: 'owner'),
        ),
      ],
    );
  }

  Widget _buildEmergencyServiceCard(String title, String number, IconData icon, Color color, Color bgColor, [bool isMobile = false]) {
    return InkWell(
      onTap: () => _dialPhoneNumber(number),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 14 : 20),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
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
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isMobile ? 4 : 6),
            Text(
              number,
              style: TextStyle(
                fontSize: isMobile ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isMobile ? 12 : 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _dialPhoneNumber(number),
                icon: Icon(Icons.phone, size: isMobile ? 16 : 18, color: Colors.white),
                label: Text(
                  'Call Now',
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerMetricChip(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for fleet overview table
  Widget _buildMobileVehicleCard(Vehicle vehicle) {
    final isMobile = DashboardLayout.isMobile(context);
    final onDetails = () => _showOwnerStatDetails('Vehicle Details', [
      ListTile(
        title: Text(vehicle.licensePlate),
        subtitle: Text('${vehicle.make} ${vehicle.model} (${vehicle.year})'),
      ),
      ListTile(
        title: const Text('Driver'),
        subtitle: Text(vehicle.driverName ?? 'Unassigned'),
      ),
      _vehicleDetailStatusTile(vehicle),
      ListTile(
        title: const Text('Type'),
        subtitle: Text(vehicle.type),
      ),
      ListTile(
        title: const Text('Location'),
        subtitle: Text(vehicle.location ?? 'Unknown'),
      ),
    ]);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onDetails,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 16 : 18),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: Icon(
                      VehicleCatalog.iconForType(vehicle.type),
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${vehicle.make} ${vehicle.model}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Year ${vehicle.year}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _buildMobileRealtimeStatusBadge(vehicle),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildOwnerMetricChip('License Plate', vehicle.licensePlate),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildOwnerMetricChip('Type', vehicle.type),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildOwnerMetricChip(
                'Driver',
                vehicle.driverName?.isNotEmpty == true ? vehicle.driverName! : 'Unassigned',
                valueColor: vehicle.driverName?.isNotEmpty == true
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _confirmDeleteVehicle(vehicle),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 14,
          vertical: isMobile ? 10 : 12),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: isMobile ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 14,
          vertical: isMobile ? 10 : 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isMobile ? 12 : 14,
          color: Colors.black87,
        ),
      ),
    );
  }

  TableRow _buildVehicleRow(Vehicle vehicle, [bool isMobile = false]) {
    return TableRow(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14, vertical: isMobile ? 10 : 12),
          child: InkWell(
            onTap: () => _showOwnerStatDetails('Vehicle Details', [
              ListTile(title: Text(vehicle.licensePlate), subtitle: Text('${vehicle.make} ${vehicle.model} (${vehicle.year})')),
              ListTile(title: const Text('Driver'), subtitle: Text(vehicle.driverName ?? 'Unassigned')),
              _vehicleDetailStatusTile(vehicle),
              ListTile(title: const Text('Location'), subtitle: Text(vehicle.location ?? 'Unknown')),
            ]),
            child: Text(
              vehicle.licensePlate,
              style: TextStyle(
                fontSize: isMobile ? 12 : 14,
                color: AppColors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        _buildTableCell('${vehicle.make} ${vehicle.model}', isMobile),
      ],
    );
  }

  Widget _buildDriverCell(Vehicle vehicle, [bool isMobile = false]) {
    final hasDriver = vehicle.assignedDriverId != null && vehicle.assignedDriverId!.isNotEmpty;
    final name = vehicle.driverName ?? 'Unassigned';
    if (!hasDriver) return _buildTableCell(name, isMobile);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: isMobile ? 12 : 16),
      child: InkWell(
        onTap: () => _showOwnerStatDetails('Driver Details', [
          ListTile(
            dense: true,
            title: Text(name),
            subtitle: Text('Email: ${vehicle.assignedDriverEmail ?? 'N/A'}\nVehicle: ${vehicle.licensePlate}'),
          ),
          _vehicleDetailStatusTile(vehicle),
        ]),
        child: Text(
          name,
          style: TextStyle(
            fontSize: isMobile ? 12 : 14,
            color: AppColors.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  // Real-time status badge - Active only while monitoring pushes stats to RTDB; else Offline; Critical when unsafe.
  Widget _buildRealtimeStatusBadge(Vehicle vehicle, [bool isMobile = false]) {
    if (vehicle.assignedDriverId == null || vehicle.assignedDriverId!.isEmpty) {
      return _buildStatusBadge('Offline', isMobile);
    }

    return StreamBuilder<bool>(
      stream: _monitoringService.watchHasActiveMonitoringSession(vehicle.assignedDriverId!),
      builder: (context, sessionSnap) {
        final active = sessionSnap.data == true;
        return StreamBuilder<Map<String, dynamic>>(
          stream: _monitoringService.getCurrentStats(vehicle.assignedDriverId!),
          builder: (context, statsSnap) {
            final label = _ownerOperationalStatusLabel(active, statsSnap.data);
            return _buildStatusBadge(label, isMobile);
          },
        );
      },
    );
  }

  // Real-time last update cell
  Widget _buildRealtimeLastUpdateCell(Vehicle vehicle, [bool isMobile = false]) {
    if (vehicle.assignedDriverId == null) {
      return _buildTableCell(vehicle.lastUpdate ?? 'N/A', isMobile);
    }

    return StreamBuilder<Map<String, dynamic>>(
      stream: _monitoringService.getCurrentStats(vehicle.assignedDriverId!),
      builder: (context, snapshot) {
        String lastUpdate = 'No session';

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final stats = snapshot.data!;
          final lastUpdateTimestamp = stats['lastUpdate'];
          if (lastUpdateTimestamp != null) {
            // Convert timestamp to readable format
            try {
              final timestamp = lastUpdateTimestamp as int;
              final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
              final now = DateTime.now();
              final difference = now.difference(dateTime);

              if (difference.inSeconds < 60) {
                lastUpdate = 'Just now';
              } else if (difference.inMinutes < 60) {
                lastUpdate = '${difference.inMinutes}m ago';
              } else if (difference.inHours < 24) {
                lastUpdate = '${difference.inHours}h ago';
              } else {
                lastUpdate = '${difference.inDays}d ago';
              }
            } catch (e) {
              // Keep default if parsing fails
            }
          }
        }

        return _buildTableCell(lastUpdate, isMobile);
      },
    );
  }

  Widget _buildStatusBadge(String status, [bool isMobile = false]) {
    Color color;
    switch (status) {
      case 'Active':
        color = AppColors.success;
        break;
      case 'Critical':
        color = AppColors.danger;
        break;
      case 'Offline':
        color = Colors.grey;
        break;
      default:
        color = Colors.grey;
    }

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 16,
          vertical: isMobile ? 0 : 12),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 12,
            vertical: isMobile ? 4 : 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          status,
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

  Widget _buildAlertnessCell(int alertnessValue, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 8 : 12),
      child: Row(
        children: [
          Text(
            '$alertnessValue%',
            style: TextStyle(
              fontSize: isMobile ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(width: isMobile ? 6 : 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: alertnessValue / 100,
                minHeight: isMobile ? 5 : 6,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  alertnessValue >= 80 ? AppColors.success :
                  alertnessValue >= 70 ? AppColors.warning : AppColors.danger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Real-time alertness cell that listens to Firebase
  Widget _buildRealtimeAlertnessCell(Vehicle vehicle, [bool isMobile = false]) {
    // If no driver assigned, show static value
    if (vehicle.assignedDriverId == null) {
      return _buildAlertnessCell(vehicle.alertness, isMobile);
    }

    // Listen to real-time stats from Firebase
    return StreamBuilder<Map<String, dynamic>>(
      stream: _monitoringService.getCurrentStats(vehicle.assignedDriverId!),
      builder: (context, snapshot) {
        int alertnessValue = 0; // Default to 0 if no session

        // If we have real-time data, use it
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final stats = snapshot.data!;
          final realtimeAlertness = stats['alertness'];
          if (realtimeAlertness != null) {
            alertnessValue = (realtimeAlertness as num).toInt();
          }
        }

        return _buildAlertnessCell(alertnessValue, isMobile);
      },
    );
  }

  Widget _buildActionsCell(Vehicle vehicle, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 8,
          vertical: isMobile ? 0 : 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.delete_outline, size: isMobile ? 18 : 20, color: Colors.red[700]),
            onPressed: () => _confirmDeleteVehicle(vehicle),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Delete vehicle',
          ),
          SizedBox(width: isMobile ? 4 : 8),
          IconButton(
            icon: Icon(Icons.phone_outlined, size: isMobile ? 18 : 20),
            onPressed: () async {
              // Get driver's phone number from Firestore
              if (vehicle.assignedDriverId != null && vehicle.assignedDriverId!.isNotEmpty) {
                try {
                  final driverDoc = await _firestore.collection('users').doc(vehicle.assignedDriverId).get();
                  if (driverDoc.exists) {
                    final driverPhone = driverDoc.data()?['phone'] as String?;
                    if (driverPhone != null && driverPhone.isNotEmpty) {
                      final uri = Uri.parse('tel:$driverPhone');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cannot make phone call'))
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Driver phone number not available'))
                      );
                    }
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'))
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No driver assigned to this vehicle'))
                );
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteVehicle(Vehicle vehicle) async {
    final title = '${vehicle.make} ${vehicle.model}'.trim();
    final plate = vehicle.licensePlate;
    final hasDriver =
        vehicle.assignedDriverId != null && vehicle.assignedDriverId!.isNotEmpty;

    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Delete Vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to Delete this Vehicle?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isNotEmpty ? title : 'Unknown Vehicle',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (plate.isNotEmpty)
                    Text('Plate: $plate', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            ),
            if (hasDriver) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: Color(0xFFFF9800)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This Vehicle has an Assigned Driver. The Driver will be Unassigned.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFFF9800)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'This Action Cannot be Undone.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _vehicleService.deleteVehicle(vehicle.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            title.isNotEmpty ? '$title has been deleted' : 'Vehicle has been deleted',
          ),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting vehicle: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Mobile real-time alertness widget
  Widget _buildMobileRealtimeAlertness(Vehicle vehicle) {
    if (vehicle.assignedDriverId == null) {
      return Row(
        children: [
          Text(
            'Alertness: ',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          Text(
            '${vehicle.alertness}%',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: vehicle.alertness / 100,
                minHeight: 6,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  vehicle.alertness >= 80 ? AppColors.success :
                  vehicle.alertness >= 70 ? AppColors.warning : AppColors.danger,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return StreamBuilder<Map<String, dynamic>>(
      stream: _monitoringService.getCurrentStats(vehicle.assignedDriverId!),
      builder: (context, snapshot) {
        int alertnessValue = 0; // Default to 0 if no session

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final stats = snapshot.data!;
          final realtimeAlertness = stats['alertness'];
          if (realtimeAlertness != null) {
            alertnessValue = (realtimeAlertness as num).toInt();
          }
        }

        return Row(
          children: [
            Text(
              'Alertness: ',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            Text(
              '$alertnessValue%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: alertnessValue / 100,
                  minHeight: 6,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    alertnessValue >= 80 ? AppColors.success :
                    alertnessValue >= 70 ? AppColors.warning : AppColors.danger,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobileRealtimeStatusBadge(Vehicle vehicle) => _buildRealtimeStatusBadge(vehicle, true);

  // Mobile real-time last update widget
  Widget _buildMobileRealtimeLastUpdate(Vehicle vehicle) {
    if (vehicle.assignedDriverId == null) {
      return Text(
        vehicle.lastUpdate ?? 'N/A',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    }

    return StreamBuilder<Map<String, dynamic>>(
      stream: _monitoringService.getCurrentStats(vehicle.assignedDriverId!),
      builder: (context, snapshot) {
        String lastUpdate = 'No session';

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final stats = snapshot.data!;
          final lastUpdateTimestamp = stats['lastUpdate'];
          if (lastUpdateTimestamp != null) {
            try {
              final timestamp = lastUpdateTimestamp as int;
              final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
              final now = DateTime.now();
              final difference = now.difference(dateTime);

              if (difference.inSeconds < 60) {
                lastUpdate = 'Just now';
              } else if (difference.inMinutes < 60) {
                lastUpdate = '${difference.inMinutes}m ago';
              } else if (difference.inHours < 24) {
                lastUpdate = '${difference.inHours}h ago';
              } else {
                lastUpdate = '${difference.inDays}d ago';
              }
            } catch (e) {
              // Keep default if parsing fails
            }
          }
        }

        return Text(
          lastUpdate,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        );
      },
    );
  }
}

class _OwnerDashboardActiveDriversCard extends StatefulWidget {
  const _OwnerDashboardActiveDriversCard({
    required this.vehicles,
    required this.monitoringService,
    required this.isMobile,
    required this.builder,
  });

  final List<Vehicle> vehicles;
  final MonitoringService monitoringService;
  final bool isMobile;
  final Widget Function(
    BuildContext context,
    int activeDriverCount,
    List<Widget> activeDriverTiles,
  ) builder;

  @override
  State<_OwnerDashboardActiveDriversCard> createState() => _OwnerDashboardActiveDriversCardState();
}

class _OwnerDashboardActiveDriversCardState extends State<_OwnerDashboardActiveDriversCard> {
  final Map<String, bool> _sessionActiveByDriver = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Set<String> _driverIds() =>
      widget.vehicles.map((v) => v.assignedDriverId).whereType<String>().toSet();

  void _resubscribe() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    setState(() => _sessionActiveByDriver.clear());

    for (final id in _driverIds()) {
      _subscriptions.add(
        widget.monitoringService.watchHasActiveMonitoringSession(id).listen((isActive) {
          if (!mounted) return;
          setState(() {
            _sessionActiveByDriver[id] = isActive;
          });
        }),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _resubscribe();
  }

  @override
  void didUpdateWidget(covariant _OwnerDashboardActiveDriversCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.vehicles.map((v) => v.assignedDriverId).whereType<String>().toSet();
    final b = widget.vehicles.map((v) => v.assignedDriverId).whereType<String>().toSet();
    if (a.length != b.length || !a.containsAll(b) || !b.containsAll(a)) {
      _resubscribe();
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeDriverIds = _sessionActiveByDriver.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toSet();

    final activeVehicles = widget.vehicles.where((v) {
      final id = v.assignedDriverId;
      if (id == null || id.isEmpty) return false;
      return activeDriverIds.contains(id);
    }).toList();

    final details = activeVehicles.isEmpty
        ? <Widget>[
            const ListTile(
              dense: true,
              title: Text('No Active Monitoring Sessions'),
            ),
          ]
        : activeVehicles
            .map(
              (v) => ListTile(
                dense: true,
                title: Text(v.driverName ?? 'Assigned Driver'),
                subtitle: Text('Vehicle: ${v.licensePlate}\n${v.assignedDriverEmail ?? ''}'),
              ),
            )
            .toList();

    return widget.builder(context, activeDriverIds.length, details);
  }
}

/// Live critical list from RTDB `current_stats` per assigned driver (same rules as driver monitoring).
class _OwnerDashboardCriticalAlertsCard extends StatefulWidget {
  const _OwnerDashboardCriticalAlertsCard({
    required this.vehicles,
    required this.isMobile,
    required this.monitoringService,
    required this.builder,
  });

  final List<Vehicle> vehicles;
  final bool isMobile;
  final MonitoringService monitoringService;
  final Widget Function(BuildContext context, List<Vehicle> criticalVehicles) builder;

  @override
  State<_OwnerDashboardCriticalAlertsCard> createState() => _OwnerDashboardCriticalAlertsCardState();
}

class _OwnerDashboardCriticalAlertsCardState extends State<_OwnerDashboardCriticalAlertsCard> {
  final Map<String, bool> _sessionActiveByDriver = {};
  final Map<String, Map<String, dynamic>> _statsByDriver = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Set<String> _driverIds() =>
      widget.vehicles.map((v) => v.assignedDriverId).whereType<String>().toSet();

  void _resubscribe() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    setState(() => _statsByDriver.clear());

    for (final id in _driverIds()) {
      _subscriptions.add(
        widget.monitoringService.watchHasActiveMonitoringSession(id).listen((isActive) {
          if (!mounted) return;
          setState(() {
            _sessionActiveByDriver[id] = isActive;
          });
        }),
      );
      _subscriptions.add(
        widget.monitoringService.getCurrentStats(id).listen((stats) {
          if (!mounted) return;
          setState(() {
            if (stats.isEmpty) {
              _statsByDriver.remove(id);
            } else {
              _statsByDriver[id] = stats;
            }
          });
        }),
      );
    }
  }

  List<Vehicle> _criticalVehicles() {
    return widget.vehicles.where((v) {
      final id = v.assignedDriverId;
      if (id == null || id.isEmpty) return false;
      if (_sessionActiveByDriver[id] != true) return false;
      final stats = _statsByDriver[id];
      if (stats == null || stats.isEmpty) return false;
      return ownerLiveMetricsCritical(stats);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _resubscribe();
  }

  @override
  void didUpdateWidget(covariant _OwnerDashboardCriticalAlertsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.vehicles.map((v) => v.assignedDriverId).whereType<String>().toSet();
    final b = widget.vehicles.map((v) => v.assignedDriverId).whereType<String>().toSet();
    if (a.length != b.length || !a.containsAll(b) || !b.containsAll(a)) {
      _resubscribe();
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _criticalVehicles());
  }
}

class _OwnerDashboardLiveSafetyScoreCard extends StatefulWidget {
  const _OwnerDashboardLiveSafetyScoreCard({
    required this.vehicles,
    required this.isMobile,
    required this.monitoringService,
    required this.builder,
  });

  final List<Vehicle> vehicles;
  final bool isMobile;
  final MonitoringService monitoringService;
  final Widget Function(
    BuildContext context,
    String safetyScoreText,
    Color safetyColor,
    List<Widget> details,
  ) builder;

  @override
  State<_OwnerDashboardLiveSafetyScoreCard> createState() => _OwnerDashboardLiveSafetyScoreCardState();
}

class _OwnerDashboardLiveSafetyScoreCardState extends State<_OwnerDashboardLiveSafetyScoreCard> {
  final Map<String, bool> _sessionActiveByDriver = {};
  final Map<String, Map<String, dynamic>> _statsByDriver = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Set<String> _driverIds() => widget.vehicles.map((v) => v.assignedDriverId).whereType<String>().toSet();

  void _resubscribe() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    setState(() {
      _sessionActiveByDriver.clear();
      _statsByDriver.clear();
    });

    for (final id in _driverIds()) {
      _subscriptions.add(
        widget.monitoringService.watchHasActiveMonitoringSession(id).listen((isActive) {
          if (!mounted) return;
          setState(() {
            _sessionActiveByDriver[id] = isActive;
          });
        }),
      );
      _subscriptions.add(
        widget.monitoringService.getCurrentStats(id).listen((stats) {
          if (!mounted) return;
          setState(() {
            if (stats.isEmpty) {
              _statsByDriver.remove(id);
            } else {
              _statsByDriver[id] = stats;
            }
          });
        }),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _resubscribe();
  }

  @override
  void didUpdateWidget(covariant _OwnerDashboardLiveSafetyScoreCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.vehicles.map((v) => v.assignedDriverId).whereType<String>().toSet();
    final b = widget.vehicles.map((v) => v.assignedDriverId).whereType<String>().toSet();
    if (a.length != b.length || !a.containsAll(b) || !b.containsAll(a)) {
      _resubscribe();
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double total = 0;
    int count = 0;
    final details = <Widget>[];

    for (final v in widget.vehicles) {
      final id = v.assignedDriverId;
      if (id == null || id.isEmpty) {
        details.add(
          ListTile(
            dense: true,
            title: Text(v.licensePlate),
            subtitle: Text('${v.make} ${v.model}'),
            trailing: const Text('Offline'),
          ),
        );
        continue;
      }

      final isActive = _sessionActiveByDriver[id] == true;
      final stats = _statsByDriver[id];
      final alertness = stats?['alertness'];
      final hasLiveAlertness = isActive && alertness is num;
      final valueText = hasLiveAlertness
          ? '${((alertness as num).toDouble() / 10).clamp(0.0, 10.0).toStringAsFixed(1)}/10'
          : (isActive ? '...' : 'Offline');

      if (hasLiveAlertness) {
        total += ((alertness as num).toDouble() / 10).clamp(0.0, 10.0);
        count++;
      }

      details.add(
        ListTile(
          dense: true,
          title: Text(v.licensePlate),
          subtitle: Text('${v.make} ${v.model}'),
          trailing: Text(valueText),
        ),
      );
    }

    final score = count > 0 ? total / count : 0.0;
    final scoreText = '${score.toStringAsFixed(1)}/10';
    final color = score >= 7.0 ? AppColors.success : (score >= 5.0 ? Colors.orange : AppColors.danger);
    return widget.builder(context, scoreText, color, details);
  }
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

// Custom formatter for Vehicle Registration Number input (ABC-123 format)
class _LicensePlateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.toUpperCase();
    
    // Remove all non-alphanumeric characters except dash
    String formatted = text.replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
    
    // Limit to 7 characters (3 letters + dash + 3 digits)
    if (formatted.length > 7) {
      formatted = formatted.substring(0, 7);
    }
    
    // Insert dash after 3 letters if not already present
    if (formatted.length > 3 && !formatted.contains('-')) {
      formatted = '${formatted.substring(0, 3)}-${formatted.substring(3)}';
    }
    
    // Ensure only letters before dash and only digits after
    if (formatted.contains('-')) {
      final parts = formatted.split('-');
      if (parts.length == 2) {
        final letters = parts[0].replaceAll(RegExp(r'[^A-Z]'), '');
        final digits = parts[1].replaceAll(RegExp(r'[^0-9]'), '');
        formatted = '$letters-$digits';
      }
    } else if (formatted.length > 3) {
      // If no dash but more than 3 chars, insert dash
      final letters = formatted.substring(0, 3).replaceAll(RegExp(r'[^A-Z]'), '');
      final digits = formatted.substring(3).replaceAll(RegExp(r'[^0-9]'), '');
      formatted = '$letters-$digits';
    } else {
      // Only letters allowed before dash position
      formatted = formatted.replaceAll(RegExp(r'[^A-Z]'), '');
    }
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
