import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/driver_location.dart';
import '../../services/driver_location_service.dart';
import '../../constants/app_colors.dart';

/// Reusable live map widget that displays driver locations in real-time.
///
/// Features:
/// - Green markers for normal drivers, red pulsing markers for drowsiness alerts
/// - Popup with driver name, status, and last updated time
/// - Automatically filters out offline drivers
/// - Clean up Firestore listener on unmount
///
/// Usage:
/// ```dart
/// // Admin: show all drivers
/// LiveMap()
///
/// // Owner: show only specific drivers
/// LiveMap(filterDriverIds: ['driverId1', 'driverId2'])
/// ```
class LiveMap extends StatefulWidget {
  /// Optional list of driver IDs to display. If null, shows all non-offline drivers.
  final List<String>? filterDriverIds;

  /// Map area height when the parent does not bound total height (e.g. in a scroll view).
  /// When the parent supplies a finite max height, the map fills the space below the header.
  final double height;

  /// When false, only the map is shown (use if the parent already provides a title).
  final bool showHeader;

  const LiveMap({
    super.key,
    this.filterDriverIds,
    this.height = 450,
    this.showHeader = true,
  });

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> with TickerProviderStateMixin {
  final DriverLocationService _locationService = DriverLocationService();
  late AnimationController _pulseController;
  late StreamSubscription<List<DriverLocation>> _subscription;
  final MapController _mapController = MapController();

  List<DriverLocation> _drivers = [];
  String? _selectedDriverId;
  bool _isLoading = true;

  // Default center: Lahore, Pakistan
  static const LatLng _defaultCenter = LatLng(31.5204, 74.3587);
  static const double _defaultZoom = 12.0;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _startListening();
  }

  void _startListening() {
    final stream = widget.filterDriverIds != null
        ? _locationService.getDriversByIdsStream(widget.filterDriverIds!)
        : _locationService.getAllDriversStream();

    _subscription = stream.listen(
      (drivers) {
        if (mounted) {
          setState(() {
            _drivers = drivers;
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  @override
  void didUpdateWidget(LiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart listener if filter IDs changed
    if (_listsDiffer(widget.filterDriverIds, oldWidget.filterDriverIds)) {
      _subscription.cancel();
      _startListening();
    }
  }

  bool _listsDiffer(List<String>? a, List<String>? b) {
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _subscription.cancel();
    super.dispose();
  }

  DriverLocation? get _selectedDriver {
    if (_selectedDriverId == null) return null;
    try {
      return _drivers.firstWhere((d) => d.id == _selectedDriverId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final alertCount = _drivers.where((d) => d.drowsinessAlert).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tightHeight = constraints.hasBoundedHeight &&
            constraints.maxHeight.isFinite &&
            constraints.maxHeight > 0;

        final mapRadius = widget.showHeader
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              )
            : BorderRadius.circular(16);

        Widget mapArea = ClipRRect(
          borderRadius: mapRadius,
          child: _buildMapStack(isMobile),
        );

        if (!tightHeight) {
          mapArea = SizedBox(height: widget.height, child: mapArea);
        }

        final children = <Widget>[
          if (widget.showHeader) _buildHeader(isMobile, alertCount),
          if (tightHeight) Expanded(child: mapArea) else mapArea,
        ];

        return Container(
          height: tightHeight ? constraints.maxHeight : null,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: tightHeight ? MainAxisSize.max : MainAxisSize.min,
            children: children,
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isMobile, int alertCount) {
    final compact = MediaQuery.of(context).size.width < 520;

    final titleBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 8 : 10),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.map_outlined,
            color: AppColors.primary,
            size: isMobile ? 20 : 24,
          ),
        ),
        SizedBox(width: isMobile ? 12 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Live Driver Tracking',
                style: TextStyle(
                  fontSize: isMobile ? 16 : 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Real-Time Driver\'s Locations on Map',
                style: TextStyle(
                  fontSize: isMobile ? 12 : 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final badges = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        _buildCountBadge(
          _drivers.length.toString(),
          'Active',
          AppColors.success,
          isMobile,
        ),
        if (alertCount > 0)
          _buildCountBadge(
            alertCount.toString(),
            'Alert',
            AppColors.danger,
            isMobile,
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: 10),
                badges,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: titleBlock),
                badges,
              ],
            ),
    );
  }

  Widget _buildMapStack(bool isMobile) {
    if (_isLoading) {
      return _buildLoadingState();
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: _defaultZoom,
            onTap: (_, __) {
              if (_selectedDriverId != null) {
                setState(() => _selectedDriverId = null);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.alertmate.app',
              maxZoom: 19,
            ),
            MarkerLayer(
              markers:
                  _drivers.map((driver) => _buildMarker(driver)).toList(),
            ),
          ],
        ),
        if (_selectedDriver != null)
          _buildDriverInfoCard(_selectedDriver!, isMobile),
        Positioned(
          bottom: isMobile ? 12 : 16,
          left: isMobile ? 12 : 16,
          child: _buildLegend(isMobile),
        ),
        if (_drivers.isEmpty && !_isLoading) _buildEmptyState(isMobile),
      ],
    );
  }

  Widget _buildCountBadge(
      String count, String label, Color color, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 14,
        vertical: isMobile ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
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
            '$count $label',
            style: TextStyle(
              fontSize: isMobile ? 11 : 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Marker _buildMarker(DriverLocation driver) {
    final isDrowsy = driver.drowsinessAlert;
    final isSelected = _selectedDriverId == driver.id;
    final size = isSelected ? 48.0 : 40.0;

    return Marker(
      point: LatLng(driver.lat, driver.lng),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedDriverId =
                _selectedDriverId == driver.id ? null : driver.id;
          });
        },
        child: isDrowsy
            ? _buildPulsingMarker(driver, size, isSelected)
            : _buildNormalMarker(driver, size, isSelected),
      ),
    );
  }

