import 'package:flutter/material.dart';
import '../services/monitoring_service.dart';
import '../constants/app_colors.dart';

class DriverHistoryScreen extends StatefulWidget {
  final String driverId;

  const DriverHistoryScreen({Key? key, required this.driverId}) : super(key: key);

  @override
  State<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends State<DriverHistoryScreen> {
  final MonitoringService _monitoringService = MonitoringService();
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final sessions = await _monitoringService.getDriverSessions(widget.driverId);
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading history: $e';
        _isLoading = false;
      });
    }
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) return 'N/A';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[date.month - 1];
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $year • $hour:$minute $period';
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) return 'N/A';
    if (minutes < 60) {
      return '${minutes}m';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  Color _getAlertnessColor(double alertness) {
    if (alertness >= 80) return AppColors.success;
    if (alertness >= 70) return AppColors.warning;
    return AppColors.danger;
  }

  String _getStatusBadge(String? status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'active':
        return 'Active';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'active':
        return AppColors.primary;
      default:
        return Colors.grey;
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Driving History',
          style: TextStyle(
            color: Colors.black87,
            fontSize: isMobile ? 20 : 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: _loadSessions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        _error,
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadSessions,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.driverPrimary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : _sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 80, color: Colors.grey[300]),
                          const SizedBox(height: 24),
                          Text(
                            'No Driving History',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your monitoring sessions will appear here',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadSessions,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Summary Card
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(isMobile ? 20 : 24),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.driverPrimary,
                                      AppColors.driverPrimary.withOpacity(0.8),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.driverPrimary.withOpacity(0.3),
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
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.analytics_outlined,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Total Sessions',
                                                style: TextStyle(
                                                  fontSize: isMobile ? 14 : 16,
                                                  color: Colors.white.withOpacity(0.9),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${_sessions.length}',
                                                style: TextStyle(
                                                  fontSize: isMobile ? 32 : 40,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              
                              // Analytics Graph
                              if (_sessions.isNotEmpty) ...[
                                _buildAnalyticsGraph(isMobile),
                                const SizedBox(height: 24),
                              ],
                              
                              // Sessions List
                              Text(
                                'Session History',
                                style: TextStyle(
                                  fontSize: isMobile ? 20 : 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              isMobile
                                  ? Column(
                                      children: _sessions.map((session) =>
                                          _buildMobileSessionCard(session, isMobile)).toList(),
                                    )
                                  : _buildDesktopTable(isMobile),
                            ],
                          ),
                        ),
                      ),
                    ),
    );
  }

  Widget _buildMobileSessionCard(Map<String, dynamic> session, bool isMobile) {
    final startTime = session['startTime'] as int?;
    final endTime = session['endTime'] as int?;
    final duration = session['duration_minutes'] as int?;
    final avgAlertness = (session['average_alertness'] as num?)?.toDouble() ?? 0.0;
    final drowsinessEvents = session['drowsiness_events'] as int? ?? 0;
    final status = session['status'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatTimestamp(startTime),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      if (endTime != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Ended: ${_formatTimestamp(endTime)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getStatusBadge(status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(status),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        Icons.timer_outlined,
                        'Duration',
                        _formatDuration(duration),
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatItem(
                        Icons.visibility_outlined,
                        'Alertness',
                        '${avgAlertness.toStringAsFixed(1)}%',
                        _getAlertnessColor(avgAlertness),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        Icons.warning_amber_rounded,
                        'Drowsiness Events',
                        '$drowsinessEvents',
                        drowsinessEvents > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatItem(
                        Icons.assessment_outlined,
                        'Data Points',
                        '${session['data_points'] ?? 0}',
                        Colors.grey[700]!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsGraph(bool isMobile) {
    // Get last 10 sessions for the graph (or all if less than 10)
    final graphSessions = _sessions.take(10).toList();
    if (graphSessions.isEmpty) return const SizedBox.shrink();

    // Calculate statistics
    final completedSessions = graphSessions.where((s) => s['status'] == 'completed').toList();
    if (completedSessions.isEmpty) return const SizedBox.shrink();

    final avgAlertnessValues = completedSessions
        .map((s) => (s['average_alertness'] as num?)?.toDouble() ?? 0.0)
        .toList();
    
    final totalDrowsinessEvents = completedSessions
        .fold<int>(0, (sum, s) => sum + ((s['drowsiness_events'] as int?) ?? 0));
    
    final avgAlertness = avgAlertnessValues.isEmpty
        ? 0.0
        : avgAlertnessValues.reduce((a, b) => a + b) / avgAlertnessValues.length;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Analytics Overview',
                style: TextStyle(
                  fontSize: isMobile ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Icon(Icons.analytics, color: AppColors.driverPrimary, size: isMobile ? 20 : 24),
            ],
          ),
          const SizedBox(height: 24),
          
          // Key Metrics Row
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetricCard(
                'Avg Alertness',
                '${avgAlertness.toStringAsFixed(1)}%',
                _getAlertnessColor(avgAlertness),
                Icons.visibility,
                isMobile,
              ),
              _buildMetricCard(
                'Total Events',
                '$totalDrowsinessEvents',
                totalDrowsinessEvents > 0 ? Colors.orange : Colors.green,
                Icons.warning,
                isMobile,
              ),
              _buildMetricCard(
                'Sessions',
                '${completedSessions.length}',
                AppColors.driverPrimary,
                Icons.directions_car,
                isMobile,
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Alertness Trend Graph
          Text(
            'Alertness Trend (Last ${completedSessions.length} Sessions)',
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: isMobile ? 200 : 250,
            child: CustomPaint(
              painter: _AlertnessChartPainter(
                dataPoints: avgAlertnessValues.reversed.toList(),
                color: AppColors.driverPrimary,
              ),
              child: Container(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color, IconData icon, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: isMobile ? 20 : 24),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isMobile ? 11 : 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: isMobile ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(bool isMobile) {
    return Container(
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - (isMobile ? 32 : 48),
          ),
          child: Table(
            columnWidths: const {
              0: FixedColumnWidth(200),
              1: FixedColumnWidth(200),
              2: FixedColumnWidth(120),
              3: FixedColumnWidth(120),
              4: FixedColumnWidth(150),
              5: FixedColumnWidth(120),
              6: FixedColumnWidth(100),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                children: [
                  _buildTableHeader('Start Time'),
                  _buildTableHeader('End Time'),
                  _buildTableHeader('Duration'),
                  _buildTableHeader('Status'),
                  _buildTableHeader('Avg Alertness'),
                  _buildTableHeader('Drowsiness Events'),
                  _buildTableHeader('Data Points'),
                ],
              ),
              ..._sessions.map((session) => _buildTableRow(session)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

  TableRow _buildTableRow(Map<String, dynamic> session) {
    final startTime = session['startTime'] as int?;
    final endTime = session['endTime'] as int?;
    final duration = session['duration_minutes'] as int?;
    final avgAlertness = (session['average_alertness'] as num?)?.toDouble() ?? 0.0;
    final drowsinessEvents = session['drowsiness_events'] as int? ?? 0;
    final status = session['status'] as String?;
    final dataPoints = session['data_points'] as int? ?? 0;

    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
      ),
      children: [
        _buildTableCell(_formatTimestamp(startTime)),
        _buildTableCell(endTime != null ? _formatTimestamp(endTime) : 'In Progress'),
        _buildTableCell(_formatDuration(duration)),
        _buildStatusCell(status),
        _buildAlertnessCell(avgAlertness),
        _buildTableCell('$drowsinessEvents'),
        _buildTableCell('$dataPoints'),
      ],
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

  Widget _buildStatusCell(String? status) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getStatusColor(status).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _getStatusBadge(status),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _getStatusColor(status),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildAlertnessCell(double alertness) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getAlertnessColor(alertness),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${alertness.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _getAlertnessColor(alertness),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for alertness chart
class _AlertnessChartPainter extends CustomPainter {
  final List<double> dataPoints;
  final Color color;

  _AlertnessChartPainter({
    required this.dataPoints,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw grid lines
    final gridLines = 5;
    for (int i = 0; i <= gridLines; i++) {
      final y = size.height * (i / gridLines);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Calculate points
    final minValue = 0.0;
    final maxValue = 100.0;
    final range = maxValue - minValue;

    final pointSpacing = dataPoints.length > 1 ? size.width / (dataPoints.length - 1) : 0.0;
    final points = <Offset>[];

    for (int i = 0; i < dataPoints.length; i++) {
      final value = dataPoints[i].clamp(minValue, maxValue);
      final normalizedValue = (value - minValue) / range;
      final x = dataPoints.length > 1 ? i * pointSpacing : size.width / 2;
      final y = size.height - (normalizedValue * size.height);
      points.add(Offset(x, y));
    }

    // Draw filled area under the line
    if (points.length > 1) {
      final path = Path();
      path.moveTo(points.first.dx, size.height);
      for (var point in points) {
        path.lineTo(point.dx, point.dy);
      }
      path.lineTo(points.last.dx, size.height);
      path.close();
      canvas.drawPath(path, fillPaint);
    }

    // Draw line
    if (points.length > 1) {
      final path = Path();
      path.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    // Draw points
    for (var point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }

    // Draw Y-axis labels
    final textStyle = TextStyle(
      color: Colors.grey[600],
      fontSize: 10,
    );
    for (int i = 0; i <= gridLines; i++) {
      final value = maxValue - (i * range / gridLines);
      final y = size.height * (i / gridLines);
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${value.toInt()}%',
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, y - textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(_AlertnessChartPainter oldDelegate) {
    return oldDelegate.dataPoints != dataPoints || oldDelegate.color != color;
  }
}

