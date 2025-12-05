import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import '../models/user.dart';
import '../models/emergency_contact.dart';
import '../auth_screen.dart';
import '../widgets/shared/app_sidebar.dart';
import '../constants/app_colors.dart';
import '../services/emergency_contact_service.dart';

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

  
  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  // Real-time data
  double _driverAlertness = 82.9;
  double _currentSpeed = 72.7;
  int _tripProgress = 48;
  int _heartRate = 72;
  double _driveTime = 2.25; // in hours

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

  void _startDataUpdate() {
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      setState(() {
        _driverAlertness = 75 + _random.nextDouble() * 20;
        _currentSpeed = 65 + _random.nextDouble() * 15;
        _heartRate = 68 + _random.nextInt(8);
        _driveTime += 0.01;
      });
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
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
                _buildStaggeredItem(
                  isMobile
                      ? Column(
                          children: [
                            _buildDriverAlertnessCard(),
                            const SizedBox(height: 16),
                            _buildCurrentSpeedCard(),
                            const SizedBox(height: 16),
                            _buildTripProgressCard(),
                            const SizedBox(height: 16),
                            _buildSafetyStatusCard(),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: _buildDriverAlertnessCard()),
                            const SizedBox(width: 20),
                            Expanded(child: _buildCurrentSpeedCard()),
                            const SizedBox(width: 20),
                            Expanded(child: _buildTripProgressCard()),
                            const SizedBox(width: 20),
                            Expanded(child: _buildSafetyStatusCard()),
                          ],
                        ),
                  3,
                ),
                const SizedBox(height: 32),
                _buildStaggeredItem(_buildTabBar(), 4),
                const SizedBox(height: 32),
                _buildStaggeredItem(
                  isMobile
                      ? Column(
                          children: [
                            if (_selectedTab == 0) ...[
                              _buildDriverAlertnessTrend(),
                              const SizedBox(height: 20),
                              _buildTripInformation(),
                            ] else if (_selectedTab == 1) ...[
                              // Placeholder for Location Tab content if it was split
                              _buildLocationTab(),
                            ] else ...[
                              // Placeholder for Safety Tools Tab content
                              _buildSafetyToolsTab(),
                            ],
                          ],
                        )
                      : Builder(
                          builder: (context) {
                            if (_selectedTab == 0) return _buildLiveStatusTab();
                            if (_selectedTab == 1) return _buildLocationTab();
                            return _buildSafetyToolsTab();
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

  Widget _buildCurrentSpeedCard() {
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
                'Current Speed',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              Icon(Icons.speed, color: Colors.grey[400], size: 20),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _currentSpeed.toStringAsFixed(13),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'mph',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Highway 101 North',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripProgressCard() {
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
                'Trip Progress',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              Icon(Icons.navigation, color: Colors.grey[400], size: 20),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '$_tripProgress%',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _tripProgress / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFFE0E0E0),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.passengerPrimary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'ETA: 3:45 PM',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
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
          const SizedBox(width: 8),
          _buildTab('Safety Tools', 2),
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
                  const SizedBox(height: 20),
                  _buildTripInformation(),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildDriverAlertnessTrend()),
                  const SizedBox(width: 20),
                  Expanded(child: _buildTripInformation()),
                ],
              );
      },
    );
  }

  Widget _buildDriverAlertnessTrend() {
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
            'Driver Alertness Trend',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Real-time monitoring over the last 90 minutes',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 300,
            child: CustomPaint(
              painter: AlertnessTrendPainter(),
              size: const Size(double.infinity, 300),
            ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Driver Break Due',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              const Text(
                'In 45 minutes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFA726),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Driver Health Indicators',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Real-time biometric and behavioral monitoring',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildHealthIndicator(
                icon: Icons.visibility,
                value: 'Normal',
                label: 'Eye Movement',
                color: const Color(0xFF2196F3),
              )),
              const SizedBox(width: 16),
              Expanded(child: _buildHealthIndicator(
                icon: Icons.favorite,
                value: '$_heartRate BPM',
                label: 'Heart Rate',
                color: const Color(0xFFE91E63),
              )),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildHealthIndicator(
                icon: Icons.show_chart,
                value: 'Stable',
                label: 'Head Position',
                color: const Color(0xFF4CAF50),
              )),
              const SizedBox(width: 16),
              Expanded(child: _buildHealthIndicator(
                icon: Icons.access_time,
                value: '${_driveTime.toStringAsFixed(0)}h ${((_driveTime % 1) * 60).toInt()}m',
                label: 'Drive Time',
                color: const Color(0xFF9C27B0),
              )),
            ],
          ),
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

  Widget _buildHealthIndicator({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
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

  Widget _buildSafetyToolsTab() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildEmergencyActionsCard()),
        const SizedBox(width: 20),
        Expanded(child: _buildSafetyChecklistCard()),
      ],
    );
  }

  Widget _buildEmergencyActionsCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Emergency Actions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Immediate safety controls',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),

          // Call 911 Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                _showCall911Dialog();
              },
              icon: const Icon(Icons.phone, size: 22),
              label: const Text(
                'Call 911',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Alert Driver Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () {
                _showAlertDriverDialog();
              },
              icon: const Icon(Icons.warning_amber, size: 22),
              label: const Text(
                'Alert Driver (Sound)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFA726),
                side: const BorderSide(color: Color(0xFFFFA726), width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Contact Emergency Contacts Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () {
                _showEmergencyContactsDialog();
              },
              icon: const Icon(Icons.contact_phone, size: 22),
              label: const Text(
                'Contact Emergency Contacts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey[300]!, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Share Location Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () {
                _showShareLocationDialog();
              },
              icon: const Icon(Icons.location_on, size: 22),
              label: const Text(
                'Share Location with Family',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey[300]!, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Emergency Contact Information
          const Text(
            'Emergency Contact Information',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Quick access to important contacts',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),

          // Primary Emergency Contact
          _buildContactCard(
            title: 'Primary Emergency Contact',
            name: 'Sarah Johnson (Spouse)',
            phone: '+1 (555) 123-4567',
          ),
          const SizedBox(height: 16),

          // Fleet Manager Contact
          _buildContactCard(
            title: 'Fleet Manager',
            name: 'Mike Chen',
            phone: '+1 (555) 987-6543',
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required String title,
    required String name,
    required String phone,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            phone,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Calling $name...')),
                );
              },
              icon: const Icon(Icons.phone, size: 18),
              label: const Text('Call'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5E6AD2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildSafetyChecklistCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Safety Checklist',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pre-trip and ongoing safety measures',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),

          _buildChecklistItem(
            'Driver alertness monitoring active',
            true,
          ),
          const SizedBox(height: 20),

          _buildChecklistItem(
            'Emergency contacts configured',
            true,
          ),
          const SizedBox(height: 20),

          _buildChecklistItem(
            'GPS tracking enabled',
            true,
          ),
          const SizedBox(height: 20),

          _buildChecklistItem(
            'Driver break recommended in 45 min',
            false,
            isWarning: true,
          ),
          const SizedBox(height: 20),

          _buildChecklistItem(
            'Vehicle systems normal',
            true,
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String text, bool isActive, {bool isWarning = false}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isWarning
                ? const Color(0xFFFFA726)
                : (isActive ? const Color(0xFF4CAF50) : Colors.grey[400]),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: isWarning ? const Color(0xFFFFA726) : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

// Dialog methods
  void _showCall911Dialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call 911'),
        content: const Text('This will immediately call emergency services.\n\nAre you sure?'),
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
                  content: Text('Calling 911...'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Call 911'),
          ),
        ],
      ),
    );
  }

  void _showAlertDriverDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alert Driver'),
        content: const Text('This will play a loud alert sound to wake the driver.\n\nProceed?'),
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
                  content: Text('Alert sound playing...'),
                  backgroundColor: Color(0xFFFFA726),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFA726)),
            child: const Text('Alert Driver'),
          ),
        ],
      ),
    );
  }

  void _showEmergencyContactsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Emergency Contacts'),
        content: const Text('This will send an alert message to all emergency contacts.\n\nContinue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Emergency contacts notified')),
              );
            },
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );
  }

  void _showShareLocationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Location'),
        content: const Text('Share your current location with family members?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Location shared with family')),
              );
            },
            child: const Text('Share'),
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