import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../models/user.dart';
import '../models/vehicle.dart';
import '../models/emergency_contact.dart';
import '../services/vehicle_service.dart';
import '../services/emergency_contact_service.dart';
import '../services/monitoring_service.dart';
import '../constants/app_colors.dart';
import '../widgets/shared/app_sidebar.dart';
import '../auth_screen.dart';

class OwnerDashboard extends StatefulWidget {
  final User user;

  const OwnerDashboard({Key? key, required this.user}) : super(key: key);

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> with TickerProviderStateMixin {
  final VehicleService _vehicleService = VehicleService();
  final MonitoringService _monitoringService = MonitoringService();
  late EmergencyContactService _emergencyContactService;

  int _selectedIndex = 0;
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = ''; // Separate state for search to ensure rebuilds
  String _statusFilter = 'All Status';
  String _typeFilter = 'All Types';
  bool _showClearButton = false;
  Timer? _debounceTimer; // Debounce timer for search


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
    _debounceTimer?.cancel();
    _searchController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // Debounced search update
  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _searchQuery != value) {
        setState(() {
          _searchQuery = value;
          _showClearButton = value.isNotEmpty;
        });
      }
    });
  }

  // Check if driver has had a session in the last 3 days
  Future<bool> _hasRecentSession(String driverId) async {
    try {
      final sessions = await _monitoringService.getDriverSessions(driverId);
      if (sessions.isEmpty) return false;

      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      
      // Check if any session started in the last 3 days
      for (final session in sessions) {
        final startTime = session['startTime'] as int?;
        if (startTime != null && startTime >= threeDaysAgo) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error checking recent session for driver $driverId: $e');
      return false;
    }
  }

  // Count unique drivers who have had sessions in the last 3 days
  Future<int> _countActiveDrivers(List<String> driverIds) async {
    if (driverIds.isEmpty) return 0;

    int activeCount = 0;
    for (final driverId in driverIds) {
      if (await _hasRecentSession(driverId)) {
        activeCount++;
      }
    }
    return activeCount;
  }

  Future<void> _showAddVehicleDialog() async {
    final formKey = GlobalKey<FormState>();
    String vehicleType = 'Car';
    String make = '';
    String model = '';
    String year = '';
    String licensePlate = '';
    bool willDrive = false;

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
                    value: vehicleType,
                    decoration: const InputDecoration(labelText: 'Type *'),
                    items: const [
                      DropdownMenuItem(value: 'Car', child: Text('Car')),
                      DropdownMenuItem(value: 'Bus', child: Text('Bus')),
                      DropdownMenuItem(value: 'Van', child: Text('Van')),
                      DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                      DropdownMenuItem(value: 'Rickshaw', child: Text('Rickshaw')),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Type is required';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setDialogState(() {
                        vehicleType = value!;
                      });
                    },
                    onSaved: (value) => vehicleType = value!,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Make *'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Make is required';
                      }
                      if (value.trim().length < 2) {
                        return 'Make must be at least 2 characters';
                      }
                      return null;
                    },
                    onSaved: (value) => make = value!.trim(),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Model *'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Model is required';
                      }
                      if (value.trim().length < 2) {
                        return 'Model must be at least 2 characters';
                      }
                      return null;
                    },
                    onSaved: (value) => model = value!.trim(),
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
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('I will be driving this vehicle'),
                    subtitle: const Text('Assign this vehicle to me'),
                    value: willDrive,
                    onChanged: (value) {
                      setDialogState(() {
                        willDrive = value!;
                      });
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

                    try {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Adding vehicle...')),
                      );

                      final result = await _vehicleService.addVehicleWithDriverCheck(
                        make: make,
                        model: model,
                        year: year,
                        licensePlate: licensePlate,
                        ownerId: widget.user.id,
                        ownerEmail: widget.user.email,
                        willOwnerDrive: willDrive,
                        type: vehicleType,
                      );

                      if (result == null && willDrive) {
                        if (mounted) {
                          _showDriverRegistrationDialog();
                        }
                      } else if (result != null && willDrive && result.assignedDriverId == null) {
                        // Vehicle was created but not assigned because owner already has one
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Vehicle added! Since you already have a vehicle assigned, this one will be automatically assigned to the next driver who signs up.',
                              ),
                              backgroundColor: AppColors.primary,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(willDrive
                                  ? 'Vehicle added and assigned to you!'
                                  : 'Vehicle added successfully'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        // Show error in a dialog for better visibility
                        showDialog(
                          context: context,
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
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const AuthScreen(
                    initialDashboardIndex: 0,
                    initialIsSignIn: false,
                    isOwnerBecomingDriver: true,
                  ),
                ),
              );
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
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.black87),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          'Owner Dashboard',
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
              backgroundColor: AppColors.primary,
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
            role: 'owner',
            user: widget.user is User ? widget.user : null,
            selectedIndex: _selectedIndex,
            onMenuItemTap: (index) => setState(() => _selectedIndex = index),
            menuItems: const [
              MenuItem(icon: Icons.home_outlined, title: 'Dashboard'),
              MenuItem(icon: Icons.phone_outlined, title: 'Emergency'),
            ],
            accentColor: AppColors.primary,
            accentLightColor: AppColors.primaryLight,
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
          role: 'owner',
          user: widget.user is User ? widget.user : null,
          selectedIndex: _selectedIndex,
          onMenuItemTap: (index) {
            setState(() => _selectedIndex = index);
            Navigator.pop(context);
          },
          menuItems: const [
            MenuItem(icon: Icons.home_outlined, title: 'Dashboard'),
            MenuItem(icon: Icons.phone_outlined, title: 'Emergency'),
          ],
          accentColor: AppColors.primary,
          accentLightColor: AppColors.primaryLight,
        ),
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
                if (!isMobile) _buildStaggeredItem(
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vehicle Owner Dashboard',
                            style: TextStyle(
                              fontSize: isMobile ? 24 : isTablet ? 28 : 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: isMobile ? 6 : 8),
                          Text(
                            'Monitor and manage your vehicle fleet',
                            style: TextStyle(
                              fontSize: isMobile ? 13 : isTablet ? 14 : 16,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      if (!isMobile)
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Export report'))
                                );
                              },
                              icon: Icon(Icons.download, size: isTablet ? 16 : 18),
                              label: Text('Export Report', style: TextStyle(fontSize: isTablet ? 13 : 14)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                                padding: EdgeInsets.symmetric(
                                    horizontal: isTablet ? 16 : 20,
                                    vertical: isTablet ? 12 : 16),
                                elevation: 0,
                                side: BorderSide(color: Colors.grey[300]!),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            SizedBox(width: isTablet ? 8 : 12),
                            IconButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Open settings'))
                                );
                              },
                              icon: Icon(Icons.settings, size: isTablet ? 20 : 24),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                side: BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  0,
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(height: isMobile ? 24 : 32),
                StreamBuilder<List<Vehicle>>(
                  stream: _vehicleService.getVehiclesByOwnerStream(widget.user.id),
                  builder: (context, snapshot) {
                    final vehicles = snapshot.data ?? [];
                    final isMobile = MediaQuery.of(context).size.width < 768;
                    final isTablet = MediaQuery.of(context).size.width < 1024 && !isMobile;

                    // Calculate dynamic safety score based on vehicle data
                    final criticalCount = vehicles.where((v) => v.status.toLowerCase() == 'critical').length;
                    final vehiclesWithAlertness = vehicles.where((v) => v.alertness > 0).toList();
                    double safetyScore = 10.0;
                    if (vehicles.isNotEmpty) {
                      // Calculate average alertness (0-100 scale, convert to 0-10)
                      if (vehiclesWithAlertness.isNotEmpty) {
                        final avgAlertness = vehiclesWithAlertness.fold<int>(0, (sum, v) => sum + v.alertness) / vehiclesWithAlertness.length;
                        safetyScore = (avgAlertness / 10).clamp(0.0, 10.0);
                      }
                      // Reduce score for critical alerts
                      safetyScore = (safetyScore - (criticalCount * 1.5)).clamp(0.0, 10.0);
                    }
                    final safetyScoreText = '${safetyScore.toStringAsFixed(1)}/10';
                    final safetyColor = safetyScore >= 7.0 ? AppColors.success : (safetyScore >= 5.0 ? Colors.orange : AppColors.danger);

                    // Get unique driver IDs from vehicles
                    final driverIds = vehicles
                        .where((v) => v.assignedDriverId != null && v.assignedDriverId!.isNotEmpty)
                        .map((v) => v.assignedDriverId!)
                        .toSet()
                        .toList();

                    // Check which drivers have had sessions in the last 3 days
                    return FutureBuilder<int>(
                      future: _countActiveDrivers(driverIds),
                      builder: (context, activeCountSnapshot) {
                        final activeDriverCount = activeCountSnapshot.data ?? 0;

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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Active Drivers',
                                  activeDriverCount.toString(),
                                  activeDriverCount == 1 ? 'Currently driving' : 'Currently driving',
                                  Icons.people_outline,
                                  AppColors.success,
                                  isMobile,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'Critical Alerts',
                                  criticalCount.toString(),
                                  'Requires attention',
                                  Icons.warning_amber_rounded,
                                  AppColors.danger,
                                  isMobile,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Safety Score',
                                  safetyScoreText,
                                  'Based on alertness',
                                  Icons.shield_outlined,
                                  safetyColor,
                                  isMobile,
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
                              )),
                              const SizedBox(width: 16),
                              Expanded(child: _buildStatCard(
                                'Active Drivers',
                                activeDriverCount.toString(),
                                activeDriverCount == 1 ? 'Currently driving' : 'Currently driving',
                                Icons.people_outline,
                                AppColors.success,
                                isMobile,
                              )),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: _buildStatCard(
                                'Critical Alerts',
                                criticalCount.toString(),
                                'Requires attention',
                                Icons.warning_amber_rounded,
                                AppColors.danger,
                                isMobile,
                              )),
                              const SizedBox(width: 16),
                              Expanded(child: _buildStatCard(
                                'Safety Score',
                                safetyScoreText,
                                'Based on alertness',
                                Icons.shield_outlined,
                                safetyColor,
                                isMobile,
                              )),
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
                              )),
                              const SizedBox(width: 20),
                              Expanded(child: _buildStatCard(
                                'Active Drivers',
                                activeDriverCount.toString(),
                                activeDriverCount == 1 ? 'Currently driving' : 'Currently driving',
                                Icons.people_outline,
                                AppColors.success,
                                isMobile,
                              )),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(child: _buildStatCard(
                                'Critical Alerts',
                                criticalCount.toString(),
                                'Requires attention',
                                Icons.warning_amber_rounded,
                                AppColors.danger,
                                isMobile,
                              )),
                              const SizedBox(width: 20),
                              Expanded(child: _buildStatCard(
                                'Safety Score',
                                safetyScoreText,
                                'Based on alertness',
                                Icons.shield_outlined,
                                safetyColor,
                                isMobile,
                              )),
                            ],
                          ),
                        ],
                      ),
                      1,
                        );
                      },
                    );
                  },
                ),
                SizedBox(height: isMobile ? 24 : 32),
                _buildStaggeredItem(
                  _buildFleetOverview(),
                  2,
                ),
                const SizedBox(height: 32),
              ],
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

  Widget _buildStatCard(String title, String value, String subtitle, IconData icon, Color color, [bool isMobile = false]) {
    return Container(
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
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final vehicles = snapshot.data ?? [];

        // --- FILTERING ---
        final searchLower = _searchQuery.toLowerCase();
        List<Vehicle> filteredVehicles = vehicles.where((vehicle) {
          bool matchesSearch = _searchQuery.isEmpty ||
              vehicle.licensePlate.toLowerCase().contains(searchLower) ||
              (vehicle.driverName?.toLowerCase().contains(searchLower) ?? false) ||
              vehicle.status.toLowerCase().contains(searchLower) ||
              (vehicle.location?.toLowerCase().contains(searchLower) ?? false) ||
              '${vehicle.make} ${vehicle.model}'.toLowerCase().contains(searchLower);

          bool matchesStatusFilter = _statusFilter == 'All Status' || vehicle.status == _statusFilter;
          bool matchesTypeFilter = _typeFilter == 'All Types' || vehicle.type == _typeFilter;

          return matchesSearch && matchesStatusFilter && matchesTypeFilter;
        }).toList();

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Vehicle(s) Details',
                    style: TextStyle(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  if (!isMobile)
                    ElevatedButton.icon(
                      onPressed: _showAddVehicleDialog,
                      icon: Icon(Icons.add, size: isMobile ? 16 : 18),
                      label: Text('Add Vehicle', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 20,
                            vertical: isMobile ? 10 : 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: isMobile ? 16 : 20),
              if (!isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
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
                                  DropdownMenuItem(value: 'Break', child: Text('Break')),
                                  DropdownMenuItem(value: 'Critical', child: Text('Critical')),
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
                        ],
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 250,
                      child: TextField(
                        key: const Key('fleet_search_field'),
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search vehicles...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _debounceTimer?.cancel();
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _showClearButton = false;
                              });
                            },
                          )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF2196F3), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              if (isMobile) ...[
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
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
                            DropdownMenuItem(value: 'Break', child: Text('Break')),
                            DropdownMenuItem(value: 'Critical', child: Text('Critical')),
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextField(
                    controller: _searchController,
                    enabled: true,
                    autofocus: false,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search vehicles...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _debounceTimer?.cancel();
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _showClearButton = false;
                          });
                        },
                      )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2196F3), width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    ),
                  ),
                ),
              ],
              SizedBox(height: isMobile ? 16 : 16),
              if (_searchController.text.isNotEmpty || _statusFilter != 'All Status' || _typeFilter != 'All Types')
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
                      if (_searchController.text.isNotEmpty || _statusFilter != 'All Status' || _typeFilter != 'All Types') ...[
                        SizedBox(width: isMobile ? 6 : 8),
                        TextButton.icon(
                          onPressed: () {
                            _debounceTimer?.cancel();
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _showClearButton = false;
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
              SizedBox(height: isMobile ? 8 : 8),
              if (filteredVehicles.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 20 : 40),
                    child: Column(
                      children: [
                        Icon(
                          _searchController.text.isNotEmpty || _statusFilter != 'All Status'
                              ? Icons.search_off
                              : Icons.directions_car_outlined,
                          size: isMobile ? 40 : 48,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: isMobile ? 12 : 16),
                        Text(
                          _searchController.text.isNotEmpty || _statusFilter != 'All Status'
                              ? 'No vehicles match your search'
                              : 'No vehicles found',
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_searchController.text.isNotEmpty || _statusFilter != 'All Status') ...[
                          SizedBox(height: isMobile ? 6 : 8),
                          TextButton(
                            onPressed: () {
                              _debounceTimer?.cancel();
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _showClearButton = false;
                                _statusFilter = 'All Status';
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
                        0: FixedColumnWidth(120),
                        1: FixedColumnWidth(150),
                        2: FixedColumnWidth(100),
                        3: FixedColumnWidth(150),
                        4: FixedColumnWidth(150),
                        5: FixedColumnWidth(120),
                        6: FixedColumnWidth(100),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          children: [
                            _buildTableHeader('License Plate', isMobile),
                            _buildTableHeader('Driver', isMobile),
                            _buildTableHeader('Status', isMobile),
                            _buildTableHeader('Alertness', isMobile),
                            _buildTableHeader('Location', isMobile),
                            _buildTableHeader('Last Update', isMobile),
                            _buildTableHeader('Actions', isMobile),
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
  }
  Widget _buildEmergency() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emergency Services',
              style: TextStyle(
                fontSize: isMobile ? 24 : 32,
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
            SizedBox(height: isMobile ? 24 : 32),
            _buildEmergencyContactsTable(isMobile),
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
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text('Error loading contacts: ${snapshot.error}'),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final contacts = snapshot.data ?? [];

        return Container(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Emergency Contacts',
                    style: TextStyle(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      _showAddContactDialog();
                    },
                    icon: Icon(Icons.add, size: isMobile ? 16 : 18),
                    label: Text('Add Contact', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 12 : 20,
                          vertical: isMobile ? 10 : 12),
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
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmergencyServiceCard(String title, String number, IconData icon, Color color, Color bgColor, [bool isMobile = false]) {
    return Container(
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
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: isMobile ? 20 : 24),
          ),
          SizedBox(height: isMobile ? 16 : 24),
          Text(
            number,
            style: TextStyle(
              fontSize: isMobile ? 24 : 28,
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
        ],
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
                        SnackBar(content: Text('${nameController.text} added to emergency contacts')),
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
                        SnackBar(content: Text('${nameController.text} updated successfully')),
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
        _buildContactInfoCell(contact.phone, contact.email, isMobile),
        _buildPriorityBadgeCell(contact.priority, isMobile),
        _buildMethodsCell(contact.methods, isMobile),
        _buildStatusToggleCell(contact, isMobile),
        _buildContactActionsCell(contact, isMobile),
      ],
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

  // Helper methods for fleet overview table
  Widget _buildMobileVehicleCard(Vehicle vehicle) {
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
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  vehicle.driverName ?? 'Unassigned',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  vehicle.location ?? 'Unknown',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMobileRealtimeAlertness(vehicle),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              _buildMobileRealtimeLastUpdate(vehicle),
              const Spacer(),
              _buildActionsCell(vehicle, true),
            ],
          ),
        ],
      ),
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

  TableRow _buildVehicleRow(Vehicle vehicle, [bool isMobile = false]) {
    return TableRow(
      children: [
        _buildTableCell(vehicle.licensePlate, isMobile),
        _buildTableCell(vehicle.driverName ?? 'Unassigned', isMobile),
        _buildRealtimeStatusBadge(vehicle, isMobile),
        _buildRealtimeAlertnessCell(vehicle, isMobile),
        _buildTableCell(vehicle.location ?? 'Unknown', isMobile),
        _buildRealtimeLastUpdateCell(vehicle, isMobile),
        _buildActionsCell(vehicle, isMobile),
      ],
    );
  }

  // Real-time status badge that updates based on driver alertness
  Widget _buildRealtimeStatusBadge(Vehicle vehicle, [bool isMobile = false]) {
    if (vehicle.assignedDriverId == null) {
      return _buildStatusBadge('Unassigned', isMobile);
    }

    return StreamBuilder<Map<String, dynamic>>(
      stream: _monitoringService.getCurrentStats(vehicle.assignedDriverId!),
      builder: (context, snapshot) {
        String status = 'Inactive'; // Default to Inactive if no session

        // If we have real-time data, determine status based on alertness
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final stats = snapshot.data!;
          final alertness = stats['alertness'];
          final drowsinessDetected = stats['drowsinessDetected'] ?? false;

          if (alertness != null) {
            final alertnessValue = (alertness as num).toDouble();
            if (drowsinessDetected || alertnessValue < 50) {
              status = 'Critical';
            } else if (alertnessValue < 70) {
              status = 'Break'; // Suggest break
            } else {
              status = 'Active';
            }
          }
        } else {
          // No data means no active session
          status = 'Inactive';
        }

        return _buildStatusBadge(status, isMobile);
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
      case 'Break':
        color = AppColors.primary;
        break;
      case 'Critical':
        color = AppColors.danger;
        break;
      case 'Inactive':
        color = Colors.grey;
        break;
      case 'Unassigned':
        color = Colors.orange[700]!;
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
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Calling driver...'))
              );
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
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

  // Mobile real-time status badge
  Widget _buildMobileRealtimeStatusBadge(Vehicle vehicle) {
    if (vehicle.assignedDriverId == null) {
      return _buildStatusBadge('Unassigned', true);
    }

    return StreamBuilder<Map<String, dynamic>>(
      stream: _monitoringService.getCurrentStats(vehicle.assignedDriverId!),
      builder: (context, snapshot) {
        String status = 'Inactive'; // Default to Inactive if no session

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final stats = snapshot.data!;
          final alertness = stats['alertness'];
          final drowsinessDetected = stats['drowsinessDetected'] ?? false;

          if (alertness != null) {
            final alertnessValue = (alertness as num).toDouble();
            if (drowsinessDetected || alertnessValue < 50) {
              status = 'Critical';
            } else if (alertnessValue < 70) {
              status = 'Break';
            } else {
              status = 'Active';
            }
          }
        } else {
          // No data means no active session
          status = 'Inactive';
        }

        return _buildStatusBadge(status, true);
      },
    );
  }

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