  Widget _buildNormalMarker(
      DriverLocation driver, double size, bool isSelected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.success,
        border: Border.all(
          color: isSelected ? Colors.white : Colors.white70,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withValues(alpha: 0.4),
            blurRadius: isSelected ? 12 : 6,
            spreadRadius: isSelected ? 2 : 0,
          ),
        ],
      ),
      child: Icon(
        driver.isOnTrip ? Icons.directions_car : Icons.local_taxi,
        color: Colors.white,
        size: size * 0.45,
      ),
    );
  }

  Widget _buildPulsingMarker(
      DriverLocation driver, double size, bool isSelected) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseValue = _pulseController.value;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.75 + (pulseValue * 0.25)),
            border: Border.all(
              color: Colors.white,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3 + (pulseValue * 0.4)),
                blurRadius: 8 + (pulseValue * 14),
                spreadRadius: 1 + (pulseValue * 5),
              ),
            ],
          ),
          child: Icon(
            Icons.warning_rounded,
            color: Colors.white,
            size: size * 0.5,
          ),
        );
      },
    );
  }

  Widget _buildDriverInfoCard(DriverLocation driver, bool isMobile) {
    final isDrowsy = driver.drowsinessAlert;

    return Positioned(
      top: isMobile ? 12 : 16,
      right: isMobile ? 12 : 16,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: isMobile ? 240 : 280,
        padding: EdgeInsets.all(isMobile ? 14 : 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isDrowsy
                ? AppColors.danger.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.15),
            width: isDrowsy ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row with close button
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isDrowsy ? AppColors.dangerLight : AppColors.primaryLight,
                  ),
                  child: Icon(
                    isDrowsy ? Icons.warning_rounded : Icons.person,
                    color: isDrowsy ? AppColors.danger : AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    driver.name,
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _selectedDriverId = null),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Drowsiness alert banner
            if (isDrowsy) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.dangerLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 14, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Text(
                      'Drowsiness Alert Active',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Status
            _buildInfoRow(
              Icons.circle,
              'Status',
              driver.statusLabel,
              driver.isOnTrip ? AppColors.success : Colors.orange,
              isMobile,
            ),
            const SizedBox(height: 8),
            // Coordinates
            _buildInfoRow(
              Icons.location_on_outlined,
              'Location',
              '${driver.lat.toStringAsFixed(4)}, ${driver.lng.toStringAsFixed(4)}',
              Colors.grey[700]!,
              isMobile,
            ),
            const SizedBox(height: 8),
            // Last updated
            _buildInfoRow(
              Icons.access_time,
              'Updated',
              driver.timeAgo,
              Colors.grey[700]!,
              isMobile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    Color iconColor,
    bool isMobile,
  ) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: isMobile ? 11 : 12,
            color: Colors.grey[600],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildLegend(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 14,
        vertical: isMobile ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLegendItem(AppColors.success, 'Normal', isMobile),
          SizedBox(width: isMobile ? 12 : 16),
          _buildLegendItem(AppColors.danger, 'Drowsy Alert', isMobile),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 10 : 12,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return ColoredBox(
      color: Colors.grey.shade50,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
            SizedBox(height: 16),
            Text(
              'Loading Map...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isMobile) {
    return Positioned.fill(
      child: Container(
        color: Colors.white.withValues(alpha: 0.7),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_off_outlined,
                size: isMobile ? 40 : 56,
                color: Colors.grey[400],
              ),
              SizedBox(height: isMobile ? 12 : 16),
              Text(
                'No Active Drivers',
                style: TextStyle(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Driver Locations will Appear Here when Drivers are Online',
                style: TextStyle(
                  fontSize: isMobile ? 12 : 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
