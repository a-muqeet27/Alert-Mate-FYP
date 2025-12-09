import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

class MonitoringService {
  // Use the correct database URL for your region
  final DatabaseReference _database = FirebaseDatabase.instanceFor(
    app: FirebaseDatabase.instance.app,
    databaseURL: 'https://alertmate-26d10-default-rtdb.asia-southeast1.firebasedatabase.app',
  ).ref();
  String? _currentSessionId;

  // Start a new monitoring session
  Future<String> startMonitoringSession(String driverId) async {
    final sessionRef = _database
        .child('drivers')
        .child(driverId)
        .child('monitoring_sessions')
        .push();
    
    _currentSessionId = sessionRef.key;
    
    await sessionRef.set({
      'startTime': ServerValue.timestamp,
      'status': 'active',
    });
    
    return _currentSessionId!;
  }

  // Update real-time stats (called every second)
  Future<void> updateRealtimeStats({
    required String driverId,
    required double alertness,
    required double ear,
    required double mar,
    required double eyeClosure,
    bool drowsinessDetected = false,
  }) async {
    if (_currentSessionId == null) return;

    final statsRef = _database
        .child('drivers')
        .child(driverId)
        .child('monitoring_sessions')
        .child(_currentSessionId!)
        .child('stats')
        .push();

    await statsRef.set({
      'timestamp': ServerValue.timestamp,
      'alertness': alertness,
      'ear': ear,
      'mar': mar,
      'eyeClosure': eyeClosure,
      'drowsinessDetected': drowsinessDetected,
    });

    // Update current stats (for real-time display)
    await _database
        .child('drivers')
        .child(driverId)
        .child('current_stats')
        .set({
      'alertness': alertness,
      'ear': ear,
      'mar': mar,
      'eyeClosure': eyeClosure,
      'drowsinessDetected': drowsinessDetected,
      'lastUpdate': ServerValue.timestamp,
    });
  }

  // End monitoring session and calculate history
  Future<void> endMonitoringSession(String driverId) async {
    if (_currentSessionId == null) return;

    // Get session data
    final sessionRef = _database
        .child('drivers')
        .child(driverId)
        .child('monitoring_sessions')
        .child(_currentSessionId!);

    final snapshot = await sessionRef.get();
    if (!snapshot.exists) return;

    final sessionData = snapshot.value as Map<dynamic, dynamic>;
    final startTime = sessionData['startTime'] as int;
    final stats = sessionData['stats'] as Map<dynamic, dynamic>?;

    // Calculate session statistics
    double totalAlertness = 0;
    int drowsinessEvents = 0;
    int dataPoints = 0;

    if (stats != null) {
      stats.forEach((key, value) {
        final statData = value as Map<dynamic, dynamic>;
        totalAlertness += (statData['alertness'] as num).toDouble();
        if (statData['drowsinessDetected'] == true) {
          drowsinessEvents++;
        }
        dataPoints++;
      });
    }

    final avgAlertness = dataPoints > 0 ? totalAlertness / dataPoints : 0.0;
    final endTime = DateTime.now().millisecondsSinceEpoch;
    final durationMinutes = ((endTime - startTime) / 60000).round();

    // Update session with end data
    await sessionRef.update({
      'endTime': ServerValue.timestamp,
      'status': 'completed',
      'duration_minutes': durationMinutes,
      'average_alertness': avgAlertness,
      'drowsiness_events': drowsinessEvents,
      'data_points': dataPoints,
    });

    // Update driver history
    await _updateDriverHistory(
      driverId,
      durationMinutes,
      avgAlertness,
      drowsinessEvents,
    );

    _currentSessionId = null;
  }

  // Update driver's overall history
  Future<void> _updateDriverHistory(
    String driverId,
    int sessionDuration,
    double sessionAvgAlertness,
    int sessionDrowsinessEvents,
  ) async {
    final historyRef = _database.child('drivers').child(driverId).child('history');
    
    final snapshot = await historyRef.get();
    
    if (snapshot.exists) {
      final history = snapshot.value as Map<dynamic, dynamic>;
      
      final totalSessions = (history['totalSessions'] as int? ?? 0) + 1;
      final totalDrivingMinutes = (history['totalDrivingMinutes'] as int? ?? 0) + sessionDuration;
      final totalDrowsinessEvents = (history['totalDrowsinessEvents'] as int? ?? 0) + sessionDrowsinessEvents;
      
      // Calculate new average alertness
      final prevAvgAlertness = (history['averageAlertness'] as num?)?.toDouble() ?? 0.0;
      final prevSessions = (history['totalSessions'] as int? ?? 0);
      final newAvgAlertness = prevSessions > 0
          ? ((prevAvgAlertness * prevSessions) + sessionAvgAlertness) / totalSessions
          : sessionAvgAlertness;

      await historyRef.update({
        'totalSessions': totalSessions,
        'totalDrivingMinutes': totalDrivingMinutes,
        'totalDrowsinessEvents': totalDrowsinessEvents,
        'averageAlertness': newAvgAlertness,
        'lastSession': ServerValue.timestamp,
      });
    } else {
      // First session
      await historyRef.set({
        'totalSessions': 1,
        'totalDrivingMinutes': sessionDuration,
        'totalDrowsinessEvents': sessionDrowsinessEvents,
        'averageAlertness': sessionAvgAlertness,
        'lastSession': ServerValue.timestamp,
      });
    }
  }

  // Get driver history
  Stream<Map<String, dynamic>> getDriverHistory(String driverId) {
    return _database
        .child('drivers')
        .child(driverId)
        .child('history')
        .onValue
        .map((event) {
      if (event.snapshot.value == null) {
        return <String, dynamic>{};
      }
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }

  // Get current session stats stream
  Stream<Map<String, dynamic>> getCurrentStats(String driverId) {
    return _database
        .child('drivers')
        .child(driverId)
        .child('current_stats')
        .onValue
        .map((event) {
      if (event.snapshot.value == null) {
        return <String, dynamic>{};
      }
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }

  // Get all sessions for a driver
  Future<List<Map<String, dynamic>>> getDriverSessions(String driverId) async {
    try {
      final snapshot = await _database
          .child('drivers')
          .child(driverId)
          .child('monitoring_sessions')
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Failed to load sessions: Request timed out');
            },
          );

      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final sessions = <Map<String, dynamic>>[];
      final data = snapshot.value;

      // Handle different data structures
      if (data is Map) {
        data.forEach((key, value) {
          try {
            if (value is Map) {
              final session = Map<String, dynamic>.from(value as Map);
              session['id'] = key.toString();
              sessions.add(session);
            }
          } catch (e) {
            print('Error parsing session $key: $e');
          }
        });
      }

      // Sort by start time (newest first)
      sessions.sort((a, b) {
        final aTime = a['startTime'] as int? ?? 0;
        final bTime = b['startTime'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });

      return sessions;
    } catch (e) {
      print('Error getting driver sessions: $e');
      rethrow;
    }
  }

  // Check if a driver has an active monitoring session (one-time read)
  Future<bool> hasActiveSession(String driverId) async {
    try {
      final snapshot = await _database
          .child('drivers')
          .child(driverId)
          .child('current_stats')
          .get()
          .timeout(const Duration(seconds: 5));

      if (!snapshot.exists || snapshot.value == null) {
        return false;
      }

      final stats = snapshot.value as Map<dynamic, dynamic>?;
      // If current_stats exists and has data, there's an active session
      return stats != null && stats.isNotEmpty;
    } catch (e) {
      print('Error checking active session for driver $driverId: $e');
      return false;
    }
  }
}