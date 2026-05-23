import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../constants/app_colors.dart';
import '../widgets/shared/app_sidebar.dart';
import '../widgets/shared/live_map.dart';
import '../screens/notifications_inbox_screen.dart';
import '../services/user_notifications_service.dart';
import '../services/driver_document_submission_service.dart';
import '../models/driver_document_submission.dart';
import '../services/owner_vehicle_submission_service.dart';
import '../models/owner_vehicle_submission.dart';
import '../utils/sign_out_flow.dart';
import '../widgets/email_verified_guard.dart';
import '../widgets/mobile_drawer_menu_button.dart';
import '../widgets/dashboard_detail_dialog_theme.dart';
import '../services/monitoring_service.dart';
import '../utils/dashboard_responsive.dart';
import '../constants/vehicle_catalog.dart';
import 'package:url_launcher/url_launcher.dart';

bool adminLiveMetricsCritical(Map<String, dynamic> stats) =>
    MonitoringService.currentStatsCritical(stats);

String _adminDriverSetFingerprint(List<Map<String, dynamic>> vehicles) {
  final ids = vehicles
      .map((v) => v['assignedDriverId'] as String? ?? '')
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return ids.join('|');
}

String _adminVehicleEffectiveStatus(
  Map<String, dynamic> vehicle,
  Map<String, Map<String, dynamic>> liveByDriver,
) {
  final assignedDriverId = vehicle['assignedDriverId'] as String?;
  final hasDriver = assignedDriverId != null && assignedDriverId.isNotEmpty;
  if (!hasDriver) return 'Offline';
  final live = liveByDriver[assignedDriverId!] ?? MonitoringService.inactiveVehicleLiveSummary;
  final active = live['active'] == true;
  final critical = live['critical'] == true;
  if (active && critical) return 'Critical';
  if (active) return 'Active';
  return 'Offline';
}

int _adminVehicleEffectiveAlertness(
  Map<String, dynamic> vehicle,
  Map<String, Map<String, dynamic>> liveByDriver,
) {
  final assignedDriverId = vehicle['assignedDriverId'] as String?;
  if (assignedDriverId == null || assignedDriverId.isEmpty) return 0;
  final live = liveByDriver[assignedDriverId] ?? MonitoringService.inactiveVehicleLiveSummary;
  if (live['active'] != true) return 0;
  final a = live['alertness'];
  if (a is num) return a.round().clamp(0, 100);
  return 0;
}

List<Map<String, dynamic>> _adminFilterVehiclesByLiveStatus(
  List<Map<String, dynamic>> vehicles,
  String filter,
  Map<String, Map<String, dynamic>> liveByDriver,
) {
  if (filter == 'All Statuses') return vehicles;
  return vehicles
      .where((v) =>
          _adminVehicleEffectiveStatus(v, liveByDriver).toLowerCase() ==
          filter.toLowerCase())
      .toList();
}

typedef _VehicleLiveTableBuilder = Widget Function(
  BuildContext context,
  Map<String, Map<String, dynamic>> liveByDriver,
);

class _VehicleLiveSubscriptionHost extends StatefulWidget {
  const _VehicleLiveSubscriptionHost({
    required this.vehicles,
    required this.monitoringService,
    required this.builder,
  });

  final List<Map<String, dynamic>> vehicles;
  final MonitoringService monitoringService;
  final _VehicleLiveTableBuilder builder;

  @override
  State<_VehicleLiveSubscriptionHost> createState() => _VehicleLiveSubscriptionHostState();
}

class _VehicleLiveSubscriptionHostState extends State<_VehicleLiveSubscriptionHost> {
  final Map<String, StreamSubscription<Map<String, dynamic>>> _subscriptions = {};
  Map<String, Map<String, dynamic>> _liveByDriver = {};

  void _syncSubscriptions() {
    final needed = widget.vehicles
        .map((v) => v['assignedDriverId'] as String?)
        .whereType()
        .where((id) => id.isNotEmpty)
        .toSet();

    var changed = false;
    for (final id in _subscriptions.keys.toList()) {
      if (!needed.contains(id)) {
        _subscriptions[id]!.cancel();
        _subscriptions.remove(id);
        _liveByDriver.remove(id);
        changed = true;
      }
    }
    for (final id in needed) {
      if (_subscriptions.containsKey(id)) continue;
      _subscriptions[id] = widget.monitoringService.watchVehicleLiveSummary(id).listen((data) {
        if (!mounted) return;
        setState(() {
          _liveByDriver = {..._liveByDriver, id: data};
        });
      });
    }
    if (changed && mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _syncSubscriptions();
  }

  @override
  void didUpdateWidget(covariant _VehicleLiveSubscriptionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_adminDriverSetFingerprint(widget.vehicles) !=
        _adminDriverSetFingerprint(oldWidget.vehicles)) {
      _syncSubscriptions();
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions.values) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _liveByDriver);
  }
}

class AdminDashboard extends StatefulWidget {
  final User user;

