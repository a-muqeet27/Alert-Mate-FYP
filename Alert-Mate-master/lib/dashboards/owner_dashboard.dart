import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../models/vehicle.dart';
import '../models/emergency_contact.dart';
import '../services/vehicle_service.dart';
import '../services/emergency_contact_service.dart';
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
import '../constants/vehicle_catalog.dart';
import '../widgets/dashboard_detail_dialog_theme.dart';
import '../utils/dashboard_responsive.dart';

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
  late EmergencyContactService _emergencyContactService;

  int _selectedIndex = 0;
  bool _isLoading = false;

  List<MenuItem> get _sidebarMenuItems => [
        const MenuItem(
          section: 'Fleet',
          icon: Icons.home_outlined,
          title: 'Overview',
        ),
        const MenuItem(
          section: 'Fleet',
          icon: Icons.directions_car_outlined,
          title: 'Fleet Management',
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
          unreadBadgeStream: UserNotificationsService.unreadCountStream(widget.user.id),
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
      default:
        return _buildOwnerOverviewPage();
    }
  }

  String get _currentPageTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Overview';
      case 1:
        return 'Fleet Management';
      case 2:
        return 'Live Map';
      case 3:
        return 'Emergency';
      case 4:
        return 'Notifications';
      default:
        return 'Overview';
    }
  }

  String get _currentPageSubtitle {
    switch (_selectedIndex) {
      case 0:
        return 'Monitor and manage your vehicle fleet';
      case 1:
        return 'View and manage all registered vehicles';
      case 2:
        return 'Track drivers assigned to your vehicles';
      case 3:
        return 'Quick access to emergency services and contacts';
      case 4:
        return 'Alerts and system messages';
      default:
        return 'Monitor and manage your vehicle fleet';
    }
  }

  Widget _buildOwnerNotificationsPage() {
    return _ownerPageShell(
      title: 'Notifications',
      subtitle: 'Alerts and system messages',
      child: NotificationsInboxScreen(user: widget.user, embedded: true),
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
    return _ownerPageShell(
      title: 'Fleet Management',
      subtitle: 'View and manage all registered vehicles',
      child: _buildFleetOverview(),
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


  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _emergencyContactService = EmergencyContactService();
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
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  bool _contactAllowsCall(EmergencyContact contact) =>
      contact.methods.any((m) => m.toString() == 'call');

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
    final formKey = GlobalKey<FormState>();
    String vehicleType = 'Car';
    String make = VehicleCatalog.defaultMake('Car') ?? '';
    String model = (make.isNotEmpty)
        ? (VehicleCatalog.defaultModel('Car', make) ?? '')
        : '';
    String year = '';
    String licensePlate = '';
    bool willDrive = false;
    Uint8List? vehicleBookBytes;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context,  setDialogState) {
          return AlertDialog(
            title: const Text('Add New Vehicle'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: vehicleType,
                    decoration: const InputDecoration(labelText: 'Type *'),
                    items: VehicleCatalog.vehicleTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Type is required';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        vehicleType = value;
                        final m = VehicleCatalog.defaultMake(value) ?? '';
                        make = m;
                        model = m.isNotEmpty
                            ? (VehicleCatalog.defaultModel(value, m) ?? '')
                            : '';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: make.isNotEmpty &&
                            VehicleCatalog.makesFor(vehicleType).contains(make)
                        ? make
                        : null,
                    decoration: const InputDecoration(labelText: 'Make *'),
                    items: VehicleCatalog.makesFor(vehicleType)
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Make is required';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        make = value;
                        model = VehicleCatalog.defaultModel(vehicleType, value) ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: model.isNotEmpty &&
                            VehicleCatalog.modelsFor(vehicleType, make).contains(model)
                        ? model
                        : null,
                    decoration: const InputDecoration(labelText: 'Model *'),
                    items: VehicleCatalog.modelsFor(vehicleType, make)
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Model is required';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => model = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Year *'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Year is required';
                      }
                      final yearInt = int.tryParse(value.trim());
                      if (yearInt == null) {
                        return 'Year must be a valid number';
                      }
                      final currentYear = DateTime.now().year;
                      if (yearInt < 1900 || yearInt > currentYear + 1) {
                        return 'Year must be between 1900 and ${currentYear + 1}';
                      }
                      return null;
                    },
                    onSaved: (value) => year = value!.trim(),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'License Plate *',
                      hintText: 'ABC-123',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9\-]')),
                      _LicensePlateFormatter(),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'License plate is required';
                      }
                      final plate = value.trim().toUpperCase();
                      // Validate ABC-123 format (3 letters, dash, 3 digits)
                      if (!RegExp(r'^[A-Z]{3}-[0-9]{3}$').hasMatch(plate)) {
                        return 'License plate must be in format ABC-123';
                      }
                      return null;
                    },
                    onSaved: (value) => licensePlate = value!.trim().toUpperCase(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Vehicle id card / book *',
                          style: TextStyle(fontSize: MediaQuery.of(context).size.width < 768 ? 13 : 14),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final bytes = await _pickImageBytes();
                          if (bytes == null) return;
                          setDialogState(() => vehicleBookBytes = bytes);
                        },
                        icon: Icon(
                          vehicleBookBytes != null ? Icons.check_circle : Icons.upload_file,
                          size: 18,
                          color: vehicleBookBytes != null ? Colors.green : AppColors.primary,
                        ),
                        label: Text(vehicleBookBytes != null ? 'Change' : 'Upload'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('I will be driving this vehicle'),
                    subtitle: const Text('Assign this vehicle to me'),
                    value: willDrive,
                    onChanged: (value) {
                      final turningOn = value == true && willDrive != true;
                      setDialogState(() {
                        willDrive = value!;
                      });

                      if (turningOn && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'To assign this car to you as driver, you will need driver verification (CNIC + license) approval from admin.',
                            ),
                            backgroundColor: AppColors.primary,
                            duration: Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.primary,
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
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    formKey.currentState!.save();

                    // Check if owner already has an assigned vehicle when they want to drive
                    if (willDrive) {
                      final existingVehicles = await _vehicleService.getVehiclesForOwner(widget.user.id);
                      final alreadyDrivingVehicle = existingVehicles.any(
                        (v) => v.assignedDriverId == widget.user.id
                      );
                      
                      if (alreadyDrivingVehicle) {
                        // Show warning that owner can't drive more than one vehicle
                        final existingVehicle = existingVehicles.firstWhere(
                          (v) => v.assignedDriverId == widget.user.id
                        );
                        
                        final proceed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                                SizedBox(width: 12),
                                Expanded(child: Text('Already Driving a Vehicle')),
                              ],
                            ),
                            content: Text(
                              'You are already assigned as the driver for:\n\n'
                              '${existingVehicle.make} ${existingVehicle.model} (${existingVehicle.licensePlate})\n\n'
                              'A driver can only be assigned to one vehicle at a time.\n\n'
                              'Would you like to add this vehicle without assigning yourself as the driver? '
                              'It will be available for other drivers.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Add Without Driving'),
                              ),
                            ],
                          ),
                        );
                        
                        if (proceed != true) return;
                        
                        // User chose to add without driving
                        willDrive = false;
                      }
                    }

                    // Show confirmation dialog
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Confirm Vehicle Addition'),
                        content: Text(
                          'Are you sure you want to add this vehicle?\n\n'
                              'Type: $vehicleType\n'
                              'Make: $make\n'
                              'Model: $model\n'
                              'Year: $year\n'
                              'License Plate: $licensePlate\n'
                              '${willDrive ? "You will be assigned as the driver." : "Vehicle will be available for driver assignment."}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Confirm'),
                          ),
                        ],
                      ),
                    );

                    if (confirm != true) return;

                    Navigator.pop(context);
                    if (!mounted) return;
                    final parentContext = this.context;

                    try {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(content: Text('Submitting vehicle for admin approval...')),
                      );

                      if (vehicleBookBytes == null) {
                        if (mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            const SnackBar(
                              content: Text('Please upload the vehicle id card / book.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                        return;
                      }

                      await _ownerVehicleSubmissionService.submitVehicle(
                        ownerId: widget.user.id,
                        ownerEmail: widget.user.email,
                        ownerName: widget.user.fullName.trim().isEmpty ? widget.user.email : widget.user.fullName,
                        make: make,
                        model: model,
                        year: year,
                        licensePlate: licensePlate,
                        type: vehicleType,
                        willOwnerDrive: willDrive,
                        vehicleBookBytes: vehicleBookBytes!,
                      );

                      if (mounted) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(
                            content: const Text('Submitted! Admin will approve your vehicle.'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        // Show error in a dialog for better visibility
                        showDialog(
                          context: parentContext,
                          builder: (context) => AlertDialog(
                            title: const Row(
                              children: [
                                Icon(Icons.error_outline, color: AppColors.danger, size: 28),
                                SizedBox(width: 12),
                                Expanded(child: Text('Error Adding Vehicle')),
                              ],
                            ),
                            content: Text(
                              e.toString().replaceFirst('Exception: ', ''),
                              style: const TextStyle(fontSize: 16),
                            ),
                            actions: [
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      }
                    }
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
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
            role: 'owner',
            user: widget.user is User ? widget.user : null,
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
      subtitle: 'Monitor and manage your vehicle fleet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMobile)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showAddVehicleDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Vehicle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          if (isMobile) const SizedBox(height: 16),
          StreamBuilder<List<Vehicle>>(
                  stream: _vehicleService.getVehiclesByOwnerStream(widget.user.id),
                  builder: (context, snapshot) {
                    final vehicles = snapshot.data ?? [];
                    final isMobile = DashboardLayout.isMobile(context);
                    final isTablet = DashboardLayout.isTablet(context);

                    return _buildStaggeredItem(
                      isMobile
                          ? Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'Total Vehicles',
                                  vehicles.length.toString(),
                                  'Registered in system',
                                  Icons.directions_car_outlined,
                                  AppColors.primary,
                                  isMobile,
                                  () => _showOwnerStatDetails(
                                    'All Vehicles',
                                    vehicles.map(_buildOwnerVehicleSummaryTile).toList(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _OwnerDashboardActiveDriversCard(
                                  vehicles: vehicles,
                                  monitoringService: _monitoringService,
                                  isMobile: isMobile,
                                  builder: (context, activeDriverCount, activeDriverTiles) => _buildStatCard(
                                    'Active Drivers',
                                    activeDriverCount.toString(),
                                    'Currently driving',
                                    Icons.people_outline,
                                    AppColors.success,
                                    isMobile,
                                    () => _showOwnerStatDetails('Active Drivers', activeDriverTiles),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                                              title: Text('${v.licensePlate} • ${v.make} ${v.model}'),
                                              subtitle: Text('Driver: ${v.driverName ?? "Unassigned"}'),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
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
                          : isTablet
                          ? Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildStatCard(
                                'Total Vehicles',
                                vehicles.length.toString(),
                                'Registered in system',
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
                                    'Currently driving',
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
                                              title: Text('${v.licensePlate} • ${v.make} ${v.model}'),
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
                                'Registered in system',
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
                                    'Currently driving',
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
                                              title: Text('${v.licensePlate} • ${v.make} ${v.model}'),
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
                      ),
                      1,
                    );
                  },
                ),
        ],
      ),
    );
  }

  /// Builds the LiveMap section filtered to only show drivers assigned
  /// to this owner's vehicles.
  Widget _buildOwnerLiveMapSection() {
    return StreamBuilder<List<Vehicle>>(
      stream: _vehicleService.getVehiclesByOwnerStream(widget.user.id),
      builder: (context, snapshot) {
        final vehicles = snapshot.data ?? [];
        final driverIds = vehicles
            .where((v) => v.assignedDriverId != null && v.assignedDriverId!.isNotEmpty)
            .map((v) => v.assignedDriverId!)
            .toSet()
            .toList();

        return SizedBox(
          height: DashboardLayout.liveMapHeight(context),
          child: LiveMap(filterDriverIds: driverIds),
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
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: isMobile ? 20 : 24),
          ),
          SizedBox(height: isMobile ? 16 : 24),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 22 : 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 13 : 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: isMobile ? 2 : 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: isMobile ? 11 : 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: card,
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
        backgroundColor: DashboardDetailDialogTheme.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 820, maxHeight: maxDialogHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: DashboardDetailDialogTheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.35))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  children: children
                      .map((child) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: child,
                          ))
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
      title: Text(
        '${vehicle.licensePlate} • ${vehicle.make} ${vehicle.model}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
              icon: Icon(Icons.edit_outlined, color: AppColors.primary, size: isMobile ? 18 : 20),
              tooltip: 'Edit',
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: () => _showEditVehicleDialog(vehicle),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red, size: isMobile ? 18 : 20),
              tooltip: 'Delete',
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: () => _showDeleteVehicleDialog(vehicle),
            ),
          ],
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
          return Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }

        final vehicles = snapshot.data ?? [];

        // Build map of driverId -> hasActiveSession for filtering
        return FutureBuilder<Map<String, bool>>(
          future: _getActiveSessionMapFuture(vehicles),
          builder: (context, sessionSnapshot) {
            if (sessionSnapshot.connectionState == ConnectionState.waiting) {
              return Container(
                padding: EdgeInsets.all(isMobile ? 16 : 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              );
            }

            final activeSessionMap = sessionSnapshot.data ?? {};

            // --- FILTERING ---
            final statusFilterActive = _statusFilter != 'All Status';
            final typeFilterActive = _typeFilter != 'All Types';
            
            List<Vehicle> filteredVehicles = vehicles.where((vehicle) {
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

            return Container(
              padding: EdgeInsets.all(isMobile ? 14 : 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMobile)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Filter by:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _statusFilter,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down),
                        items: const [
                          DropdownMenuItem(value: 'All Status', child: Text('All Status')),
                          DropdownMenuItem(value: 'Active', child: Text('Active')),
                          DropdownMenuItem(value: 'Critical', child: Text('Critical')),
                          DropdownMenuItem(value: 'Offline', child: Text('Offline')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _statusFilter = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _typeFilter,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down),
                        items: const [
                          DropdownMenuItem(value: 'All Types', child: Text('All Types')),
                          DropdownMenuItem(value: 'Car', child: Text('Car')),
                          DropdownMenuItem(value: 'Bus', child: Text('Bus')),
                          DropdownMenuItem(value: 'Van', child: Text('Van')),
                          DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                          DropdownMenuItem(value: 'Rickshaw', child: Text('Rickshaw')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _typeFilter = value!;
                          });
                        },
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _showAddVehicleDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Vehicle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              if (isMobile) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showAddVehicleDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Vehicle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Filter by:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<String>(
                          value: _statusFilter,
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.arrow_drop_down),
                          items: const [
                            DropdownMenuItem(value: 'All Status', child: Text('All Status')),
                            DropdownMenuItem(value: 'Active', child: Text('Active')),
                            DropdownMenuItem(value: 'Critical', child: Text('Critical')),
                            DropdownMenuItem(value: 'Offline', child: Text('Offline')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _statusFilter = value!;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<String>(
                          value: _typeFilter,
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.arrow_drop_down),
                          items: const [
                            DropdownMenuItem(value: 'All Types', child: Text('All Types')),
                            DropdownMenuItem(value: 'Car', child: Text('Car')),
                            DropdownMenuItem(value: 'Bus', child: Text('Bus')),
                            DropdownMenuItem(value: 'Van', child: Text('Van')),
                            DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                            DropdownMenuItem(value: 'Rickshaw', child: Text('Rickshaw')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _typeFilter = value!;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: isMobile ? 10 : 12),
              if (_statusFilter != 'All Status' || _typeFilter != 'All Types')
                Padding(
                  padding: EdgeInsets.only(bottom: isMobile ? 8 : 12),
                  child: Row(
                    children: [
                      Text(
                        'Found ${filteredVehicles.length} vehicle${filteredVehicles.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: isMobile ? 12 : 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_statusFilter != 'All Status' || _typeFilter != 'All Types') ...[
                        SizedBox(width: isMobile ? 6 : 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _statusFilter = 'All Status';
                              _typeFilter = 'All Types';
                            });
                          },
                          icon: Icon(Icons.clear, size: isMobile ? 14 : 16),
                          label: Text('Clear filters', style: TextStyle(fontSize: isMobile ? 12 : 14)),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 6 : 8,
                                vertical: isMobile ? 2 : 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (filteredVehicles.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 20 : 40),
                    child: Column(
                      children: [
                        Icon(
                          _statusFilter != 'All Status' || _typeFilter != 'All Types'
                              ? Icons.filter_alt_off
                              : Icons.directions_car_outlined,
                          size: isMobile ? 40 : 48,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: isMobile ? 12 : 16),
                        Text(
                          _statusFilter != 'All Status' || _typeFilter != 'All Types'
                              ? 'No vehicles match your filters'
                              : 'No vehicles found',
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_statusFilter != 'All Status' || _typeFilter != 'All Types') ...[
                          SizedBox(height: isMobile ? 6 : 8),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _statusFilter = 'All Status';
                                _typeFilter = 'All Types';
                              });
                            },
                            child: Text('Clear filters', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                isMobile
                    ? Column(
                  children: filteredVehicles.map((vehicle) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildMobileVehicleCard(vehicle),
                  )).toList(),
                )
                    : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: MediaQuery.of(context).size.width - (isMobile ? 32 : 160),
                    ),
                    child: Table(
                      columnWidths: const {
                        0: FixedColumnWidth(180),
                        1: FixedColumnWidth(240),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
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
            ],
          ),
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
                              Icons.local_police,
                              AppColors.police,
                              AppColors.policeLight,
                              isMobile,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEmergencyServiceCard(
                              'Ambulance',
                              '1122',
                              Icons.local_hospital,
                              AppColors.ambulance,
                              AppColors.ambulanceLight,
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
                              Icons.local_fire_department,
                              AppColors.fire,
                              AppColors.fireLight,
                              isMobile,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEmergencyServiceCard(
                              'Motorway Police',
                              '130',
                              Icons.car_crash,
                              AppColors.motorway,
                              AppColors.motorwayLight,
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
                              Icons.local_police,
                              AppColors.police,
                              AppColors.policeLight,
                              isMobile,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _buildEmergencyServiceCard(
                              'Ambulance',
                              '1122',
                              Icons.local_hospital,
                              AppColors.ambulance,
                              AppColors.ambulanceLight,
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
                              Icons.local_fire_department,
                              AppColors.fire,
                              AppColors.fireLight,
                              isMobile,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _buildEmergencyServiceCard(
                              'Motorway Police',
                              '130',
                              Icons.car_crash,
                              AppColors.motorway,
                              AppColors.motorwayLight,
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
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
                color: Colors.black.withValues(alpha: 0.04),
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
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 20,
                      vertical: isMobile ? 10 : 12,
                    ),
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

  Widget _buildEmergencyServiceCard(String title, String number, IconData icon, Color color, Color bgColor, [bool isMobile = false]) {
    return InkWell(
      onTap: () => _dialPhoneNumber(number),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
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

  void _showAddContactDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final relationshipController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    String priority = 'secondary';
    List<String> methods = ['call'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
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
              onPressed: () async {
                if (methods.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select at least one contact method')),
                  );
                  return;
                }
                
                if (formKey.currentState!.validate()) {
                  try {
                    await _emergencyContactService.addEmergencyContact(
                      userId: widget.user.id,
                      userRole: 'owner',
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
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${nameController.text} added to emergency contacts'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error adding contact: $e')),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Contact'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditContactDialog(EmergencyContact contact) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: contact.name);
    final relationshipController = TextEditingController(text: contact.relationship);
    final phoneController = TextEditingController(text: contact.phone);
    final emailController = TextEditingController(text: contact.email);
    String priority = contact.priority;
    List<String> methods = List<String>.from(contact.methods);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
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
              onPressed: () async {
                if (methods.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select at least one contact method')),
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
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${nameController.text} updated successfully'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating contact: $e')),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
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
              Expanded(
                child: Text(contact.phone, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              ),
            ],
          ),
          if (_contactAllowsCall(contact) && contact.phone.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _dialPhoneNumber(contact.phone),
                icon: const Icon(Icons.phone, size: 18),
                label: const Text('Call now'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.85)),
                ),
              ),
            ),
          ],
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
              const SizedBox(width: 8),
              _buildMethodsCell(contact.methods, true),
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
        _buildContactInfoCell(contact.phone, contact.email, isMobile, _contactAllowsCall(contact)),
        _buildPriorityBadgeCell(contact.priority, isMobile),
        _buildMethodsCell(contact.methods, isMobile),
        _buildStatusToggleCell(contact, isMobile),
        _buildContactActionsCell(contact, isMobile),
      ],
    );
  }

  Widget _buildContactInfoCell(String phone, String email, [bool isMobile = false, bool showCallNow = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  phone,
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (showCallNow && phone.trim().isNotEmpty) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Call now',
                  child: IconButton(
                    onPressed: () => _dialPhoneNumber(phone),
                    icon: Icon(Icons.phone, size: isMobile ? 20 : 22, color: Colors.green[700]),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
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
          horizontal: isMobile ? 0 : 16,
          vertical: isMobile ? 0 : 12),
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

  // Helper methods for fleet overview table
  Widget _buildMobileVehicleCard(Vehicle vehicle) {
    return InkWell(
      onTap: () => _showOwnerStatDetails('Vehicle Details', [
        ListTile(title: Text(vehicle.licensePlate), subtitle: Text('${vehicle.make} ${vehicle.model} (${vehicle.year})')),
        ListTile(title: const Text('Driver'), subtitle: Text(vehicle.driverName ?? 'Unassigned')),
        _vehicleDetailStatusTile(vehicle),
        ListTile(title: const Text('Location'), subtitle: Text(vehicle.location ?? 'Unknown')),
        ListTile(title: const Text('Alertness'), subtitle: Text('${vehicle.alertness}%')),
        ListTile(
          title: const Text('Actions'),
          subtitle: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () => _showEditVehicleDialog(vehicle),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _showDeleteVehicleDialog(vehicle),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
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
                                const SnackBar(content: Text('Cannot make phone call')),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Driver phone number not available')),
                            );
                          }
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No driver assigned to this vehicle')),
                      );
                    }
                  },
                  icon: const Icon(Icons.phone_outlined),
                  label: const Text('Call'),
                ),
              ],
            ),
          ),
        ),
      ]),
      borderRadius: BorderRadius.circular(8),
      child: Container(
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
                  vehicle.licensePlate,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              _buildMobileRealtimeStatusBadge(vehicle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${vehicle.make} ${vehicle.model}',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      ),
    ));
  }

  Widget _buildTableHeader(String text, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 14,
          vertical: isMobile ? 8 : 10),
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

  // Real-time status badge — Active only while monitoring pushes stats to RTDB; else Offline; Critical when unsafe.
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
            icon: Icon(Icons.edit_outlined, size: isMobile ? 18 : 20, color: AppColors.primary),
            onPressed: () {
              _showEditVehicleDialog(vehicle);
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Edit vehicle',
          ),
          SizedBox(width: isMobile ? 4 : 8),
          IconButton(
            icon: Icon(Icons.delete_outline, size: isMobile ? 18 : 20, color: Colors.red[700]),
            onPressed: () {
              _showDeleteVehicleDialog(vehicle);
            },
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

  Future<void> _showEditVehicleDialog(Vehicle vehicle) async {
    final formKey = GlobalKey<FormState>();
    final makeCtrl = TextEditingController(text: vehicle.make);
    final modelCtrl = TextEditingController(text: vehicle.model);
    final yearCtrl = TextEditingController(text: vehicle.year);
    final plateCtrl = TextEditingController(text: vehicle.licensePlate);
    String selectedType = vehicle.type;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Edit Vehicle'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: makeCtrl,
                    decoration: const InputDecoration(labelText: 'Make', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: modelCtrl,
                    decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: yearCtrl,
                    decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: plateCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_LicensePlateFormatter()],
                    decoration: const InputDecoration(labelText: 'License Plate', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                    items: const ['Car', 'Bus', 'Van', 'Truck', 'Rickshaw']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => selectedType = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                await _firestore.collection('vehicles').doc(vehicle.id).update({
                  'make': makeCtrl.text.trim(),
                  'model': modelCtrl.text.trim(),
                  'year': yearCtrl.text.trim(),
                  'licensePlate': plateCtrl.text.trim().toUpperCase(),
                  'type': selectedType,
                });
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vehicle updated successfully')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteVehicleDialog(Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vehicle'),
        content: Text(
          'Are you sure you want to delete vehicle ${vehicle.licensePlate}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _vehicleService.deleteVehicle(vehicle.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Vehicle ${vehicle.licensePlate} deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting vehicle: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
              title: Text('No active monitoring sessions'),
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

// Custom formatter for license plate input (ABC-123 format)
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
