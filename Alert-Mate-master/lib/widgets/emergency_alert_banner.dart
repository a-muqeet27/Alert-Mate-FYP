import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/emergency_alert_service.dart';

/// Reusable emergency alert banner widget
/// Shows active emergency alerts at the top of dashboards
class EmergencyAlertBanner extends StatelessWidget {
  final String userId;
  final String userRole; // 'driver', 'owner', or 'admin'
  final EmergencyAlertService _alertService = EmergencyAlertService();

  EmergencyAlertBanner({
    Key? key,
    required this.userId,
    required this.userRole,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Stream<List<Map<String, dynamic>>> alertStream;

    if (userRole == 'driver') {
      alertStream = _alertService.streamDriverAlerts(userId);
    } else if (userRole == 'owner') {
      alertStream = _alertService.streamOwnerAlerts(userId);
    } else {
      alertStream = _alertService.streamAllActiveAlerts();
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: alertStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final alerts = snapshot.data!;
        final isMobile = MediaQuery.of(context).size.width < 768;

        return Column(
          children: alerts.map((alert) => _buildAlertCard(context, alert, isMobile)).toList(),
        );
      },
    );
  }

  Widget _buildAlertCard(BuildContext context, Map<String, dynamic> alert, bool isMobile) {
    final passengerName = alert['passengerName'] as String? ?? 'Unknown Passenger';
    final vehiclePlate = alert['vehiclePlate'] as String? ?? 'Unknown';
    final vehicleMake = alert['vehicleMake'] as String? ?? '';
    final vehicleModel = alert['vehicleModel'] as String? ?? '';
    final alertId = alert['id'] as String;

    return Container(
      margin: EdgeInsets.only(
        left: isMobile ? 16 : 24,
        right: isMobile ? 16 : 24,
        bottom: 16,
      ),
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🚨 EMERGENCY ALERT',
                      style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'From: $passengerName',
                      style: TextStyle(
                        fontSize: isMobile ? 13 : 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _acknowledgeAlert(context, alertId),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Acknowledge',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_car, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Vehicle: $vehicleMake $vehicleModel ($vehiclePlate)',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A passenger has sent an emergency alert. Please respond immediately.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _acknowledgeAlert(context, alertId),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Acknowledge'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _resolveAlert(context, alertId),
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Resolve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _acknowledgeAlert(BuildContext context, String alertId) async {
    try {
      await _alertService.acknowledgeAlert(alertId, userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert acknowledged'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resolveAlert(BuildContext context, String alertId) async {
    try {
      await _alertService.resolveAlert(alertId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert resolved'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
