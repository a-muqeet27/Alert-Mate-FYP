import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import '../models/user.dart';
import '../models/emergency_contact.dart';
import '../utils/sign_out_flow.dart';
import '../widgets/shared/app_sidebar.dart';
import '../widgets/shared/live_map.dart';
import '../constants/app_colors.dart';
import '../services/emergency_contact_service.dart';
import '../services/emergency_alert_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vehicle.dart';
import '../services/vehicle_service.dart';
import '../services/monitoring_service.dart';
import '../widgets/email_verified_guard.dart';
import '../screens/notifications_inbox_screen.dart';
import '../services/user_notifications_service.dart';
import '../widgets/mobile_drawer_menu_button.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/dashboard_responsive.dart';

class PassengerDashboard extends StatefulWidget {
  final User user;

  const PassengerDashboard({Key? key, required this.user}) : super(key: key);

  @override
  State<PassengerDashboard> createState() => _PassengerDashboardState();
}

class _PassengerDashboardState extends State<PassengerDashboard>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  final Random _random = Random();

  List<MenuItem> get _sidebarMenuItems => [
        const MenuItem(
          section: 'Trip',
          icon: Icons.search,
          title: 'Find Vehicle',
        ),
        const MenuItem(
          section: 'Trip',
          icon: Icons.map_outlined,
          title: 'Map',
        ),
        const MenuItem(
          section: 'Safety',
          icon: Icons.warning_amber_rounded,
          title: 'Emergency Alert',
        ),
        const MenuItem(
          section: 'Safety',
          icon: Icons.phone_outlined,
          title: 'Emergency Services',
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
        return _buildVehicleLookupPage();
      case 1:
        return _buildTripMapPage();
      case 2:
        return _buildEmergencyAlertPage();
      case 3:
        return _buildEmergency();
      case 4:
        return _buildPassengerNotificationsPage();
      default:
        return _buildVehicleLookupPage();
    }
  }

  String get _currentPageTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Find Vehicle';
      case 1:
        return 'Map';
      case 2:
        return 'Emergency Alert';
      case 3:
        return 'Emergency Services';
      case 4:
        return 'Notifications';
      default:
        return 'Find Vehicle';
    }
  }

  String get _currentPageSubtitle {
    switch (_selectedIndex) {
      case 0:
        return 'Connect with Your Driver';
      case 1:
        return 'Live Driver Location on Map';
      case 2:
        return 'Notify driver, owner, and administrators in an emergency';
      case 3:
        return 'Quick access to emergency services and contacts';
      case 4:
        return 'Alerts and system messages';
      default:
        return 'Connect with Your Driver';
    }
  }

  Widget _buildPassengerNotificationsPage() {
    return _passengerPageShell(
      title: 'Notifications',
      subtitle: 'Alerts and system messages',
      child: NotificationsInboxScreen(user: widget.user, embedded: true),
    );
  }

  Widget _passengerPageShell({
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

  Widget _buildPassengerMetricPanel({required Widget child, bool isMobile = false}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: child,
    );
  }

  Widget _buildPassengerMetricChip(String label, String value, {Color? valueColor, bool compact = false}) {
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
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  double _passengerMapHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return (h * 0.55).clamp(320.0, 520.0);
  }

  Widget _buildPassengerSectionCard({
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

  Widget _buildVehicleLookupPage() {
    final isMobile = DashboardLayout.isMobile(context);
    final hasTrip = _lookupVehicle != null || (_lookupDriverId != null && _lookupDriverId!.isNotEmpty);
    return _passengerPageShell(
      title: 'Find Vehicle',
      subtitle: 'Search by license plate to connect with your driver',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStaggeredItem(
            _buildPassengerSectionCard(
              isMobile: isMobile,
              icon: Icons.search,
              title: 'Find Vehicle',
              subtitle: 'Enter the License Plate to Connect With Your Driver',
              child: _buildPlateLookupSection(),
            ),
            0,
          ),
          if (hasTrip) ...[
            SizedBox(height: isMobile ? 14 : 18),
            _buildStaggeredItem(
              _buildPassengerSectionCard(
                isMobile: isMobile,
                icon: Icons.directions_car_filled_outlined,
                title: 'Trip Status',
                subtitle: 'Live Driver and Vehicle Information',
                child: _buildPlateLookupResults(),
              ),
              1,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripMapPage() {
    final isMobile = DashboardLayout.isMobile(context);
    final driverId = _lookupDriverId;
    final hasDriver = driverId != null && driverId.isNotEmpty;

    return _passengerPageShell(
      title: 'Map',
      subtitle: hasDriver
          ? 'Live driver location'
          : 'Find a vehicle under Find Vehicle to view the map',
      child: _buildStaggeredItem(
        hasDriver
            ? _buildPassengerLiveMapBlock(driverId!)
            : _buildPassengerMapEmptyState(isMobile),
        0,
      ),
    );
  }

  Widget _buildPassengerLiveMapBlock(String driverId) {
    final mapHeight = _passengerMapHeight(context);
    return SizedBox(
      width: double.infinity,
      height: mapHeight,
      child: LiveMap(
        filterDriverIds: [driverId],
        showHeader: true,
        height: mapHeight,
      ),
    );
  }

  Widget _buildPassengerMapEmptyState(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: isMobile ? 32 : 48, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.map_outlined, size: isMobile ? 52 : 64, color: Colors.grey[400]),
          SizedBox(height: isMobile ? 14 : 18),
          Text(
            'No Driver Connected',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Go to "Find Vehicle" and "Search by License Plate" to View Live Map',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyAlertPage() {
    final isMobile = DashboardLayout.isMobile(context);
    return _passengerPageShell(
      title: 'Emergency Alert',
      subtitle: 'Notify driver, owner, and administrators in an emergency',
      child: _buildStaggeredItem(
        _buildPassengerSectionCard(
          isMobile: isMobile,
          icon: Icons.warning_amber_rounded,
          title: 'Emergency Alert',
          subtitle: 'Send an Alert to Driver, Owner and Administrators',
          child: _buildEmergencyControlsCard(),
        ),
        0,
      ),
    );
  }
  late EmergencyContactService _emergencyContactService;
  final EmergencyAlertService _emergencyAlertService = EmergencyAlertService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final VehicleService _vehicleService = VehicleService();
  final MonitoringService _monitoringService = MonitoringService();
  Vehicle? _selectedVehicle;
  String? _selectedDriverId;
  // Plate lookup state
  final TextEditingController _plateController = TextEditingController();
  bool _isSearchingPlate = false;
  String? _plateError;
  Vehicle? _lookupVehicle;
  String? _lookupDriverId;
  DateTime? _lookupStartedAt;

  
  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  // Real-time data
  double _driverAlertness = 82.9;

  Timer? _updateTimer;
  
  // Emergency contacts stream - initialized once in initState
  Stream<List<EmergencyContact>>? _emergencyContactsStream;

  @override
  void initState() {
    super.initState();
    _emergencyContactService = EmergencyContactService();
    
    // Initialize emergency contacts stream ONCE here
    _emergencyContactsStream = _emergencyContactService.getEmergencyContactsStream(widget.user.id);
    
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
    _startDataUpdate();
  }

  // Vehicle selector
  Widget _buildVehicleSelector() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Vehicle / Driver',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Vehicle>>(
            stream: _vehiclesForPassengerStream(),
            builder: (context, snapshot) {
              final vehicles = snapshot.data ?? [];
              vehicles.sort((a, b) => (b.status == 'Active' ? 1 : 0)
                  .compareTo(a.status == 'Active' ? 1 : 0));
              if (_selectedVehicle != null) {
                final exists = vehicles.any((v) => v.id == _selectedVehicle!.id);
                if (!exists) {
                  _onSelectVehicle(null);
                }
              }
              // Use vehicleId (String) as the dropdown value to avoid identity issues
              final String? selectedId = _selectedVehicle?.id;
              return DropdownButton<String>(
                value: vehicles.any((v) => v.id == selectedId) ? selectedId : null,
                hint: const Text('Choose a vehicle to follow'),
                isExpanded: true,
                items: vehicles.map((v) {
                  final title = '${v.make} ${v.model} (${v.year})'
                      '${v.driverName != null ? ' • ${v.driverName}' : ''}'
                      ' • ${v.status}';
                  return DropdownMenuItem<String>(
                    value: v.id,
                    child: Text(title, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (vehicleId) {
                  if (vehicleId == null) {
                    _onSelectVehicle(null);
                    return;
                  }
                  final matches = vehicles.where((v) => v.id == vehicleId);
                  if (matches.isEmpty) {
                    _onSelectVehicle(null);
                  } else {
                    _onSelectVehicle(matches.first);
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _startDataUpdate() {
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      setState(() {
        _driverAlertness = 75 + _random.nextDouble() * 20;
      });
    });
  }

  // Stream vehicles so passenger can select which ride to follow
  Stream<List<Vehicle>> _vehiclesForPassengerStream() {
    return _firestore
        .collection('vehicles')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Vehicle.fromMap({'id': d.id, ...d.data()}))
            .toList());
  }

  void _onSelectVehicle(Vehicle? v) {
    setState(() {
      _selectedVehicle = v;
      _selectedDriverId = v?.assignedDriverId;
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _plateController.dispose();
    _updateTimer?.cancel();
    super.dispose();
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
            role: 'Passenger',
            user: widget.user,
            selectedIndex: _selectedIndex,
            onMenuItemTap: (index) => setState(() => _selectedIndex = index),
            menuItems: _sidebarMenuItems,
            accentColor: AppColors.primary,
            accentLightColor: AppColors.primaryLight,
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
          role: 'Passenger',
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




  // Normalize license plate: uppercase, remove spaces and hyphens
  String _normalizePlate(String input) {
    return input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  }

  // Build common formatting variants to match Firestore values exactly
  // because Firestore equality is case/format sensitive.
  List<String> _buildPlateVariants(String rawInput) {
    final trimmed = rawInput.trim();
    final upper = trimmed.toUpperCase();
    final lower = trimmed.toLowerCase();
    final noSepUpper = _normalizePlate(trimmed); // e.g., AAA111

    // If pattern like ABC123 -> add ABC-123 and ABC 123
    final match = RegExp(r'^([A-Za-z]+)[\s-]*([0-9]+)$').firstMatch(upper);
    String withDash = upper;
    String withSpace = upper;
    if (match != null) {
      final partA = match.group(1) ?? '';
      final partB = match.group(2) ?? '';
      withDash = '$partA-$partB';
      withSpace = '$partA $partB';
    }

    // Unique, ordered attempts (most likely first)
    final variants = <String>{
      trimmed,
      upper,
      lower,
      withDash,
      withSpace,
      noSepUpper,
    }.toList();

    // Remove empty strings just in case
    return variants.where((v) => v.isNotEmpty).toList();
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findVehicleByPlate(
    String rawInput,
  ) async {
    final variants = _buildPlateVariants(rawInput);
    for (final value in variants) {
      final snap = await _firestore
          .collection('vehicles')
          .where('licensePlate', isEqualTo: value)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first;
      }
    }
    return null;
  }

  Future<void> _searchByPlate() async {
    final raw = _plateController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _plateError = 'Enter a license plate';
        _lookupVehicle = null;
        _lookupDriverId = null;
      });
      return;
    }
    setState(() {
      _isSearchingPlate = true;
      _plateError = null;
      _lookupVehicle = null;
      _lookupDriverId = null;
    });
    try {
      final doc = await _findVehicleByPlate(raw);
      if (doc == null) {
        setState(() {
          _plateError = 'No vehicle found with this license plate';
          _isSearchingPlate = false;
        });
        return;
      }
      final v = Vehicle.fromMap({'id': doc.id, ...doc.data() as Map<String, dynamic>});
      final driverId = v.assignedDriverId ?? '';
      if (driverId.isEmpty) {
        setState(() {
          _lookupVehicle = v;
          _lookupDriverId = null;
          _isSearchingPlate = false;
          _plateError = 'No driver currently assigned to this vehicle';
        });
        return;
      }
      setState(() {
        _lookupVehicle = v;
        _lookupDriverId = driverId;
        _lookupStartedAt = DateTime.now();
        _isSearchingPlate = false;
      });
    } catch (e) {
      setState(() {
        _plateError = 'Error: $e';
        _isSearchingPlate = false;
      });
    }
  }

  Widget _buildPlateLookupSection() {
    final isMobile = DashboardLayout.isMobile(context);
    return _buildPassengerMetricPanel(
      isMobile: isMobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _plateController,
                      textCapitalization: TextCapitalization.characters,
                      cursorColor: AppColors.primary,
                      decoration: InputDecoration(
                        hintText: 'e.g. ABC-123',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.primary, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: _isSearchingPlate ? null : _searchByPlate,
                        icon: const Icon(Icons.search, size: 18),
                        label: Text(_isSearchingPlate ? 'Searching...' : 'Search'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _plateController,
                        textCapitalization: TextCapitalization.characters,
                        cursorColor: AppColors.primary,
                        decoration: InputDecoration(
                          hintText: 'Enter license plate (e.g., ABC-123)',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppColors.primary, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: _isSearchingPlate ? null : _searchByPlate,
                        icon: const Icon(Icons.search, size: 18),
                        label: Text(_isSearchingPlate ? 'Searching...' : 'Search'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
          if (_plateError != null) ...[
            const SizedBox(height: 6),
            Text(
              _plateError!,
              style: const TextStyle(fontSize: 13, color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlateLookupResults() {
    final v = _lookupVehicle;
    final driverId = _lookupDriverId;
    if (v == null && driverId == null) {
      // Nothing to show yet
      return const SizedBox.shrink();
    }
    final isMobile = DashboardLayout.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPassengerMetricPanel(
          isMobile: isMobile,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vehicle & Driver',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              if (v != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildPassengerMetricChip(
                        'Driver',
                        v.driverName ?? (driverId ?? 'Unknown'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildPassengerMetricChip('Plate', v.licensePlate),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildPassengerMetricChip('Vehicle', '${v.make} ${v.model}'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildFindVehicleTripInfo(),
        const SizedBox(height: 14),
        if (driverId != null && driverId.isNotEmpty)
          _buildLiveStatusCards(driverId)
        else
          _buildPassengerMetricPanel(
            isMobile: isMobile,
            child: const Text(
              'No live data (no driver assigned)',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }

  // Two-card row: Driver Alertness + Safety Status based on live RTDB stats
  Widget _buildLiveStatusCards(String driverId) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    
    // Check if driver is actively monitoring (status = 'on_trip')
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('drivers').doc(driverId).snapshots(),
      builder: (context, driverSnapshot) {
        final driverData = driverSnapshot.data?.data() as Map<String, dynamic>?;
        final driverStatus = driverData?['status'] as String?;
        final isMonitoring = driverStatus == 'on_trip';
        
        if (!isMonitoring) {
          return _buildPassengerMetricPanel(
            isMobile: isMobile,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey[500], size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Monitoring Not Started',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Live status appears when the driver starts monitoring.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
              ],
            ),
          );
        }
        
        // Driver is monitoring - show live stats
        final cards = StreamBuilder<Map<String, dynamic>>(
          stream: _monitoringService.getCurrentStats(driverId),
          builder: (context, snapshot) {
            final hasLive = snapshot.hasData && (snapshot.data?.isNotEmpty == true);
            if (!hasLive) {
              return _buildPassengerMetricPanel(
                isMobile: isMobile,
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
              );
            }
            final data = snapshot.data!;
            final drowsy = data['drowsinessDetected'] == true;
            final safe = !drowsy;
            final statusColor = safe ? const Color(0xFF4CAF50) : Colors.red;
            return isMobile
                ? Column(
                    children: [
                      _buildDriverStateBadgeCard(drowsy),
                      const SizedBox(height: 16),
                      _buildSafetyStatusCardUI(safe, drowsy, statusColor),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildDriverStateBadgeCard(drowsy)),
                      const SizedBox(width: 20),
                      Expanded(child: _buildSafetyStatusCardUI(safe, drowsy, statusColor)),
                    ],
                  );
          },
        );
        return cards;
      },
    );
  }

  Widget _buildDriverStateBadgeCard(bool drowsy) {
    final isMobile = DashboardLayout.isMobile(context);
    return _buildPassengerMetricPanel(
      isMobile: isMobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.podcasts, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              const Text(
                'Live Driver Status',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildPassengerMetricChip(
            'Status',
            drowsy ? 'Drowsy' : 'Normal',
            valueColor: drowsy ? AppColors.danger : AppColors.success,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyStatusCardUI(bool safe, bool drowsy, Color statusColor) {
    final isMobile = DashboardLayout.isMobile(context);
    return _buildPassengerMetricPanel(
      isMobile: isMobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              const Text(
                'Safety Status',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildPassengerMetricChip(
            'Status',
            safe ? 'Safe' : (drowsy ? 'Critical' : 'Break Recommended'),
            valueColor: statusColor,
            compact: true,
          ),
          const SizedBox(height: 10),
          Text(
            safe ? 'All systems active' : (drowsy ? 'Drowsiness detected' : 'Consider taking a short break'),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyControlsCard() {
    final driverId = _lookupDriverId;
    if (driverId == null || driverId.isEmpty) {
      return _buildEmergencyControlsCardContent(
        canSend: false,
        statusMessage: 'Search for a vehicle under Find Vehicle before sending an alert.',
      );
    }

    return StreamBuilder<bool>(
      stream: _monitoringService.watchHasActiveMonitoringSession(driverId),
      builder: (context, snapshot) {
        final sessionActive = snapshot.data ?? false;
        return _buildEmergencyControlsCardContent(
          canSend: sessionActive,
          statusMessage: sessionActive
              ? null
              : 'The Driver Has Not Started Monitoring Yet. '
              'You Can Send An Alert After They Tap Start Monitoring.',
        );
      },
    );
  }

  Widget _buildEmergencyControlsCardContent({
    required bool canSend,
    String? statusMessage,
  }) {
    final isMobile = DashboardLayout.isMobile(context);
    return _buildPassengerMetricPanel(
      isMobile: isMobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: canSend ? _showEmergencyAlertDialog : null,
              icon: const Icon(Icons.notifications_active, size: 22),
              label: const Text(
                'Send Emergency Alert',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                disabledForegroundColor: Colors.white70,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Use Only in Case of Absolute Emergency',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.schedule, color: Colors.blueGrey[700], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusMessage,
                      style: TextStyle(fontSize: 13, color: Colors.blueGrey[800]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverAlertnessCard() {
    return Container(
      padding: const EdgeInsets.all(24),
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
              const Text(
                'Driver Alertness',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              Icon(Icons.visibility_outlined, color: Colors.grey[400], size: 20),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _driverAlertness.toStringAsFixed(13),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Good',
              style: TextStyle(
                color: Color(0xFFFFA726),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _driverAlertness / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFFE0E0E0),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildSafetyStatusCard() {
    return Container(
      padding: const EdgeInsets.all(24),
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
              const Text(
                'Safety Status',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              Icon(Icons.shield_outlined, color: Colors.grey[400], size: 20),
            ],
          ),
          const SizedBox(height: 20),
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
              const Text(
                'Safe',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'All systems active',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return constraints.maxWidth < 900
            ? Column(
                children: [
                  _buildDriverAlertnessTrend(),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildDriverAlertnessTrend()),
                ],
              );
      },
    );
  }

  Widget _buildDriverAlertnessTrend() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final driverId = _lookupDriverId;
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live Driver Status',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Real-time alertness and drowsiness indicators',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          if (driverId == null || driverId.isEmpty)
            Text(
              'Search by license plate to view live status',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            )
          else
            StreamBuilder<Map<String, dynamic>>(
              stream: _monitoringService.getCurrentStats(driverId),
              builder: (context, snapshot) {
                final hasLive = snapshot.hasData && (snapshot.data?.isNotEmpty == true);
                if (!hasLive) {
                  return const Text(
                    'Driver is not active',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  );
                }
                final data = snapshot.data!;
                final drowsy = data['drowsinessDetected'] == true;
                final lastUpdateMs = data['lastUpdate'] as int?;
                String lastText = '';
                if (lastUpdateMs != null) {
                  final dt = DateTime.fromMillisecondsSinceEpoch(lastUpdateMs);
                  lastText = 'Last update: ${dt.toLocal().toString().split(".").first}';
                }
                final color = drowsy ? AppColors.danger : AppColors.success;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          drowsy ? Icons.warning_amber : Icons.check_circle,
                          color: color,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          drowsy ? 'Drowsy' : 'Normal',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
                        ),
                      ],
                    ),
                    if (lastText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(lastText, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  /// Trip details shown under Find Vehicle after a plate search.
  Widget _buildFindVehicleTripInfo() => _buildTripInformation();

  Widget _buildTripInformation() {
    final driverId = _lookupDriverId;
    final vehicleId = _lookupVehicle?.id;
    final isMobile = DashboardLayout.isMobile(context);
    return _buildPassengerMetricPanel(
      isMobile: isMobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_outlined, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              const Text(
                'Trip Information',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Current vehicle monitoring details',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (driverId == null || driverId.isEmpty)
            const Text(
              'Search by license plate to view live trip information.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            )
          else
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('drivers').doc(driverId).snapshots(),
              builder: (context, driverSnapshot) {
                final driverData = driverSnapshot.data?.data() as Map<String, dynamic>?;
                final driverStatus = driverData?['status'] as String?;
                final isMonitoring = driverStatus == 'on_trip';
                
                if (!isMonitoring) {
                  return const Text(
                    'No active monitoring session. Trip information appears when the driver starts monitoring.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                  );
                }
                
                // Driver is monitoring - show trip info
                return StreamBuilder<Map<String, dynamic>>(
                  stream: _monitoringService.getCurrentStats(driverId),
                  builder: (context, statsSnap) {
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: vehicleId == null
                          ? null
                          : _firestore.collection('vehicles').doc(vehicleId).snapshots(),
                      builder: (context, vehicleSnap) {
                        final stats = statsSnap.data ?? {};
                        final vehicleData = vehicleSnap.data?.data() ?? {};
                        final currentAlerts = (stats['drowsinessDetected'] == true) ? 1 : 0;
                        final avgAlertness = (stats['alertness'] as num?)?.toDouble() ?? 0.0;
                        final started = _lookupStartedAt;
                        final drivingMinutes = started == null ? 0 : DateTime.now().difference(started).inMinutes;
                        final location = vehicleData['location'] as String? ?? '';
                        final liveMake = vehicleData['make'] as String? ?? _lookupVehicle?.make ?? '';
                        final liveModel = vehicleData['model'] as String? ?? _lookupVehicle?.model ?? '';
                        final vehicleLabel =
                            '$liveMake $liveModel'.trim().isEmpty ? 'N/A' : '$liveMake $liveModel';
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildPassengerMetricChip('Vehicle', vehicleLabel, compact: true),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildPassengerMetricChip(
                                    'Current Alerts',
                                    '$currentAlerts',
                                    valueColor: currentAlerts > 0 ? AppColors.danger : AppColors.success,
                                    compact: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildPassengerMetricChip(
                                    'Driving Minutes',
                                    '$drivingMinutes',
                                    compact: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildPassengerMetricChip(
                                    'Avg Alertness',
                                    '${avgAlertness.toStringAsFixed(1)}%',
                                    compact: true,
                                  ),
                                ),
                              ],
                            ),
                            if (location.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _buildPassengerMetricChip('Current Location', location, compact: true),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  // Show confirmation dialog
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('End Ride'),
                                      content: const Text('Are you sure you want to end this ride? This will clear all trip information.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            // Clear the lookup data
                                            setState(() {
                                              _lookupVehicle = null;
                                              _lookupDriverId = null;
                                              _lookupStartedAt = null;
                                              _plateController.clear();
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Ride ended successfully'),
                                                backgroundColor: AppColors.primary,
                                              ),
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('End Ride'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.stop_circle_outlined),
                                label: const Text('End Ride'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          ],
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

  Widget _buildEmergency() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return _passengerPageShell(
      title: 'Emergency Services',
      subtitle: 'Quick access to emergency services and contacts',
      child: _buildEmergencyContent(isMobile),
    );
  }

  Widget _buildPassengerEmergencyServicesGrid(bool isMobile) {
    final police = _buildEmergencyServiceCard(
      'Police', '15', Icons.local_police_outlined, AppColors.police, AppColors.policeLight, isMobile,
    );
    final ambulance = _buildEmergencyServiceCard(
      'Ambulance', '1122', Icons.local_hospital_outlined, AppColors.ambulance, AppColors.ambulanceLight, isMobile,
    );
    final fire = _buildEmergencyServiceCard(
      'Fire Department', '16', Icons.local_fire_department_outlined, AppColors.fire, AppColors.fireLight, isMobile,
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
        _buildPassengerSectionCard(
          isMobile: isMobile,
          icon: Icons.emergency_outlined,
          title: 'Emergency Services',
          subtitle: 'One-tap access to local emergency helplines',
          child: _buildPassengerEmergencyServicesGrid(isMobile),
        ),
        SizedBox(height: isMobile ? 14 : 18),
        _buildPassengerSectionCard(
          isMobile: isMobile,
          icon: Icons.contacts_outlined,
          title: 'Emergency Contacts',
          subtitle: 'Manage people notified during critical alerts',
          child: _buildEmergencyContactsContent(isMobile),
        ),
      ],
    );
  }

  Widget _buildEmergencyServiceCard(String title, String number, IconData icon, Color color, Color bgColor, [bool isMobile = false]) {
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

  Widget _buildEmergencyContactsContent([bool isMobile = false]) {
    return StreamBuilder<List<EmergencyContact>>(
      stream: _emergencyContactsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Error loading contacts: ${snapshot.error}',
            style: const TextStyle(color: AppColors.danger),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }

        final contacts = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _showContactDialog(context: context),
                icon: Icon(Icons.person_add_outlined, size: isMobile ? 18 : 20),
                label: Text('Add Contact', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 14 : 20,
                    vertical: isMobile ? 10 : 12,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            SizedBox(height: isMobile ? 14 : 18),
            isMobile
                ? contacts.isEmpty
                    ? _buildPassengerContactsEmptyState(isMobile)
                    : Column(
                        children: contacts
                            .map((contact) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildPassengerMobileContactCard(contact),
                                ))
                            .toList(),
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
                            color: AppColors.primaryLight.withValues(alpha: 0.35),
                          ),
                          children: [
                            _buildTableHeader('Name'),
                            _buildTableHeader('Relationship'),
                            _buildTableHeader('Contact'),
                            _buildTableHeader('Priority'),
                            _buildTableHeader('Methods'),
                            _buildTableHeader('Status'),
                            _buildTableHeader('Actions'),
                          ],
                        ),
                        ...contacts.map((contact) => _buildEmergencyContactRow(contact)),
                      ],
                    ),
                  ),
            if (contacts.isNotEmpty) ...[
              SizedBox(height: isMobile ? 12 : 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${contacts.length} contact${contacts.length == 1 ? '' : 's'} ready for emergency notifications',
                        style: TextStyle(fontSize: isMobile ? 12 : 13, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPassengerContactsEmptyState(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 24 : 32),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.contact_phone_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'No emergency contacts yet',
            style: TextStyle(
              fontSize: isMobile ? 15 : 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add someone to notify during critical alerts',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerMobileContactCard(EmergencyContact contact) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
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
              _buildContactActionsCell(contact),
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
              Expanded(
                child: Text(
                  contact.phone,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          if (contact.email.isNotEmpty) ...[
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
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildCompactPriorityChip(contact.priority),
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: contact.enabled,
                onChanged: (value) async {
                  try {
                    await _emergencyContactService.toggleContactEnabled(contact.id, value);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                activeColor: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactPriorityChip(String priority) {
    final isPrimary = priority == 'primary';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPrimary ? Colors.red : const Color(0xFFFF6F00),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        priority,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildContactInfoCell(String phone, String email) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phone,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              email,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriorityBadgeCell(String priority) {
    final isPrimary = priority == 'primary';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.red : const Color(0xFFFF6F00),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          priority,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  TableRow _buildEmergencyContactRow(EmergencyContact contact) {
    return TableRow(
      children: [
        _buildTableCell(contact.name),
        _buildTableCell(contact.relationship),
        _buildContactInfoCell(contact.phone, contact.email),
        _buildPriorityBadgeCell(contact.priority),
        _buildMethodsCell(contact.methods),
        _buildStatusToggleCell(contact),
        _buildContactActionsCell(contact),
      ],
    );
  }

  Widget _buildMethodsCell(List<dynamic> methods) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (methods.contains('call'))
            Icon(Icons.phone, size: 18, color: Colors.green[600]),
          if (methods.contains('call')) const SizedBox(width: 6),
          if (methods.contains('sms'))
            Icon(Icons.message, size: 18, color: Colors.blue[600]),
          if (methods.contains('sms')) const SizedBox(width: 6),
          if (methods.contains('email'))
            Icon(Icons.email, size: 18, color: Colors.grey[600]),
        ],
      ),
    );
  }

  Widget _buildStatusToggleCell(EmergencyContact contact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Switch(
        value: contact.enabled,
        onChanged: (value) async {
          try {
            await _emergencyContactService.toggleContactEnabled(contact.id, value);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            }
          }
        },
        activeColor: AppColors.primary,
      ),
    );
  }

  Widget _buildContactActionsCell(EmergencyContact contact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () {
              _showContactDialog(context: context, contact: contact);
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
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
                      SnackBar(content: Text('Error: $e')),
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

  void _showBuzzerDialog() async {
    if (_plateController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a license plate first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final vehicleToAlert = _lookupVehicle;
    if (vehicleToAlert == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matching vehicle found for this plate.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Get driver's emergency contacts
    final driverId = vehicleToAlert.assignedDriverId;
    List<EmergencyContact> emergencyContacts = [];
    if (driverId == null || driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active driver found for this vehicle.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final hasActiveSession = await _monitoringService.hasActiveSession(driverId);
    if (!hasActiveSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert not sent because monitoring session is not active.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (driverId.isNotEmpty) {
      try {
        final contactsSnapshot = await _firestore
            .collection('emergencyContacts')
            .where('userId', isEqualTo: driverId)
            .where('enabled', isEqualTo: true)
            .orderBy('priority', descending: true)
            .get();
        
        emergencyContacts = contactsSnapshot.docs
            .map((doc) => EmergencyContact.fromMap({'id': doc.id, ...doc.data()}))
            .toList();
      } catch (e) {
        print('Error fetching emergency contacts: $e');
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send emergency alert?'),
        content: Text(
          emergencyContacts.isNotEmpty
              ? 'This will notify the assigned driver, vehicle owner, admins, and ${emergencyContacts.length} emergency contact(s) immediately.'
              : 'This will notify the assigned driver, vehicle owner and admins immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final vehicle = vehicleToAlert;
              if (vehicle == null) return;
              
              // Send alert to Firestore
              await _firestore.collection('passenger_alerts').add({
                'passengerId': widget.user.id,
                'passengerName': widget.user.fullName,
                'vehicleId': vehicle.id,
                'licensePlate': vehicle.licensePlate,
                'driverId': vehicle.assignedDriverId,
                'ownerId': vehicle.ownerId,
                'targetRoles': ['driver', 'owner', 'admin'],
                'createdAt': FieldValue.serverTimestamp(),
                'status': 'new',
              });
              
              // Call primary emergency contact if available
              if (emergencyContacts.isNotEmpty) {
                final primaryContact = emergencyContacts.first;
                if (primaryContact.methods.contains('call') && primaryContact.phone.isNotEmpty) {
                  try {
                    final uri = Uri.parse('tel:${primaryContact.phone}');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  } catch (e) {
                    print('Error launching phone call: $e');
                  }
                }
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    emergencyContacts.isNotEmpty
                        ? 'Emergency alert sent and calling ${emergencyContacts.first.name}'
                        : 'Emergency alert sent to driver, owner and admin'
                  ),
                  backgroundColor: AppColors.primaryDark,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );
  }

  static const List<String> _emergencyCategories = [
    'Driver Not Responding',
    'Car Issue',
    'Tyre Issue',
    'Medical Emergency',
    'Over Speeding',
    'Other',
  ];

  // Emergency alert dialog with category selection and confirmation
  void _showEmergencyAlertDialog() async {
    final vehicle = _lookupVehicle;
    final driverId = _lookupDriverId;
    
    if (vehicle == null || driverId == null || driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please search for a vehicle first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final hasActiveSession = await _monitoringService.hasActiveSession(driverId);
    if (!hasActiveSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot Send alert: the driver has not started a monitoring session yet.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // Get vehicle owner info
    String? ownerId;
    String? ownerName;
    if (vehicle.ownerId != null && vehicle.ownerId!.isNotEmpty) {
      try {
        final ownerDoc = await _firestore.collection('users').doc(vehicle.ownerId).get();
        if (ownerDoc.exists) {
          final ownerData = ownerDoc.data();
          ownerId = vehicle.ownerId;
          ownerName = '${ownerData?['firstName'] ?? ''} ${ownerData?['lastName'] ?? ''}'.trim();
        }
      } catch (e) {
        print('Error fetching owner info: $e');
      }
    }

    // Get driver name
    String driverName = vehicle.driverName ?? 'Unknown Driver';

    final scaffoldContext = context;
    String selectedCategory = _emergencyCategories.first;

    await showDialog<void>(
      context: scaffoldContext,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Emergency Alert',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is for ABSOLUTE EMERGENCIES ONLY',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Emergency type',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._emergencyCategories.map((cat) => RadioListTile<String>(
              value: cat,
              groupValue: selectedCategory,
              onChanged: (v) {
                if (v != null) setDialogState(() => selectedCategory = v);
              },
              title: Text(cat, style: const TextStyle(fontSize: 14)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
            )),
            const SizedBox(height: 12),
            const Text(
              'This alert will immediately notify:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildAlertRecipient(Icons.person, 'Driver', driverName),
            if (ownerName != null && ownerName.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildAlertRecipient(Icons.business, 'Vehicle Owner', ownerName),
            ],
            const SizedBox(height: 8),
            _buildAlertRecipient(Icons.admin_panel_settings, 'System Admin', 'All administrators'),
            const SizedBox(height: 16),
            Text(
              'Vehicle: ${vehicle.make} ${vehicle.model} (${vehicle.licensePlate})',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final category = selectedCategory;
              Navigator.pop(dialogContext);

              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!scaffoldContext.mounted) return;

                showDialog<void>(
                  context: scaffoldContext,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.red),
                            SizedBox(height: 16),
                            Text('Sending emergency alert...'),
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                try {
                  await _emergencyAlertService.sendEmergencyAlert(
                    passengerId: widget.user.id,
                    passengerName: widget.user.fullName.trim().isEmpty
                        ? widget.user.email
                        : widget.user.fullName.trim(),
                    driverId: driverId,
                    driverName: driverName,
                    vehiclePlate: vehicle.licensePlate,
                    vehicleMake: vehicle.make,
                    vehicleModel: vehicle.model,
                    category: category,
                    ownerId: ownerId,
                    ownerName: ownerName,
                  ).timeout(const Duration(seconds: 40));

                  if (scaffoldContext.mounted) {
                    Navigator.of(scaffoldContext).pop();
                  }
                  if (scaffoldContext.mounted) {
                    final plate = vehicle.licensePlate;
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Emergency alert ($category) sent for plate $plate. Driver, owner, and admins were notified.',
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                } on TimeoutException catch (_) {
                  if (scaffoldContext.mounted) {
                    Navigator.of(scaffoldContext).pop();
                  }
                  if (scaffoldContext.mounted) {
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Sending the alert timed out. Check internet, Firebase Console rules for emergency_alerts, and redeploy updated rules.',
                        ),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 6),
                      ),
                    );
                  }
                } catch (e) {
                  if (scaffoldContext.mounted) {
                    Navigator.of(scaffoldContext).pop();
                  }
                  if (scaffoldContext.mounted) {
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text('Failed to send alert: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('SEND EMERGENCY ALERT'),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildAlertRecipient(IconData icon, String role, String name) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$role: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _showContactDialog({required BuildContext context, EmergencyContact? contact}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: contact?.name ?? '');
    final relationshipController = TextEditingController(text: contact?.relationship ?? '');
    final phoneController = TextEditingController(text: contact?.phone ?? '');
    final emailController = TextEditingController(text: contact?.email ?? '');
    String priority = contact?.priority ?? 'primary';
    final methods = Set<String>.from(contact?.methods ?? <String>{'call'});
    bool enabled = contact?.enabled ?? true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(contact == null ? 'Add Contact' : 'Edit Contact'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: relationshipController,
                      decoration: const InputDecoration(labelText: 'Relationship'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email (optional)'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Priority:'),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: priority,
                          items: const [
                            DropdownMenuItem(value: 'primary', child: Text('Primary')),
                            DropdownMenuItem(value: 'secondary', child: Text('Secondary')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => priority = val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Checkbox(
                              value: methods.contains('call'),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) { methods.add('call'); } else { methods.remove('call'); }
                                });
                              },
                            ),
                            const Text('Call'),
                          ]),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Checkbox(
                              value: methods.contains('sms'),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) { methods.add('sms'); } else { methods.remove('sms'); }
                                });
                              },
                            ),
                            const Text('SMS'),
                          ]),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Checkbox(
                              value: methods.contains('email'),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) { methods.add('email'); } else { methods.remove('email'); }
                                });
                              },
                            ),
                            const Text('Email'),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Enabled'),
                        const SizedBox(width: 12),
                        Switch(
                          value: enabled,
                          onChanged: (val) {
                            setDialogState(() => enabled = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState?.validate() != true) return;
                  if (methods.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Select at least one method'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  
                  Navigator.pop(ctx);
                  
                  try {
                    if (contact == null) {
                      await _emergencyContactService.addEmergencyContact(
                        userId: widget.user.id,
                        userRole: 'Passenger',
                        contactData: {
                          'name': nameController.text.trim(),
                          'relationship': relationshipController.text.trim(),
                          'phone': phoneController.text.trim(),
                          'email': emailController.text.trim(),
                          'priority': priority,
                          'methods': methods.toList(),
                          'enabled': enabled,
                        },
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Contact added'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      }
                    } else {
                      await _emergencyContactService.updateEmergencyContact(
                        contactId: contact.id,
                        contactData: {
                          'name': nameController.text.trim(),
                          'relationship': relationshipController.text.trim(),
                          'phone': phoneController.text.trim(),
                          'email': emailController.text.trim(),
                          'priority': priority,
                          'methods': methods.toList(),
                          'enabled': enabled,
                        },
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Contact updated'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: Text(contact == null ? 'Add' : 'Save'),
              ),
            ],
          );
        }
      ),
    );
  }
}

class AlertnessTrendPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    // Vertical grid lines
    for (int i = 0; i <= 6; i++) {
      double x = (size.width / 6) * i;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    // Horizontal grid lines
    for (int i = 0; i <= 4; i++) {
      double y = (size.height / 4) * i;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Sample data points (declining trend)
    final points = [
      Offset(size.width * 0.05, size.height * 0.1),
      Offset(size.width * 0.25, size.height * 0.2),
      Offset(size.width * 0.45, size.height * 0.35),
      Offset(size.width * 0.65, size.height * 0.5),
      Offset(size.width * 0.80, size.height * 0.6),
      Offset(size.width * 0.95, size.height * 0.7),
    ];

    // Draw line connecting points
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);

    // Draw dots at each point
    for (var point in points) {
      canvas.drawCircle(point, 5, dotPaint);
    }

    // Draw axis labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Y-axis labels
    final yLabels = ['100', '90', '80', '70', '60'];
    for (int i = 0; i < yLabels.length; i++) {
      textPainter.text = TextSpan(
        text: yLabels[i],
        style: const TextStyle(color: Colors.black54, fontSize: 12),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(-40, (size.height / 4) * i - 6),
      );
    }

    // X-axis labels (time)
    final xLabels = ['14:00', '14:15', '14:30', '14:45', '15:00', '15:15'];
    for (int i = 0; i < xLabels.length; i++) {
      textPainter.text = TextSpan(
        text: xLabels[i],
        style: const TextStyle(color: Colors.black54, fontSize: 11),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset((size.width / 6) * i - 15, size.height + 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}