import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tracking_token.dart';

class TrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Generate a unique tracking token (8 characters, URL-safe)
  String _generateToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();
  }

  /// Create a new tracking token for live location sharing
  /// Returns the token ID that can be used in the tracking URL
  Future<String> createTrackingToken({
    required String driverId,
    required String vehiclePlate,
    required String vehicleMake,
    required String vehicleModel,
    Duration duration = const Duration(hours: 6), // Default 6 hours
  }) async {
    try {
      final token = _generateToken();
      final now = DateTime.now().millisecondsSinceEpoch;
      final expiresAt = now + duration.inMilliseconds;

      final trackingToken = TrackingToken(
        id: token,
        driverId: driverId,
        vehiclePlate: vehiclePlate,
        vehicleMake: vehicleMake,
        vehicleModel: vehicleModel,
        createdAt: now,
        expiresAt: expiresAt,
        isActive: true,
      );

      await _firestore
          .collection('tracking_tokens')
          .doc(token)
          .set(trackingToken.toMap());

      print('✅ TrackingService: Created token $token for driver $driverId (expires in ${duration.inHours}h)');
      return token;
    } catch (e) {
      print('❌ TrackingService.createTrackingToken error: $e');
      rethrow;
    }
  }

  /// Get tracking token details
  Future<TrackingToken?> getTrackingToken(String tokenId) async {
    try {
      final doc = await _firestore.collection('tracking_tokens').doc(tokenId).get();
      
      if (!doc.exists) {
        print('⚠️ TrackingService: Token $tokenId not found');
        return null;
      }

      final token = TrackingToken.fromMap(doc.data()!, doc.id);

      // Check if expired
      if (token.isExpired) {
        print('⚠️ TrackingService: Token $tokenId has expired');
        // Deactivate expired token
        await deactivateToken(tokenId);
        return null;
      }

      return token;
    } catch (e) {
      print('❌ TrackingService.getTrackingToken error: $e');
      return null;
    }
  }

  /// Stream tracking token (for real-time updates)
  Stream<TrackingToken?> streamTrackingToken(String tokenId) {
    return _firestore
        .collection('tracking_tokens')
        .doc(tokenId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      
      final token = TrackingToken.fromMap(doc.data()!, doc.id);
      
      // Check if expired
      if (token.isExpired || !token.isActive) {
        return null;
      }
      
      return token;
    });
  }

  /// Get driver's live location
  Stream<Map<String, dynamic>?> streamDriverLocation(String driverId) {
    return _firestore
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      
      final data = doc.data()!;
      final lat = data['lat'] as double? ?? 0.0;
      final lng = data['lng'] as double? ?? 0.0;
      
      // Return null if no valid location
      if (lat == 0.0 && lng == 0.0) return null;
      
      return {
        'lat': lat,
        'lng': lng,
        'status': data['status'] ?? 'offline',
        'drowsinessAlert': data['drowsinessAlert'] ?? false,
        'updatedAt': data['updatedAt'],
      };
    });
  }

  /// Deactivate a tracking token
  Future<void> deactivateToken(String tokenId) async {
    try {
      await _firestore.collection('tracking_tokens').doc(tokenId).update({
        'isActive': false,
      });
      print('✅ TrackingService: Deactivated token $tokenId');
    } catch (e) {
      print('❌ TrackingService.deactivateToken error: $e');
    }
  }

  /// Clean up expired tokens (call this periodically)
  Future<void> cleanupExpiredTokens() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final expiredTokens = await _firestore
          .collection('tracking_tokens')
          .where('expiresAt', isLessThan: now)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in expiredTokens.docs) {
        await doc.reference.update({'isActive': false});
      }

      print('✅ TrackingService: Cleaned up ${expiredTokens.docs.length} expired tokens');
    } catch (e) {
      print('❌ TrackingService.cleanupExpiredTokens error: $e');
    }
  }

  /// Get all active tokens for a driver (for management)
  Future<List<TrackingToken>> getActiveTokensForDriver(String driverId) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final snapshot = await _firestore
          .collection('tracking_tokens')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .where('expiresAt', isGreaterThan: now)
          .get();

      return snapshot.docs
          .map((doc) => TrackingToken.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ TrackingService.getActiveTokensForDriver error: $e');
      return [];
    }
  }
}
