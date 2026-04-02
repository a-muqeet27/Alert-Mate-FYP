import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import '../models/user.dart';
import '../models/emergency_contact.dart';
import '../auth_screen.dart';
import '../widgets/shared/app_sidebar.dart';
import '../constants/app_colors.dart';
import '../services/emergency_contact_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vehicle.dart';
import '../services/vehicle_service.dart';
import '../services/monitoring_service.dart';

class PassengerDashboard extends StatefulWidget {
  final User user;

  const PassengerDashboard({Key? key, required this.user}) : super(key: key);

  @override
  State<PassengerDashboard> createState() => _PassengerDashboardState();
}

class _PassengerDashboardState extends State<PassengerDashboard>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  int _selectedTab = 0;
  final Random _random = Random();
  late EmergencyContactService _emergencyContactService;
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

  @override
  void initState() {
    super.initState();
    _emergencyContactService = EmergencyContactService();
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
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.black87),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          'Passenger Dashboard',
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
              backgroundColor: AppColors.passengerPrimary,
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
                  role: 'passenger',
                  user: widget.user,
                  selectedIndex: _selectedIndex,
                  onMenuItemTap: (index) => setState(() => _selectedIndex = index),
                  menuItems: const [
                    MenuItem(icon: Icons.home_outlined, title: 'Dashboard'),
                    MenuItem(icon: Icons.phone_outlined, title: 'Emergency'),
                  ],
                  accentColor: AppColors.passengerPrimary,
                  accentLightColor: AppColors.passengerLight,
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
          role: 'passenger',
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
          accentColor: AppColors.passengerPrimary,
          accentLightColor: AppColors.passengerLight,
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
        final isMobile = constraints.maxWidth < 768;
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMobile) ...[
                  _buildStaggeredItem(
                    Text(
                      'Passenger Safety Monitor',
                      style: TextStyle(
                        fontSize: isMobile ? 24 : 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    0,
                  ),
                  SizedBox(height: isMobile ? 6 : 8),
                  _buildStaggeredItem(
                    Text(
                      'Real-time monitoring of driver status and trip safety',
                      style: TextStyle(
                        fontSize: isMobile ? 13 : 16,
                        color: Colors.black54,
                      ),
                    ),
                    1,
                  ),
                ],
                const SizedBox(height: 32),
                _buildStaggeredItem(
                  _buildEmergencyControlsCard(),
                  2,
                ),
                const SizedBox(height: 24),
                // License plate lookup section (Passenger enters plate to view live status/history)
                _buildStaggeredItem(
                  _buildPlateLookupSection(),
                  2,
                ),
                const SizedBox(height: 24),
                // Tab bar (Live Status / Location)
                const SizedBox(height: 8),
                _buildStaggeredItem(_buildTabBar(), 4),
                const SizedBox(height: 32),
                _buildStaggeredItem(
                  isMobile
                      ? Column(
                          children: [
                            if (_selectedTab == 0) ...[
                              _buildDriverAlertnessTrend(),
                            ] else if (_selectedTab == 1) ...[
                              _buildLocationTab(),
                            ],
                          ],
                        )
                      : Builder(
                          builder: (context) {
                            if (_selectedTab == 0) return _buildLiveStatusTab();
                            return _buildLocationTab();
                          },
                        ),
                  5,
                ),
              ],
            ),
          ),
        );
      },
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
            'Find Driver by License Plate',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _plateController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Enter license plate (e.g., ABC-123)',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _isSearchingPlate ? null : _searchByPlate,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(_isSearchingPlate ? 'Searching...' : 'Search'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.passengerPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          if (_plateError != null) ...[
            const SizedBox(height: 8),
            Text(
              _plateError!,
              style: const TextStyle(fontSize: 13, color: Colors.red),
            ),
          ],
          const SizedBox(height: 16),
          _buildPlateLookupResults(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Basic vehicle & driver info from Firestore
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vehicle & Driver',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              if (v != null) ...[
                _buildTripInfoRow('Driver', v.driverName ?? (driverId ?? 'Unknown')),
                const SizedBox(height: 8),
                _buildTripInfoRow('Vehicle', '${v.make} ${v.model}'),
                const SizedBox(height: 8),
                _buildTripInfoRow('License Plate', v.licensePlate),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (driverId != null && driverId.isNotEmpty)
          _buildLiveStatusCards(driverId)
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: const Text('No live data (no driver assigned)', style: TextStyle(fontSize: 13, color: Colors.black54)),
          ),
        const SizedBox(height: 16),
        // History from RTDB history node
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'History',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              if (driverId == null || driverId.isEmpty)
                const Text('No history available', style: TextStyle(fontSize: 13, color: Colors.black54))
              else
                StreamBuilder<Map<String, dynamic>>(
                  stream: _monitoringService.getDriverHistory(driverId),
                  builder: (context, snapshot) {
                    final history = snapshot.data ?? {};
                    if (history.isEmpty) {
                      return const Text('No history recorded yet', style: TextStyle(fontSize: 13, color: Colors.black54));
                    }
                    // Render as simple key/value table
                    final entries = history.entries.toList();
                    // Not all nodes have time keys; show as-is
                    return Table(
                      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        const TableRow(
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Field', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Value', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                            ),
                          ],
                        ),
                        ...entries.map((e) => TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(e.key.toString(), style: const TextStyle(fontSize: 13, color: Colors.black87)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(e.value.toString(), style: const TextStyle(fontSize: 13, color: Colors.black87)),
                            ),
                          ],
                        )),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  // Two-card row: Driver Alertness + Safety Status based on live RTDB stats
  Widget _buildLiveStatusCards(String driverId) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final cards = StreamBuilder<Map<String, dynamic>>(
      stream: _monitoringService.getCurrentStats(driverId),
      builder: (context, snapshot) {
        final hasLive = snapshot.hasData && (snapshot.data?.isNotEmpty == true);
        if (!hasLive) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: const Text('Driver is not active', style: TextStyle(fontSize: 13, color: Colors.black54)),
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
  }

  Widget _buildDriverStateBadgeCard(bool drowsy) {
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
                'Live Driver Status',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              Icon(Icons.podcasts, color: Colors.grey[400], size: 20),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(drowsy ? Icons.warning_amber : Icons.check_circle,
                  color: drowsy ? Colors.red : AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                drowsy ? 'Drowsy' : 'Normal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: drowsy ? Colors.red : AppColors.success,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSafetyStatusCardUI(bool safe, bool drowsy, Color statusColor) {
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
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                safe ? 'Safe' : (drowsy ? 'Critical' : 'Break Recommended'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            safe ? 'All systems active' : (drowsy ? 'Drowsiness detected' : 'Consider taking a short break'),
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyControlsCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2), width: 2),
      ),
      child: Column(
        children: [
          const Text(
            'Emergency Controls',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use only in case of emergency',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: () {
                _showEmergencyDialog();
              },
              icon: const Icon(Icons.phone, size: 24),
              label: const Text(
                'EMERGENCY SOS',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
            ),
          ),
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
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.passengerPrimary),
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

  Widget _buildTabBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildTab('Live Status', 0),
          const SizedBox(width: 8),
          _buildTab('Location', 1),
        ],
      ),
    );
  }

  Widget _buildTab(String text, int index) {
    final isActive = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? const Border(
            bottom: BorderSide(color: AppColors.passengerPrimary, width: 3),
          )
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? AppColors.passengerPrimary : Colors.black54,
          ),
        ),
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

  Widget _buildTripInformation() {
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
            'Trip Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Current journey details',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          _buildTripInfoRow('Departure', 'San Francisco, CA'),
          const SizedBox(height: 20),
          _buildTripInfoRow('Destination', 'Los Angeles, CA'),
          const SizedBox(height: 20),
          _buildTripInfoRow('Distance Remaining', '245 miles'),
          const SizedBox(height: 20),
          _buildTripInfoRow('Estimated Arrival', '3:45 PM'),
          const SizedBox(height: 20),
          if (_selectedVehicle?.location != null && _selectedVehicle!.location!.isNotEmpty)
            _buildTripInfoRow('Current Location', _selectedVehicle!.location!),
        ],
      ),
    );
  }

  Widget _buildTripInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationTab() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_on_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'Live Location Tracking',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'GPS tracking and route display coming soon',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
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
            isMobile
                ? Column(
                    children: [
                      _buildEmergencyServiceCard(
                        'Police',
                        '15',
                        Icons.local_police,
                        const Color(0xFF2196F3),
                        const Color(0xFFE3F2FD),
                        isMobile,
                      ),
                      const SizedBox(height: 12),
                      _buildEmergencyServiceCard(
                        'Ambulance',
                        '1122',
                        Icons.local_hospital,
                        Colors.red,
                        const Color(0xFFFFEBEE),
                        isMobile,
                      ),
                      const SizedBox(height: 12),
                      _buildEmergencyServiceCard(
                        'Fire Department',
                        '16',
                        Icons.local_fire_department,
                        const Color(0xFFFF6F00),
                        const Color(0xFFFFF3E0),
                        isMobile,
                      ),
                      const SizedBox(height: 12),
                      _buildEmergencyServiceCard(
                        'Motorway Police',
                        '130',
                        Icons.car_crash,
                        const Color(0xFF4CAF50),
                        const Color(0xFFE8F5E9),
                        isMobile,
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      SizedBox(
                        width: 280,
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
                        width: 280,
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
                        width: 280,
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
                        width: 280,
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
            _buildEmergencyContactsTable(),
          ],
        ),
      ),
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
              fontSize: isMobile ? 28 : 32,
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

  Widget _buildEmergencyContactsTable() {
    return StreamBuilder<List<EmergencyContact>>(
      stream: _emergencyContactService.getEmergencyContactsStream(widget.user.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(28),
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
            child: Text('Error loading contacts: ${snapshot.error}'),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(28),
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
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final contacts = snapshot.data ?? [];

        return Container(
          padding: const EdgeInsets.all(28),
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
                      const Text(
                        'Emergency Contacts',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage your emergency contact list',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      _showContactDialog(context: context);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Contact'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 800),
                  child: Table(
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
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Last system test: Just now • ${contacts.length} active contacts',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
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

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black54,
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
        activeColor: const Color(0xFF2196F3),
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
                      SnackBar(content: Text('${contact.name} removed')),
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

  void _showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency SOS'),
        content: const Text(
          'This will immediately alert emergency services and your emergency contacts.\n\nAre you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Emergency services have been alerted'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Call Emergency'),
          ),
        ],
      ),
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
                      const SnackBar(content: Text('Select at least one method')),
                    );
                    return;
                  }
                  
                  Navigator.pop(ctx);
                  
                  try {
                    if (contact == null) {
                      await _emergencyContactService.addEmergencyContact(
                        userId: widget.user.id,
                        userRole: 'passenger',
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
                          const SnackBar(content: Text('Contact added')),
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
                          const SnackBar(content: Text('Contact updated')),
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
      ..color = const Color(0xFF9B59B6)
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