  const AdminDashboard({Key? key, required this.user}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  final MonitoringService _monitoringService = MonitoringService();

  List<MenuItem> get _sidebarMenuItems => [
        const MenuItem(
          section: 'Overview',
          icon: Icons.dashboard_outlined,
          title: 'Statistics',
        ),
        const MenuItem(
          section: 'Overview',
          icon: Icons.map_outlined,
          title: 'Live Map',
        ),
        const MenuItem(
          section: 'Users',
          icon: Icons.tune_outlined,
          title: 'User Filters',
        ),
        const MenuItem(
          section: 'Users',
          icon: Icons.people_outline,
          title: 'User Registry',
        ),
        const MenuItem(
          section: 'Vehicles',
          icon: Icons.tune_outlined,
          title: 'Vehicle Filters',
        ),
        const MenuItem(
          section: 'Vehicles',
          icon: Icons.directions_car_filled_outlined,
          title: 'Vehicle Registry',
        ),
        const MenuItem(
          section: 'Management',
          icon: Icons.history,
          title: 'Activity',
        ),
        const MenuItem(
          section: 'Management',
          icon: Icons.verified_user_outlined,
          title: 'Documents',
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
        return _buildAdminStatsPage();
      case 1:
        return _buildAdminLiveMapPage();
      case 2:
        return _buildAdminUserFiltersPage();
      case 3:
        return _buildAdminUserRegistryPage();
      case 4:
        return _buildAdminVehicleFiltersPage();
      case 5:
        return _buildAdminVehicleRegistryPage();
      case 6:
        return _buildAdminActivityPage();
      case 7:
        return _buildAdminDocumentsPage();
      case 8:
        return _adminPageShell(
          child: NotificationsInboxScreen(user: widget.user, embedded: true),
        );
      default:
        return _buildAdminStatsPage();
    }
  }

  String get _currentPageTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Statistics';
      case 1:
        return 'Live Map';
      case 2:
        return 'User Filters';
      case 3:
        return 'User Registry';
      case 4:
        return 'Vehicle Filters';
      case 5:
        return 'Vehicle Registry';
      case 6:
        return 'Activity';
      case 7:
        return 'Documents';
      case 8:
        return 'Notifications';
      default:
        return 'Statistics';
    }
  }

  String get _currentPageSubtitle {
    switch (_selectedIndex) {
      case 0:
        return 'Real-time counts across users, vehicles, and alerts';
      case 1:
        return 'All active drivers on the map';
      case 2:
        return 'Search accounts and filter by role';
      case 3:
        return 'Browse accounts matching your user filters';
      case 4:
        return 'Search fleet records and filter by type or status';
      case 5:
        return 'Browse vehicles matching your fleet filters';
      case 6:
        return 'Latest system events and updates';
      case 7:
        return 'Review Driver CNIC/License and Owner Vehicle Submissions';
      case 8:
        return 'Alerts and system messages';
      default:
        return 'Real-time counts across users, vehicles, and alerts';
    }
  }

  Widget _adminPageShell({required Widget child}) {
    return DashboardLayout.scrollPage(context: context, child: child);
  }

  double _adminSectionSpacing(bool isMobile) => isMobile ? 20 : 28;

  Widget _adminSectionGap(bool isMobile) => SizedBox(height: _adminSectionSpacing(isMobile));

  InputDecoration _adminInputDecoration({
    required String hintText,
    IconData? prefixIcon,
    Widget? suffixIcon,
    bool isMobile = false,
  }) {
    final radius = BorderRadius.circular(12);
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(fontSize: isMobile ? 15 : 16, color: AppColors.textSecondary),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 24, color: AppColors.primary) : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: isMobile ? 16 : 18),
    );
  }

  Widget _buildAdminSectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    bool isMobile = false,
    String? subtitle,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 14,
            offset: const Offset(0, 5),
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
                padding: EdgeInsets.all(isMobile ? 12 : 14),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: isMobile ? 26 : 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: isMobile ? 13 : 15,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          SizedBox(height: isMobile ? 20 : 24),
          child,
        ],
      ),
    );
  }

  Widget _buildAdminMetricPanel({required Widget child, bool isMobile = false}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: child,
    );
  }

  Widget _buildAdminOptionBlock({
    required String label,
    required Widget child,
    bool isMobile = false,
    String? hint,
    IconData? icon,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppColors.primary, size: isMobile ? 22 : 26),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              style: TextStyle(
                fontSize: isMobile ? 13 : 14,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          SizedBox(height: isMobile ? 14 : 18),
          child,
        ],
      ),
    );
  }

  Widget _buildAdminSeparatedOptions({
    required List<Widget> options,
    bool isMobile = false,
  }) {
    if (options.isEmpty) return const SizedBox.shrink();
    if (options.length == 1) return options.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) SizedBox(height: isMobile ? 16 : 20),
          options[i],
        ],
      ],
    );
  }

  Widget _buildAdminMetricChip(String label, String value, {Color? valueColor, bool large = true}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: large ? 18 : 14, vertical: large ? 18 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: large ? 13 : 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: large ? 8 : 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: large ? 28 : 20,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.primary,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Color _adminFleetStatusColor(String option) {
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

  Widget _buildAdminRoleDropdown({
    required String value,
    required ValueChanged<String> onChanged,
    bool isMobile = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary, size: 28),
          style: TextStyle(
            fontSize: isMobile ? 16 : 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          items: ['All Roles', 'Admin', 'Driver', 'Owner', 'Passenger']
              .map((role) => DropdownMenuItem(value: role, child: Text(role)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _buildAdminUserTypeDropdown(bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _userTypeFilter,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary, size: 28),
          style: TextStyle(
            fontSize: isMobile ? 16 : 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          items: const [
            DropdownMenuItem(value: 'All Users', child: Text('All Users')),
            DropdownMenuItem(value: 'Drivers', child: Text('Drivers')),
            DropdownMenuItem(value: 'Owners', child: Text('Owners')),
            DropdownMenuItem(value: 'Passengers', child: Text('Passengers')),
          ],
          onChanged: (val) => setState(() => _userTypeFilter = val!),
        ),
      ),
    );
  }

  Widget _buildAdminVehicleTypeDropdown(bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _vehicleTypeFilter,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary, size: 28),
          style: TextStyle(
            fontSize: isMobile ? 16 : 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          items: ['All Types', 'Car', 'Bus', 'Van', 'Truck', 'Rickshaw']
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: VehicleCatalog.dropdownMenuLabel(
                    t,
                    iconColor: AppColors.primary.withValues(alpha: 0.85),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _vehicleTypeFilter = v);
          },
        ),
      ),
    );
  }

  Widget _buildAdminVehicleStatusDropdown(bool isMobile) {
    Widget statusRow(String option) {
      return Row(
        children: [
          Icon(Icons.circle, size: 14, color: _adminFleetStatusColor(option)),
          const SizedBox(width: 10),
          Expanded(child: Text(option)),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _vehicleStatusFilter,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary, size: 28),
          selectedItemBuilder: (context) => ['All Statuses', 'Active', 'Offline', 'Critical']
              .map((o) => Align(alignment: Alignment.centerLeft, child: statusRow(o)))
              .toList(),
          style: TextStyle(
            fontSize: isMobile ? 16 : 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          items: ['All Statuses', 'Active', 'Offline', 'Critical']
              .map((s) => DropdownMenuItem(value: s, child: statusRow(s)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _vehicleStatusFilter = v);
          },
        ),
      ),
    );
  }

  Widget _buildDesktopAdminHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentPageTitle,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentPageSubtitle,
                  style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: Icon(Icons.logout_rounded, color: AppColors.primary, size: 26),
            onPressed: () => performSignOutAndGoToAdminAuth(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminStatsPage() {
    final isMobile = DashboardLayout.isMobile(context);
    return _adminPageShell(
      child: _buildDynamicStatsSections(isMobile),
    );
  }

  Widget _buildAdminLiveMapPage() {
    final mapHeight = DashboardLayout.liveMapHeight(context) + (DashboardLayout.isMobile(context) ? 40 : 80);
    return _adminPageShell(
      child: _buildStaggeredItem(
        SizedBox(
          height: mapHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LiveMap(
              showHeader: true,
              height: mapHeight,
            ),
          ),
        ),
        0,
      ),
    );
  }

  Widget _buildAdminUserFiltersPage() {
    return _adminPageShell(child: _buildUserFiltersSection());
  }

  Widget _buildAdminUserRegistryPage() {
    return _adminPageShell(child: _buildUserRegistrySection());
  }

  Widget _buildAdminVehicleFiltersPage() {
    return _adminPageShell(child: _buildVehicleFiltersSection());
  }

  Widget _buildAdminVehicleRegistryPage() {
    return _adminPageShell(child: _buildVehicleRegistrySection());
  }

  Widget _buildAdminActivityPage() {
    final isMobile = DashboardLayout.isMobile(context);
    return _adminPageShell(
      child: _buildStaggeredItem(
        _buildAdminSectionCard(
          isMobile: isMobile,
          icon: Icons.history,
          title: 'Recent Activity',
          subtitle: 'Latest system events and updates',
          child: _buildRecentActivitiesContent(),
        ),
        0,
      ),
    );
  }

  Widget _buildAdminDocumentsPage() {
    return _adminPageShell(child: _buildDocumentApproval());
  }
  String _selectedRoleFilter = 'All Roles';
  String _userTypeFilter = 'All Users';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _userSearchController = TextEditingController();
  String _userSearchQuery = '';

  // Vehicle management state
  final TextEditingController _vehicleSearchController = TextEditingController();
  String _vehicleSearchQuery = '';
  String _vehicleTypeFilter = 'All Types';
  String _vehicleStatusFilter = 'All Statuses';

  final DriverDocumentSubmissionService _driverDocumentSubmissionService = DriverDocumentSubmissionService();
  final OwnerVehicleSubmissionService _ownerVehicleSubmissionService = OwnerVehicleSubmissionService();
  String? _processingSubmissionId;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
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
    _fadeController.dispose();
    _slideController.dispose();
    _userSearchController.dispose();
    _vehicleSearchController.dispose();
    super.dispose();
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
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              _currentPageSubtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
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
              onPressed: () => performSignOutAndGoToAdminAuth(context),
            ),
          ),
        ],
      ) : null,
      body: EmailVerifiedGuard(
        enforceVerification: false,
        child: DashboardLayout.scaffoldBody(
          context: context,
          sidebar: _buildSidebar(),
          desktopHeader: _buildDesktopAdminHeader(),
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
          role: 'admin',
          user: widget.user,
          selectedIndex: _selectedIndex,
          onMenuItemTap: (index) {
            setState(() => _selectedIndex = index);
            Navigator.pop(context);
          },
          menuItems: _sidebarMenuItems,
          accentColor: AppColors.primary,
          accentLightColor: AppColors.primaryLight,
          adminPortal: true,
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return AppSidebar(
      role: 'admin',
      user: widget.user,
      selectedIndex: _selectedIndex,
      onMenuItemTap: (index) => setState(() => _selectedIndex = index),
      menuItems: _sidebarMenuItems,
      accentColor: AppColors.primary,
      accentLightColor: AppColors.primaryLight,
      adminPortal: true,
    );
  }


  Widget _buildStatCardContent(String title, String value, String subtitle,
      IconData icon, Color valueColor, Color subtitleColor, bool isMobile) {
    return _buildAdminSeparatedOptions(
      isMobile: isMobile,
      options: [
        _buildAdminOptionBlock(
          isMobile: isMobile,
          label: title,
          hint: subtitle,
          icon: icon,
          child: _buildAdminMetricChip('Count', value, valueColor: valueColor),
        ),
      ],
    );
  }

  // --- Dynamic Stats: separate section per metric ---
  Widget _buildDynamicStatsSections(bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, usersSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('vehicles').snapshots(),
          builder: (context, vehiclesSnapshot) {
            // Calculate user counts
            int totalUsers = 0;
            int driverCount = 0;
            int ownerCount = 0;
            int passengerCount = 0;

            if (usersSnapshot.hasData) {
              final users = usersSnapshot.data!.docs;
              totalUsers = users.length;
              for (var doc in users) {
                final data = doc.data() as Map<String, dynamic>;
                final roles = data['roles'] as List<dynamic>? ?? [];
                final activeRole = (data['activeRole'] as String? ?? data['role'] as String? ?? '').toLowerCase();
                if (roles.map((r) => r.toString().toLowerCase()).contains('driver') || activeRole == 'driver') driverCount++;
                if (roles.map((r) => r.toString().toLowerCase()).contains('owner') || activeRole == 'owner') ownerCount++;
                if (roles.map((r) => r.toString().toLowerCase()).contains('passenger') || activeRole == 'passenger') passengerCount++;
              }
            }

            final vehicleDocs = vehiclesSnapshot.hasData ? vehiclesSnapshot.data!.docs : <QueryDocumentSnapshot>[];

            // Determine display value based on dropdown
            String usersValue;
            String usersSubtitle;
            if (_userTypeFilter == 'Drivers') {
              usersValue = driverCount.toString();
              usersSubtitle = 'Registered drivers';
            } else if (_userTypeFilter == 'Owners') {
              usersValue = ownerCount.toString();
              usersSubtitle = 'Registered owners';
            } else if (_userTypeFilter == 'Passengers') {
              usersValue = passengerCount.toString();
              usersSubtitle = 'Registered passengers';
            } else {
              usersValue = totalUsers.toString();
              usersSubtitle = 'Registered users';
            }

            final isLoading = !usersSnapshot.hasData || !vehiclesSnapshot.hasData;
            var sectionIndex = 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStaggeredItem(
                  _buildAdminSectionCard(
                    isMobile: isMobile,
                    icon: Icons.people_outline,
                    title: 'User Statistics',
                    subtitle: 'Registered accounts by role',
                    child: _buildAdminSeparatedOptions(
                      isMobile: isMobile,
                      options: [
                        _buildAdminOptionBlock(
                          isMobile: isMobile,
                          label: 'User Type',
                          hint: 'Choose which user group to count',
                          icon: Icons.filter_alt_outlined,
                          child: _buildAdminUserTypeDropdown(isMobile),
                        ),
                        _buildAdminOptionBlock(
                          isMobile: isMobile,
                          label: 'Total Count',
                          hint: usersSubtitle,
                          icon: Icons.groups_outlined,
                          child: _buildAdminMetricChip(
                            'Users',
                            isLoading ? '...' : usersValue,
                            valueColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  sectionIndex++,
                ),
                _adminSectionGap(isMobile),
                _buildStaggeredItem(
                  _buildAdminSectionCard(
                    isMobile: isMobile,
                    icon: Icons.directions_car_filled_outlined,
                    title: 'Active Vehicles',
                    subtitle: 'Vehicles with live monitoring sessions',
                    child: _AdminLiveVehicleFleetMetrics(
                      vehicleDocs: vehicleDocs,
                      isLoading: isLoading,
                      isMobile: isMobile,
                      monitoringService: _monitoringService,
                      metricOnly: 'active',
                      statCardBuilder: _buildStatCardContent,
                    ),
                  ),
                  sectionIndex++,
                ),
                _adminSectionGap(isMobile),
                _buildStaggeredItem(
                  _buildAdminSectionCard(
                    isMobile: isMobile,
                    icon: Icons.warning_amber_rounded,
                    title: 'Critical Alerts',
                    subtitle: 'Vehicles in critical live condition',
                    child: _AdminLiveVehicleFleetMetrics(
                      vehicleDocs: vehicleDocs,
                      isLoading: isLoading,
                      isMobile: isMobile,
                      monitoringService: _monitoringService,
                      metricOnly: 'alerts',
                      statCardBuilder: _buildStatCardContent,
                    ),
                  ),
                  sectionIndex++,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showStatsDetailsDialog(String title, List<String> rows) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DashboardDetailDialogTheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(e),
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // --- Helper: Format time ago ---
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  Widget _buildUserSearchField(bool isMobile) {
    return TextField(
      controller: _userSearchController,
      style: TextStyle(fontSize: isMobile ? 16 : 17),
      decoration: _adminInputDecoration(
        hintText: 'Search by name or email...',
        prefixIcon: Icons.search,
        isMobile: isMobile,
        suffixIcon: _userSearchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 22),
                onPressed: () {
                  _userSearchController.clear();
                  setState(() => _userSearchQuery = '');
                },
              )
            : null,
      ),
      onChanged: (value) => setState(() => _userSearchQuery = value.trim()),
    );
  }

  Widget _buildUserFiltersSection() {
    final isMobile = DashboardLayout.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStaggeredItem(
          _buildAdminSectionCard(
            isMobile: isMobile,
            icon: Icons.tune_outlined,
            title: 'Search & filters',
            subtitle: 'Find accounts by name, email, or role',
            child: _buildAdminSeparatedOptions(
              isMobile: isMobile,
              options: [
                _buildAdminOptionBlock(
                  isMobile: isMobile,
                  label: 'Search query',
                  hint: 'Applied when you open User Registry in the sidebar',
                  icon: Icons.person_search_outlined,
                  child: _buildUserSearchField(isMobile),
                ),
                _buildAdminOptionBlock(
                  isMobile: isMobile,
                  label: 'Role',
                  hint: 'All roles or a specific account type',
                  icon: Icons.badge_outlined,
                  child: _buildAdminRoleDropdown(
                    value: _selectedRoleFilter,
                    onChanged: (v) => setState(() => _selectedRoleFilter = v),
                    isMobile: isMobile,
                  ),
                ),
              ],
            ),
          ),
          0,
        ),
        _adminSectionGap(isMobile),
        _buildStaggeredItem(
          _buildAdminRegistryNavHint(
            isMobile: isMobile,
            message: 'Open User Registry in the sidebar to view matching accounts.',
            buttonLabel: 'Go to User Registry',
            onOpenRegistry: () => setState(() => _selectedIndex = 3),
          ),
          1,
        ),
      ],
    );
  }

  Widget _buildUserRegistrySection() {
    final isMobile = DashboardLayout.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStaggeredItem(
          _buildAdminActiveFiltersBanner(
            isMobile: isMobile,
            filtersLabel: _userActiveFiltersLabel(),
            onEditFilters: () => setState(() => _selectedIndex = 2),
          ),
          0,
        ),
        _adminSectionGap(isMobile),
        _buildStaggeredItem(
          _buildAdminSectionCard(
            isMobile: isMobile,
            icon: Icons.people_outline,
            title: 'User registry',
            subtitle: 'Tap a user for details and actions',
            child: _buildUserTable(),
          ),
          1,
        ),
      ],
    );
  }

  String _userActiveFiltersLabel() {
    final parts = <String>[];
    if (_userSearchQuery.isNotEmpty) parts.add('Search: "$_userSearchQuery"');
    if (_selectedRoleFilter != 'All Roles') parts.add('Role: $_selectedRoleFilter');
    return parts.isEmpty ? 'No filters applied (showing all users)' : parts.join(' • ');
  }

  Widget _buildUserTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No users found', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        var users = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['docId'] = doc.id;
          return data;
        }).toList();

        // Apply role filter
        if (_selectedRoleFilter != 'All Roles') {
          final filterRole = _selectedRoleFilter.toLowerCase();
          users = users.where((data) {
            final roles = (data['roles'] as List<dynamic>?)?.map((r) => r.toString().toLowerCase()).toList() ?? [];
            final activeRole = (data['activeRole'] as String? ?? data['role'] as String? ?? '').toLowerCase();
            return roles.contains(filterRole) || activeRole == filterRole;
          }).toList();
        }

        // Apply search filter
        if (_userSearchQuery.isNotEmpty) {
          final query = _userSearchQuery.toLowerCase();
          users = users.where((data) {
            final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.toLowerCase();
            final email = (data['email'] as String? ?? '').toLowerCase();
            return name.contains(query) || email.contains(query);
          }).toList();
        }

        if (users.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No users match the current filters', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        return Column(
          children: users.map((user) {
            final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
            final activeRole = (user['activeRole'] as String? ?? user['role'] as String? ?? 'user').toLowerCase();
            final icon = activeRole == 'owner'
                ? Icons.business
                : activeRole == 'admin'
                    ? Icons.admin_panel_settings
                    : activeRole == 'passenger'
                        ? Icons.person
                        : Icons.drive_eta;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Icon(icon, color: AppColors.primary),
              ),
              title: Text(name.isNotEmpty ? name : 'Unknown User'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showUserQuickDetails(user),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMobileUserCard(Map<String, dynamic> user) {
    final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    final email = user['email'] as String? ?? '';
    final phone = user['phone'] as String? ?? '';
    final activeRole = user['activeRole'] as String? ?? user['role'] as String? ?? 'N/A';
    final isActive = user['isActive'] as bool? ?? true;
    final createdAt = user['createdAt'] is Timestamp
        ? (user['createdAt'] as Timestamp).toDate()
        : null;
    final joinedText = createdAt != null ? _formatTimeAgo(createdAt) : 'N/A';

    final roleColors = {
      'driver': const Color(0xFF4CAF50),
      'owner': const Color(0xFF2196F3),
      'admin': const Color(0xFF9C27B0),
    };
    final roleColor = roleColors[activeRole.toLowerCase()] ?? Colors.grey;

    final isMobile = DashboardLayout.isMobile(context);
    return InkWell(
      onTap: () => _showUserQuickDetails(user),
      borderRadius: BorderRadius.circular(12),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
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
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: roleColor.withOpacity(0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: roleColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : 'Unknown',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF4CAF50) : Colors.grey[400],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'Active' : 'Inactive',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildAdminMetricChip('Role', activeRole, valueColor: roleColor, large: false),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildAdminMetricChip(
                  'Status',
                  isActive ? 'Active' : 'Inactive',
                  valueColor: isActive ? AppColors.success : AppColors.textSecondary,
                  large: false,
                ),
              ),
            ],
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildAdminMetricChip('Phone', phone, large: false),
          ],
          const SizedBox(height: 10),
          _buildAdminMetricChip('Joined', joinedText, large: false),
        ],
      ),
    ));
  }



  Widget _buildRoleBadge(String role) {
    final colors = {
      'driver': const Color(0xFF4CAF50),
      'passenger': const Color(0xFFFF9800),
      'owner': const Color(0xFF2196F3),
      'admin': const Color(0xFF9C27B0),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors[role]!,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          role,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isActive = status == 'Active';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF4CAF50) : Colors.grey[400],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          status,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildUserActionsCell(Map<String, dynamic> user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF2196F3)),
            tooltip: 'Edit user',
            onPressed: () => _showEditUserDialog(user),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Delete user',
            onPressed: () => _confirmDeleteUser(user),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _showUserQuickDetails(Map<String, dynamic> user) async {
    final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    final email = user['email'] as String? ?? 'N/A';
    final phone = user['phone'] as String? ?? 'N/A';
    final role = user['activeRole'] as String? ?? user['role'] as String? ?? 'N/A';
    final roleLabel = role.isNotEmpty ? '${role[0].toUpperCase()}${role.substring(1)}' : 'N/A';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DashboardDetailDialogTheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(name.isNotEmpty ? name : 'User Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildQuickDetailCardRow(Icons.mail_outline, 'Email', email),
            const SizedBox(height: 10),
            _buildQuickDetailCardRow(Icons.phone_outlined, 'Phone', phone),
            const SizedBox(height: 10),
            _buildQuickDetailCardRow(Icons.person_outline, 'Role', roleLabel),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDeleteUser(user);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showEditUserDialog(user);
            },
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final docId = user['docId'] as String?;
    if (docId == null || docId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot edit: User ID not found'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final formKey = GlobalKey<FormState>();
    final firstNameCtrl = TextEditingController(text: user['firstName'] as String? ?? '');
    final lastNameCtrl = TextEditingController(text: user['lastName'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: user['phone'] as String? ?? '');
    String selectedRole = (user['activeRole'] as String? ?? user['role'] as String? ?? 'driver').toLowerCase();
    bool isActive = user['isActive'] as bool? ?? true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: DashboardDetailDialogTheme.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.edit, color: Color(0xFF2196F3), size: 22),
                SizedBox(width: 8),
                Text('Edit User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: firstNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'First Name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'First name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: lastNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Last Name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Last name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneCtrl,
                      decoration: InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: ['driver', 'owner', 'passenger', 'admin']
                          .map((r) => DropdownMenuItem(
                                value: r,
                                child: Text(r[0].toUpperCase() + r.substring(1)),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedRole = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Account Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        Switch(
                          value: isActive,
                          onChanged: (val) => setDialogState(() => isActive = val),
                          activeColor: const Color(0xFF4CAF50),
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
                  Navigator.pop(ctx);
                  try {
                    await _firestore.collection('users').doc(docId).update({
                      'firstName': firstNameCtrl.text.trim(),
                      'lastName': lastNameCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                      'activeRole': selectedRole,
                      'role': selectedRole,
                      'isActive': isActive,
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User updated successfully'), backgroundColor: Color(0xFF4CAF50)),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating user: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteUser(Map<String, dynamic> user) async {
    final docId = user['docId'] as String?;
    if (docId == null || docId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: User ID not found'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    final email = user['email'] as String? ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Delete User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete this user?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isNotEmpty ? name : 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (email.isNotEmpty)
                    Text(email, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone. All user data will be permanently removed.',
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

    if (confirm == true) {
      try {
        // Also remove user from any assigned vehicles
        final vehicleSnapshot = await _firestore.collection('vehicles')
            .where('assignedDriverId', isEqualTo: docId)
            .get();
        for (var vDoc in vehicleSnapshot.docs) {
          await vDoc.reference.update({
            'assignedDriverId': null,
            'assignedDriverEmail': null,
            'driverName': null,
            'status': 'Offline',
          });
        }

        await _firestore.collection('users').doc(docId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${name.isNotEmpty ? name : "User"} has been deleted'), backgroundColor: const Color(0xFF4CAF50)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting user: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildUserRoleDistribution() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        int driverCount = 0;
        int ownerCount = 0;
        int adminCount = 0;
        int totalCount = 0;

        if (snapshot.hasData) {
          totalCount = snapshot.data!.docs.length;
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final roles = (data['roles'] as List<dynamic>?)?.map((r) => r.toString().toLowerCase()).toList() ?? [];
            final activeRole = (data['activeRole'] as String? ?? data['role'] as String? ?? '').toLowerCase();
            if (roles.contains('driver') || activeRole == 'driver') driverCount++;
            if (roles.contains('owner') || activeRole == 'owner') ownerCount++;
            if (roles.contains('admin') || activeRole == 'admin') adminCount++;
          }
        }

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
                'User Role Distribution',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Breakdown of $totalCount registered users',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              if (!snapshot.hasData)
                const Center(child: CircularProgressIndicator())
              else ...[
                _buildRoleRow('Drivers', driverCount, const Color(0xFF4CAF50)),
                _buildRoleRow('Owners', ownerCount, const Color(0xFF2196F3)),
                _buildRoleRow('Admins', adminCount, const Color(0xFF9C27B0)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoleRow(String role, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            role,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitiesContent() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').orderBy('createdAt', descending: true).limit(3).snapshots(),
      builder: (context, usersSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('vehicles').orderBy('createdAt', descending: true).limit(3).snapshots(),
          builder: (context, vehiclesSnapshot) {
            // Build activity list from multiple sources
            final List<Map<String, dynamic>> activities = [];

            // User registrations
            if (usersSnapshot.hasData) {
              for (var doc in usersSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
                final activeRole = data['activeRole'] as String? ?? data['role'] as String? ?? 'user';
                final createdAt = data['createdAt'] is Timestamp
                    ? (data['createdAt'] as Timestamp).toDate()
                    : null;
                activities.add({
                  'type': 'user_registered',
                  'icon': Icons.person_add_outlined,
                  'title': name.isNotEmpty ? name : 'New User',
                  'subtitle': '${activeRole[0].toUpperCase()}${activeRole.substring(1)} registered',
                  'time': createdAt,
                  'color': activeRole.toLowerCase() == 'driver'
                      ? const Color(0xFF4CAF50)
                      : activeRole.toLowerCase() == 'owner'
                          ? const Color(0xFF2196F3)
                          : const Color(0xFF9C27B0),
                });
              }
            }

            // Vehicle additions
            if (vehiclesSnapshot.hasData) {
              for (var doc in vehiclesSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final make = data['make'] as String? ?? '';
                final model = data['model'] as String? ?? '';
                final plate = data['licensePlate'] as String? ?? '';
                final vType = data['type'] as String? ?? 'Car';
                final createdAt = data['createdAt'] is Timestamp
                    ? (data['createdAt'] as Timestamp).toDate()
                    : null;
                activities.add({
                  'type': 'vehicle_added',
                  'icon': VehicleCatalog.iconForType(vType),
                  'title': '$make $model'.trim().isNotEmpty ? '$make $model'.trim() : 'New Vehicle',
                  'subtitle': 'Vehicle added ${plate.isNotEmpty ? "• $plate" : ""}',
                  'time': createdAt,
                  'color': const Color(0xFFFF9800),
                });
              }
            }

            // Sort by time descending, nulls last
            activities.sort((a, b) {
              final aTime = a['time'] as DateTime?;
              final bTime = b['time'] as DateTime?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });

            // Take only first 5
            final recentActivities = activities.take(5).toList();

            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!usersSnapshot.hasData && !vehiclesSnapshot.hasData)
                    const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  else if (recentActivities.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.history, size: 40, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text('No recent activities', style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    )
                  else
                    ...recentActivities.map((activity) {
                      final timeText = activity['time'] != null
                          ? _formatTimeAgo(activity['time'] as DateTime)
                          : 'Unknown';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildActivityItem(
                          activity['icon'] as IconData,
                          activity['title'] as String,
                          '${activity['subtitle']} • $timeText',
                          activity['color'] as Color,
                        ),
                      );
                    }),
                ],
            );
          },
        );
      },
    );
  }

  Widget _buildActivityItem(IconData icon, String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 26, color: color),
          ),
          const SizedBox(width: 16),
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
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =============================================
  // VEHICLE MANAGEMENT SECTION
  // =============================================
  Widget _buildVehicleSearchField(bool isMobile) {
    return TextField(
      controller: _vehicleSearchController,
      style: TextStyle(fontSize: isMobile ? 16 : 17),
      decoration: _adminInputDecoration(
        hintText: 'Search plate, make, model, driver...',
        prefixIcon: Icons.search,
        isMobile: isMobile,
        suffixIcon: _vehicleSearchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 22),
                onPressed: () {
                  _vehicleSearchController.clear();
                  setState(() => _vehicleSearchQuery = '');
                },
              )
            : null,
      ),
      onChanged: (value) => setState(() => _vehicleSearchQuery = value.trim()),
    );
  }

  Widget _buildVehicleFiltersSection() {
    final isMobile = DashboardLayout.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStaggeredItem(
          _buildAdminSectionCard(
            isMobile: isMobile,
            icon: Icons.tune_outlined,
            title: 'Search & filters',
            subtitle: 'Find fleet records by plate, details, type, or live status',
            child: _buildAdminSeparatedOptions(
              isMobile: isMobile,
              options: [
                _buildAdminOptionBlock(
                  isMobile: isMobile,
                  label: 'Search query',
                  hint: 'Applied when you open Vehicle Registry in the sidebar',
                  icon: Icons.search,
                  child: _buildVehicleSearchField(isMobile),
                ),
                _buildAdminOptionBlock(
                  isMobile: isMobile,
                  label: 'Vehicle type',
                  hint: 'Car, bus, van, truck, or rickshaw',
                  icon: VehicleCatalog.iconForFilterOption(_vehicleTypeFilter),
                  child: _buildAdminVehicleTypeDropdown(isMobile),
                ),
                _buildAdminOptionBlock(
                  isMobile: isMobile,
                  label: 'Live status',
                  hint: 'Active, offline, or critical state',
                  icon: Icons.circle,
                  child: _buildAdminVehicleStatusDropdown(isMobile),
                ),
              ],
            ),
          ),
          0,
        ),
        _adminSectionGap(isMobile),
        _buildStaggeredItem(
          _buildAdminRegistryNavHint(
            isMobile: isMobile,
            message: 'Open Vehicle Registry in the sidebar to view matching fleet records.',
            buttonLabel: 'Go to Vehicle Registry',
            onOpenRegistry: () => setState(() => _selectedIndex = 5),
          ),
          1,
        ),
      ],
    );
  }

  Widget _buildVehicleRegistrySection() {
    final isMobile = DashboardLayout.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStaggeredItem(
          _buildAdminActiveFiltersBanner(
            isMobile: isMobile,
            filtersLabel: _vehicleActiveFiltersLabel(),
            onEditFilters: () => setState(() => _selectedIndex = 4),
          ),
          0,
        ),
        _adminSectionGap(isMobile),
        _buildStaggeredItem(
          _buildAdminSectionCard(
            isMobile: isMobile,
            icon: Icons.directions_car_filled_outlined,
            title: 'Vehicle registry',
            subtitle: 'Full fleet list with live metrics',
            child: _buildVehicleTable(),
          ),
          1,
        ),
      ],
    );
  }

  String _vehicleActiveFiltersLabel() {
    final parts = <String>[];
    if (_vehicleSearchQuery.isNotEmpty) parts.add('Search: "$_vehicleSearchQuery"');
    if (_vehicleTypeFilter != 'All Types') parts.add('Type: $_vehicleTypeFilter');
    if (_vehicleStatusFilter != 'All Statuses') parts.add('Status: $_vehicleStatusFilter');
    return parts.isEmpty ? 'No filters applied (showing all vehicles)' : parts.join(' • ');
  }

  Widget _buildAdminActiveFiltersBanner({
    required bool isMobile,
    required String filtersLabel,
    required VoidCallback onEditFilters,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.filter_alt_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active filters',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  filtersLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onEditFilters,
            child: const Text('Edit filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminRegistryNavHint({
    required bool isMobile,
    required String message,
    required String buttonLabel,
    required VoidCallback onOpenRegistry,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: isMobile ? 14 : 15,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onOpenRegistry,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(buttonLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('vehicles').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.directions_car_outlined, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No vehicles found', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        var vehicles = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['docId'] = doc.id;
          return data;
        }).toList();

        // Apply type filter
        if (_vehicleTypeFilter != 'All Types') {
          vehicles = vehicles.where((v) {
            final type = (v['type'] as String? ?? 'Car');
            return type == _vehicleTypeFilter;
          }).toList();
        }

        // Apply search
        if (_vehicleSearchQuery.isNotEmpty) {
          final query = _vehicleSearchQuery.toLowerCase();
          vehicles = vehicles.where((v) {
            final make = (v['make'] as String? ?? '').toLowerCase();
            final model = (v['model'] as String? ?? '').toLowerCase();
            final plate = (v['licensePlate'] as String? ?? '').toLowerCase();
            final driverName = (v['driverName'] as String? ?? '').toLowerCase();
            final ownerEmail = (v['ownerEmail'] as String? ?? '').toLowerCase();
            return make.contains(query) || model.contains(query) || plate.contains(query) || driverName.contains(query) || ownerEmail.contains(query);
          }).toList();
        }

        if (vehicles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No vehicles match the current filters', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        return _VehicleLiveSubscriptionHost(
          vehicles: vehicles,
          monitoringService: _monitoringService,
          builder: (context, liveByDriver) {
            final shown = _adminFilterVehiclesByLiveStatus(
              vehicles,
              _vehicleStatusFilter,
              liveByDriver,
            );
            if (shown.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'No vehicles match the current filters',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < DashboardLayout.mobileBreakpoint;
                if (narrow) {
                  return Column(
                    children: shown
                        .map((v) => _buildMobileVehicleCard(v, liveByDriver))
                        .toList(),
                  );
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 900),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1.5),
                        2: FlexColumnWidth(1),
                        3: FlexColumnWidth(1.5),
                        4: FlexColumnWidth(1.2),
                        5: FlexColumnWidth(1.2),
                        6: FlexColumnWidth(1),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                          ),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text('Vehicle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text('License Plate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text('Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text('Driver', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text('Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text('Alertness', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text('Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                            ),
                          ],
                        ),
                        ...shown.map((v) => _buildVehicleTableDataRow(v, liveByDriver)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  TableRow _buildVehicleTableDataRow(
    Map<String, dynamic> v,
    Map<String, Map<String, dynamic>> liveByDriver,
  ) {
    final make = v['make'] as String? ?? '';
    final model = v['model'] as String? ?? '';
    final plate = v['licensePlate'] as String? ?? '';
    final type = v['type'] as String? ?? 'Car';
    final driverName = v['driverName'] as String?;
    final assignedDriverId = v['assignedDriverId'] as String?;
    final hasDriver = assignedDriverId != null && assignedDriverId.isNotEmpty;
    final effective = _adminVehicleEffectiveStatus(v, liveByDriver);
    final alertness = _adminVehicleEffectiveAlertness(v, liveByDriver);
    final liveActive =
        hasDriver && (liveByDriver[assignedDriverId!]?['active'] == true);

    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      children: [
        _buildTableCell('$make $model'.trim()),
        _buildTableCell(plate),
        _buildVehicleTypeBadge(type),
        _buildTableCell(hasDriver ? (driverName ?? 'Assigned') : 'Unassigned'),
        _buildVehicleStatusBadgeLive(effective),
        _buildAlertnessBadgeLive(alertness, liveActive),
        _buildVehicleActionsCell(v),
      ],
    );
  }

  Widget _buildMobileVehicleCard(
    Map<String, dynamic> vehicle,
    Map<String, Map<String, dynamic>> liveByDriver,
  ) {
    final make = vehicle['make'] as String? ?? '';
    final model = vehicle['model'] as String? ?? '';
    final plate = vehicle['licensePlate'] as String? ?? '';
    final type = vehicle['type'] as String? ?? 'Car';
    final driverName = vehicle['driverName'] as String?;
    final assignedDriverId = vehicle['assignedDriverId'] as String?;
    final hasDriver = assignedDriverId != null && assignedDriverId.isNotEmpty;
    final effective = _adminVehicleEffectiveStatus(vehicle, liveByDriver);
    final alertness = _adminVehicleEffectiveAlertness(vehicle, liveByDriver);
    final liveActive =
        hasDriver && (liveByDriver[assignedDriverId!]?['active'] == true);
    final ownerEmail = vehicle['ownerEmail'] as String? ?? '';

    Color statusColor;
    if (effective == 'Active') {
      statusColor = const Color(0xFF4CAF50);
    } else if (effective == 'Critical') {
      statusColor = Colors.red;
    } else {
      statusColor = Colors.grey;
    }

    final isMobile = DashboardLayout.isMobile(context);
    final alertnessColor = !liveActive
        ? AppColors.textSecondary
        : alertness >= 70
            ? AppColors.success
            : alertness >= 50
                ? AppColors.warning
                : AppColors.danger;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showVehicleQuickDetails(vehicle),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
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
                      VehicleCatalog.iconForType(type),
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
                          '$make $model'.trim().isNotEmpty ? '$make $model'.trim() : 'Unknown Vehicle',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(plate, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      effective,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _buildAdminMetricChip('Type', type, large: false)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildAdminMetricChip(
                      'Status',
                      effective,
                      valueColor: statusColor,
                      large: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildAdminMetricChip(
                      'Driver',
                      hasDriver ? (driverName ?? 'Assigned') : 'Unassigned',
                      large: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildAdminMetricChip(
                      'Alertness',
                      liveActive ? '$alertness%' : 'N/A',
                      valueColor: alertnessColor,
                      large: false,
                    ),
                  ),
                ],
              ),
              if (ownerEmail.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildAdminMetricChip('Owner', ownerEmail, large: false),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 16,
        vertical: isMobile ? 12 : 16,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isMobile ? 12 : 14,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildVehicleTypeBadge(String type) {
    final typeColors = {
      'Car': const Color(0xFF2196F3),
      'Bus': const Color(0xFF9C27B0),
      'Van': const Color(0xFFFF9800),
      'Truck': const Color(0xFF607D8B),
      'Rickshaw': const Color(0xFF4CAF50),
    };
    final color = typeColors[type] ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          type,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildVehicleStatusBadgeLive(String effectiveStatus) {
    Color color;
    if (effectiveStatus == 'Active') {
      color = const Color(0xFF4CAF50);
    } else if (effectiveStatus == 'Critical') {
      color = Colors.red;
    } else {
      color = Colors.grey[500]!;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          effectiveStatus,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildAlertnessBadgeLive(int alertness, bool liveActive) {
    if (!liveActive) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          'N/A',
          style: TextStyle(fontSize: 13, color: Colors.grey[400], fontWeight: FontWeight.w500),
        ),
      );
    }
    return _buildAlertnessBadge(alertness, liveSession: true);
  }

  Widget _buildAlertnessBadge(int alertness, {bool liveSession = false}) {
    Color color;
    if (alertness >= 70) {
      color = const Color(0xFF4CAF50);
    } else if (alertness >= 50) {
      color = const Color(0xFFFF9800);
    } else if (alertness > 0 || liveSession) {
      color = Colors.red;
    } else {
      color = Colors.grey[400]!;
    }

    final showPct = liveSession || alertness > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            showPct ? '$alertness%' : 'N/A',
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleActionsCell(Map<String, dynamic> vehicle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF2196F3)),
            tooltip: 'Edit vehicle',
            onPressed: () => _showEditVehicleDialog(vehicle),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Delete vehicle',
            onPressed: () => _confirmDeleteVehicle(vehicle),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _showVehicleQuickDetails(Map<String, dynamic> vehicle) async {
    final title = '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'.trim();
    final plate = vehicle['licensePlate'] as String? ?? 'N/A';
    final ownerEmail = vehicle['ownerEmail'] as String? ?? 'N/A';
    final ownerId = vehicle['ownerId'] as String?;
    final driverEmail = vehicle['assignedDriverEmail'] as String? ?? 'N/A';
    final driverId = vehicle['assignedDriverId'] as String?;
    String ownerName = 'N/A';
    String driverName = vehicle['driverName'] as String? ?? 'Unassigned';
    try {
      if (ownerId != null && ownerId.isNotEmpty) {
        final ownerDoc = await _firestore.collection('users').doc(ownerId).get();
        if (ownerDoc.exists) {
          final d = ownerDoc.data() as Map<String, dynamic>;
          ownerName = '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
        }
      }
      if (driverId != null && driverId.isNotEmpty) {
        final driverDoc = await _firestore.collection('users').doc(driverId).get();
        if (driverDoc.exists) {
          final d = driverDoc.data() as Map<String, dynamic>;
          final full = '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
          if (full.isNotEmpty) driverName = full;
        }
      }
    } catch (_) {}
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DashboardDetailDialogTheme.surface,
        surfaceTintColor: Colors.transparent,
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title.isNotEmpty ? title : 'Vehicle Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildQuickDetailCardRow(Icons.confirmation_number_outlined, 'Plate', plate),
              const SizedBox(height: 10),
              _buildQuickDetailCardRow(Icons.badge_outlined, 'Owner Name', ownerName.isEmpty ? 'N/A' : ownerName),
              const SizedBox(height: 10),
              _buildQuickDetailCardRow(Icons.mail_outline, 'Owner Email', ownerEmail),
              const SizedBox(height: 10),
              _buildQuickDetailCardRow(Icons.person_outline, 'Driver Name', driverName),
              const SizedBox(height: 10),
              _buildQuickDetailCardRow(Icons.alternate_email, 'Driver Email', driverEmail),
              const SizedBox(height: 10),
              if (driverId != null && driverId.isNotEmpty)
                StreamBuilder<Map<String, dynamic>>(
                  stream: _monitoringService.watchVehicleLiveSummary(driverId),
                  initialData: Map<String, dynamic>.from(MonitoringService.inactiveVehicleLiveSummary),
                  builder: (context, snap) {
                    final live = snap.data ?? MonitoringService.inactiveVehicleLiveSummary;
                    final liveMap = <String, Map<String, dynamic>>{driverId: live};
                    final st = _adminVehicleEffectiveStatus(vehicle, liveMap);
                    final al = _adminVehicleEffectiveAlertness(vehicle, liveMap);
                    final liveActive = live['active'] == true;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildQuickDetailCardRow(Icons.info_outline, 'Status', st),
                        const SizedBox(height: 10),
                        _buildQuickDetailCardRow(
                          Icons.speed,
                          'Alertness',
                          liveActive ? '$al%' : 'N/A',
                        ),
                      ],
                    );
                  },
                )
              else ...[
                _buildQuickDetailCardRow(Icons.info_outline, 'Status', 'Offline'),
                const SizedBox(height: 10),
                _buildQuickDetailCardRow(Icons.speed, 'Alertness', 'N/A'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDeleteVehicle(vehicle);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showEditVehicleDialog(vehicle);
            },
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickDetailCardRow(IconData icon, String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditVehicleDialog(Map<String, dynamic> vehicle) async {
    final docId = vehicle['docId'] as String?;
    if (docId == null || docId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot edit: Vehicle ID not found'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final formKey = GlobalKey<FormState>();
    final makeCtrl = TextEditingController(text: vehicle['make'] as String? ?? '');
    final modelCtrl = TextEditingController(text: vehicle['model'] as String? ?? '');
    final yearCtrl = TextEditingController(text: vehicle['year'] as String? ?? '');
    final plateCtrl = TextEditingController(text: vehicle['licensePlate'] as String? ?? '');
    String selectedType = vehicle['type'] as String? ?? 'Car';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.edit, color: Color(0xFF2196F3), size: 22),
                SizedBox(width: 8),
                Text('Edit Vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: makeCtrl,
                      decoration: InputDecoration(
                        labelText: 'Make',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Make is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: modelCtrl,
                      decoration: InputDecoration(
                        labelText: 'Model',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Model is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: yearCtrl,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Year is required';
                        final year = int.tryParse(v.trim());
                        if (year == null || year < 1900 || year > DateTime.now().year + 1) {
                          return 'Enter a valid year';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: plateCtrl,
                      decoration: InputDecoration(
                        labelText: 'License Plate',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'License plate is required' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: VehicleCatalog.vehicleTypes
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: VehicleCatalog.dropdownMenuLabel(
                                t,
                                iconColor: AppColors.primary.withValues(alpha: 0.85),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedType = val);
                      },
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

                  // Check for duplicate license plate
                  final plateQuery = await _firestore.collection('vehicles')
                      .where('licensePlate', isEqualTo: plateCtrl.text.trim())
                      .get();
                  final hasDuplicate = plateQuery.docs.any((d) => d.id != docId);
                  if (hasDuplicate) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('A vehicle with this license plate already exists'), backgroundColor: Colors.red),
                      );
                    }
                    return;
                  }

                  Navigator.pop(ctx);
                  try {
                    await _firestore.collection('vehicles').doc(docId).update({
                      'make': makeCtrl.text.trim(),
                      'model': modelCtrl.text.trim(),
                      'year': yearCtrl.text.trim(),
                      'licensePlate': plateCtrl.text.trim(),
                      'type': selectedType,
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vehicle updated successfully'), backgroundColor: Color(0xFF4CAF50)),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating vehicle: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteVehicle(Map<String, dynamic> vehicle) async {
    final docId = vehicle['docId'] as String?;
    if (docId == null || docId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: Vehicle ID not found'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final make = vehicle['make'] as String? ?? '';
    final model = vehicle['model'] as String? ?? '';
    final plate = vehicle['licensePlate'] as String? ?? '';
    final assignedDriverId = vehicle['assignedDriverId'] as String?;
    final hasDriver = assignedDriverId != null && assignedDriverId.isNotEmpty;

    final confirm = await showDialog<bool>(
      context: context,
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
            const Text('Are you sure you want to delete this vehicle?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$make $model'.trim().isNotEmpty ? '$make $model' : 'Unknown Vehicle', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                  color: const Color(0xFFFF9800).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: Color(0xFFFF9800)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This vehicle has an assigned driver. The driver will be unassigned.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFFF9800)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
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

    if (confirm == true) {
      try {
        await _firestore.collection('vehicles').doc(docId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${make.isNotEmpty ? "$make $model" : "Vehicle"} has been deleted'),
              backgroundColor: const Color(0xFF4CAF50),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting vehicle: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // =============================================
  // DOCUMENT APPROVAL (Real-time)
  // - Driver CNIC/License approval
  // - Owner vehicle book/id card approval
  // =============================================
  String _formatTime(DateTime? t) {
    if (t == null) return '—';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  Future<void> _approveDriverDocs(DriverDocumentSubmission s) async {
    setState(() => _processingSubmissionId = s.id);
    try {
      await _driverDocumentSubmissionService.approveSubmission(s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver documents Approved. Vehicle Assignment Attempted.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingSubmissionId = null);
    }
  }

  Future<void> _rejectDriverDocs(DriverDocumentSubmission s) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Reject Driver Documents'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Reason (Optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Reject')),
          ],
        );
      },
    );
    if (reason == null) return;
    setState(() => _processingSubmissionId = s.id);
    try {
      await _driverDocumentSubmissionService.rejectSubmission(s.id, reason: reason.isEmpty ? null : reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submission rejected'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingSubmissionId = null);
    }
  }

  Future<void> _approveOwnerVehicle(OwnerVehicleSubmission s) async {
    setState(() => _processingSubmissionId = s.id);
    try {
      await _ownerVehicleSubmissionService.approveSubmission(s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle booking approved. Vehicle assignment attempted (if driver queue exists).'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingSubmissionId = null);
    }
  }

  Future<void> _rejectOwnerVehicle(OwnerVehicleSubmission s) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Reject vehicle submission'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Reject')),
          ],
        );
      },
    );
    if (reason == null) return;

    setState(() => _processingSubmissionId = s.id);
    try {
      await _ownerVehicleSubmissionService.rejectSubmission(s.id, reason: reason.isEmpty ? null : reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submission rejected'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingSubmissionId = null);
    }
  }

  bool _isPdfUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.pdf') || lower.contains('/pdf') || lower.contains('format=pdf');
  }

  Future<void> _openDocUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showDocPreview(String url, String title) {
    if (url.isEmpty) return;

    if (_isPdfUrl(url)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined, color: AppColors.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'This document is a PDF. Open it in your browser or PDF viewer.',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _openDocUrl(url);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open PDF'),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text(title, style: const TextStyle(fontSize: 16)),
                automaticallyImplyLeading: false,
                actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))],
              ),
              SizedBox(
                height: 400,
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.network(
                      url,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Could not load preview'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentApproval() {
    final isMobile = DashboardLayout.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStaggeredItem(
          _buildAdminSectionCard(
            isMobile: isMobile,
            icon: Icons.badge_outlined,
            title: 'Driver Documents',
            subtitle: 'Review CNIC and License Submissions',
            child: StreamBuilder<List<DriverDocumentSubmission>>(
            stream: _driverDocumentSubmissionService.watchPendingSubmissions(),
            builder: (context, snapshot) {
              final pending = snapshot.data ?? [];
              final count = pending.length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAdminOptionBlock(
                    isMobile: isMobile,
                    label: 'Pending Queue',
                    hint: 'Documents Waiting for Admin Review',
                    icon: Icons.pending_actions,
                    child: _buildAdminMetricChip(
                      'Pending',
                      count.toString(),
                      valueColor: AppColors.warning,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.hasError)
                    Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red))
                  else if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    )
                  else if (pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'No driver document submissions',
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobileLayout = constraints.maxWidth < DashboardLayout.mobileBreakpoint;
                        if (isMobileLayout) {
                          return Column(
                            children: pending.map((s) => _buildMobileDriverDocCard(s)).toList(),
                          );
                        }
                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(flex: 3, child: Text('Driver', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text('Submitted', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text('Documents', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text('Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                ],
                              ),
                            ),
                            ...pending.map((s) => _buildDriverDocRow(s)),
                          ],
                        );
                      },
                    ),
                ],
              );
            },
          ),
          ),
          0,
        ),
        _adminSectionGap(isMobile),
        _buildStaggeredItem(
          _buildAdminSectionCard(
            isMobile: isMobile,
            icon: Icons.directions_car_filled_outlined,
            title: 'Owner Vehicles',
            subtitle: 'Approve owner vehicle book submissions',
            child: StreamBuilder<List<OwnerVehicleSubmission>>(
            stream: _ownerVehicleSubmissionService.watchPendingSubmissions(),
            builder: (context, snapshot) {
              final pending = snapshot.data ?? [];
              final count = pending.length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAdminOptionBlock(
                    isMobile: isMobile,
                    label: 'Pending Queue',
                    hint: 'Vehicle books waiting for approval',
                    icon: Icons.pending_actions,
                    child: _buildAdminMetricChip(
                      'Pending',
                      count.toString(),
                      valueColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.hasError)
                    Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red))
                  else if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    )
                  else if (pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'No owner vehicle submissions',
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobileLayout = constraints.maxWidth < DashboardLayout.mobileBreakpoint;
                        if (isMobileLayout) {
                          return Column(
                            children: pending.map((s) => _buildMobileOwnerVehicleCard(s)).toList(),
                          );
                        }
                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(flex: 2, child: Text('Owner', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 3, child: Text('Vehicle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text('Submitted', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text('Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                ],
                              ),
                            ),
                            ...pending.map((s) => _buildOwnerVehicleRow(s)),
                          ],
                        );
                      },
                    ),
                ],
              );
            },
          ),
          ),
          1,
        ),
      ],
    );
  }

  Widget _buildDriverDocRow(DriverDocumentSubmission s) {
    final busy = _processingSubmissionId == s.id;
    final initial = s.driverName.isNotEmpty ? s.driverName[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFFF9800).withOpacity(0.15),
                  child: Text(
                    initial,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFFF9800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.driverName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (s.preferredTypeDisplay != null && s.preferredTypeDisplay!.isNotEmpty)
                        Text(
                          'Preferred type: ${s.preferredTypeDisplay}',
                          style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatTime(s.submittedAt),
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => _showDocPreview(s.cnicUrl, 'CNIC'),
                  child: const Text('CNIC', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => _showDocPreview(s.licenseUrl, 'License'),
                  child: const Text('License', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: busy ? null : () => _approveDriverDocs(s),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                    minimumSize: Size.zero,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Approve', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : () => _rejectDriverDocs(s),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDriverDocCard(DriverDocumentSubmission s) {
    final busy = _processingSubmissionId == s.id;
    final initial = s.driverName.isNotEmpty ? s.driverName[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
                child: Text(
                  initial,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.driverName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    if (s.preferredTypeDisplay != null && s.preferredTypeDisplay!.isNotEmpty)
                      Text(
                        'Preferred type: ${s.preferredTypeDisplay}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                      ),
                    Text(_formatTime(s.submittedAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(onPressed: () => _showDocPreview(s.cnicUrl, 'CNIC'), child: const Text('CNIC')),
              OutlinedButton(onPressed: () => _showDocPreview(s.licenseUrl, 'License'), child: const Text('License')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _approveDriverDocs(s),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _rejectDriverDocs(s),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerVehicleRow(OwnerVehicleSubmission s) {
    final busy = _processingSubmissionId == s.id;
    final initial = s.ownerName.isNotEmpty ? s.ownerName[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF2196F3).withOpacity(0.15),
                  child: Text(
                    initial,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2196F3)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.ownerName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${s.make} ${s.model} · ${s.licensePlate} (${s.type})',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatTime(s.submittedAt),
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                TextButton(
                  onPressed: () => _showDocPreview(s.vehicleBookUrl, 'Vehicle book'),
                  child: const Text('View', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: busy ? null : () => _approveOwnerVehicle(s),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                    minimumSize: Size.zero,
                  ),
                  child: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Approve', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : () => _rejectOwnerVehicle(s),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileOwnerVehicleCard(OwnerVehicleSubmission s) {
    final busy = _processingSubmissionId == s.id;
    final initial = s.ownerName.isNotEmpty ? s.ownerName[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
                child: Text(
                  initial,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.ownerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('${s.make} ${s.model} · ${s.licensePlate}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildAdminMetricChip('Submitted', _formatTime(s.submittedAt), large: false),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showDocPreview(s.vehicleBookUrl, 'Vehicle book'),
                  child: const Text('View vehicle book'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _approveOwnerVehicle(s),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _rejectOwnerVehicle(s),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Removed: _buildFleetOverview, _buildGlobalFleetStatus, _buildLiveFleetMap,
}

/// Live **Active vehicles** and **Alerts** from RTDB (same rules as owner: monitoring on + heartbeat; critical from `current_stats`).
class _AdminLiveVehicleFleetMetrics extends StatefulWidget {
  const _AdminLiveVehicleFleetMetrics({
    required this.vehicleDocs,
    required this.isLoading,
    required this.isMobile,
    required this.monitoringService,
    required this.statCardBuilder,
    this.metricOnly,
  });

  final List<QueryDocumentSnapshot> vehicleDocs;
  final bool isLoading;
  final bool isMobile;
  final MonitoringService monitoringService;
  /// When set to `active` or `alerts`, only that metric block is built.
  final String? metricOnly;
  final Widget Function(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color valueColor,
    Color subtitleColor,
    bool isMobile,
  ) statCardBuilder;

  @override
  State<_AdminLiveVehicleFleetMetrics> createState() => _AdminLiveVehicleFleetMetricsState();
}

class _AdminLiveVehicleFleetMetricsState extends State<_AdminLiveVehicleFleetMetrics> {
  final Map<String, bool> _sessionActiveByDriver = {};
  final Map<String, Map<String, dynamic>> _statsByDriver = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  static Set<String> _driverIdsFromDocs(List<QueryDocumentSnapshot> docs) {
    final ids = <String>{};
    for (final doc in docs) {
      final raw = doc.data();
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data['assignedDriverId'] as String?;
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  void _resubscribe() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    setState(() {
      _sessionActiveByDriver.clear();
      _statsByDriver.clear();
    });

    for (final id in _driverIdsFromDocs(widget.vehicleDocs)) {
      _subscriptions.add(
        widget.monitoringService.watchHasActiveMonitoringSession(id).listen((active) {
          if (!mounted) return;
          setState(() => _sessionActiveByDriver[id] = active);
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

  int _liveActiveVehicleCount() {
    var n = 0;
    for (final doc in widget.vehicleDocs) {
      final raw = doc.data();
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw as Map);
      final driverId = data['assignedDriverId'] as String?;
      if (driverId == null || driverId.isEmpty) continue;
      if (_sessionActiveByDriver[driverId] == true) n++;
    }
    return n;
  }

  int _liveAlertsVehicleCount() {
    var n = 0;
    for (final doc in widget.vehicleDocs) {
      final raw = doc.data();
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw as Map);
      final driverId = data['assignedDriverId'] as String?;
      if (driverId == null || driverId.isEmpty) continue;
      if (_sessionActiveByDriver[driverId] != true) continue;
      final stats = _statsByDriver[driverId];
      if (stats == null || stats.isEmpty) continue;
      if (adminLiveMetricsCritical(stats)) n++;
    }
    return n;
  }

  @override
  void initState() {
    super.initState();
    _resubscribe();
  }

  @override
  void didUpdateWidget(covariant _AdminLiveVehicleFleetMetrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = _driverIdsFromDocs(oldWidget.vehicleDocs);
    final b = _driverIdsFromDocs(widget.vehicleDocs);
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
    final active = _liveActiveVehicleCount();
    final alerts = _liveAlertsVehicleCount();
    final valueActive = widget.isLoading ? '...' : active.toString();
    final valueAlerts = widget.isLoading ? '...' : alerts.toString();

    final activeCard = widget.statCardBuilder(
      'Live Sessions',
      valueActive,
      'Vehicles currently being monitored',
      Icons.directions_car_filled_outlined,
      AppColors.success,
      AppColors.success,
      widget.isMobile,
    );
    final alertsCard = widget.statCardBuilder(
      'Critical Now',
      valueAlerts,
      'Requires immediate attention',
      Icons.warning_amber_rounded,
      AppColors.danger,
      AppColors.danger,
      widget.isMobile,
    );

    if (widget.metricOnly == 'active') return activeCard;
    if (widget.metricOnly == 'alerts') return alertsCard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        activeCard,
        SizedBox(height: widget.isMobile ? 16 : 20),
        alertsCard,
      ],
    );
  }
}
