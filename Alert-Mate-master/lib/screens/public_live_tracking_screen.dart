import 'package:flutter/material.dart';
import 'dart:async';
import '../services/tracking_service.dart';
import '../models/tracking_token.dart';
import '../constants/app_colors.dart';
import '../widgets/shared/live_map.dart';

class PublicLiveTrackingScreen extends StatefulWidget {
  final String tokenId;

  const PublicLiveTrackingScreen({Key? key, required this.tokenId}) : super(key: key);

  @override
  State<PublicLiveTrackingScreen> createState() => _PublicLiveTrackingScreenState();
}

class _PublicLiveTrackingScreenState extends State<PublicLiveTrackingScreen> {
  final TrackingService _trackingService = TrackingService();
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    // Update UI every second to show remaining time
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  String _formatTimeRemaining(Duration duration) {
    if (duration.inSeconds <= 0) return 'Expired';
    
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m remaining';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s remaining';
    } else {
      return '${seconds}s remaining';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/images/Alert Mate New.png',
              height: 32,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.location_on),
            ),
            const SizedBox(width: 8),
            const Text(
              'Live Tracking',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<TrackingToken?>(
        stream: _trackingService.streamTrackingToken(widget.tokenId),
        builder: (context, tokenSnapshot) {
          // Loading state
          if (tokenSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          // Token not found or expired
          if (!tokenSnapshot.hasData || tokenSnapshot.data == null) {
            return _buildErrorState(
              icon: Icons.link_off,
              title: 'Tracking Link Expired',
              message: 'This tracking link is no longer valid or has expired.',
            );
          }

          final token = tokenSnapshot.data!;

          // Stream driver location
          return StreamBuilder<Map<String, dynamic>?>(
            stream: _trackingService.streamDriverLocation(token.driverId),
            builder: (context, locationSnapshot) {
              // Loading location
              if (locationSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              // No location available
              if (!locationSnapshot.hasData || locationSnapshot.data == null) {
                return _buildErrorState(
                  icon: Icons.location_off,
                  title: 'Location Unavailable',
                  message: 'Driver is currently offline or location services are disabled.',
                );
              }

              final location = locationSnapshot.data!;
              final lat = location['lat'] as double;
              final lng = location['lng'] as double;
              final status = location['status'] as String;
              final drowsinessAlert = location['drowsinessAlert'] as bool;

              return SingleChildScrollView(
                child: Column(
                  children: [
                    // Vehicle Info Card
                    Container(
                      margin: EdgeInsets.all(isMobile ? 16 : 24),
                      padding: EdgeInsets.all(isMobile ? 20 : 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.directions_car,
                                  color: AppColors.primary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${token.vehicleMake} ${token.vehicleModel}',
                                      style: TextStyle(
                                        fontSize: isMobile ? 18 : 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      token.vehiclePlate,
                                      style: TextStyle(
                                        fontSize: isMobile ? 16 : 18,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          // Status Row
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoChip(
                                  icon: Icons.circle,
                                  label: status == 'on_trip' ? 'On Trip' : 
                                         status == 'idle' ? 'Idle' : 'Offline',
                                  color: status == 'on_trip' ? Colors.green :
                                         status == 'idle' ? Colors.orange : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildInfoChip(
                                  icon: drowsinessAlert ? Icons.warning : Icons.check_circle,
                                  label: drowsinessAlert ? 'Alert!' : 'Normal',
                                  color: drowsinessAlert ? Colors.red : Colors.green,
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Expiry Info
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.timer, color: AppColors.primary, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatTimeRemaining(token.timeRemaining),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Live Map
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
                      height: isMobile ? 400 : 500,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: LiveMap(
                          filterDriverIds: [token.driverId],
                          height: isMobile ? 400 : 500,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Coordinates Info
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
                      padding: EdgeInsets.all(isMobile ? 16 : 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Coordinates',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Info Footer
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Location updates every 10 seconds automatically',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
