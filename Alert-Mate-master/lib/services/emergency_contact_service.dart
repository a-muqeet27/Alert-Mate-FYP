import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/emergency_contact.dart';

class EmergencyContactService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Add a new emergency contact
  Future<String> addEmergencyContact({
    required String userId,
    required String userRole,
    required Map<String, dynamic> contactData,
  }) async {
    try {
      print('📞 Adding emergency contact for user: $userId');
      
      DocumentReference contactRef = await _firestore.collection('emergencyContacts').add({
        'userId': userId,
        'userRole': userRole,
        'name': contactData['name'],
        'relationship': contactData['relationship'],
        'phone': contactData['phone'],
        'email': contactData['email'] ?? '',
        'priority': contactData['priority'] ?? 'secondary',
        'methods': contactData['methods'] ?? ['call'],
        'enabled': contactData['enabled'] ?? true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Emergency contact added: ${contactRef.id}');
      return contactRef.id;
    } catch (e) {
      print('❌ Error adding emergency contact: $e');
      rethrow;
    }
  }

  /// Update an existing emergency contact
  Future<void> updateEmergencyContact({
    required String contactId,
    required Map<String, dynamic> contactData,
  }) async {
    try {
      print('🔄 Updating emergency contact: $contactId');
      
      await _firestore.collection('emergencyContacts').doc(contactId).update({
        'name': contactData['name'],
        'relationship': contactData['relationship'],
        'phone': contactData['phone'],
        'email': contactData['email'] ?? '',
        'priority': contactData['priority'] ?? 'secondary',
        'methods': contactData['methods'] ?? ['call'],
        'enabled': contactData['enabled'] ?? true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Emergency contact updated');
    } catch (e) {
      print('❌ Error updating emergency contact: $e');
      rethrow;
    }
  }

  /// Delete an emergency contact
  Future<void> deleteEmergencyContact(String contactId) async {
    try {
      print('🗑️ Deleting emergency contact: $contactId');
      
      await _firestore.collection('emergencyContacts').doc(contactId).delete();

      print('✅ Emergency contact deleted');
    } catch (e) {
      print('❌ Error deleting emergency contact: $e');
      rethrow;
    }
  }

  /// Toggle contact enabled status
  Future<void> toggleContactEnabled(String contactId, bool enabled) async {
    try {
      print('🔄 Toggling contact $contactId enabled: $enabled');
      
      await _firestore.collection('emergencyContacts').doc(contactId).update({
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Contact enabled status updated');
    } catch (e) {
      print('❌ Error toggling contact enabled: $e');
      rethrow;
    }
  }

  /// Get emergency contacts stream for a user (real-time updates)
  Stream<List<EmergencyContact>> getEmergencyContactsStream(String userId) {
    try {
      print('📡 Streaming emergency contacts for user: $userId');
      
      return _firestore
          .collection('emergencyContacts')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map((snapshot) {
        List<EmergencyContact> contacts = snapshot.docs
            .map((doc) => EmergencyContact.fromMap({
                  'id': doc.id,
                  ...doc.data(),
                }))
            .toList();
        
        print('✅ Emergency contacts stream: ${contacts.length} contacts');
        return contacts;
      });
    } catch (e) {
      print('❌ Error getting emergency contacts stream: $e');
      return Stream.value([]);
    }
  }

  /// Get emergency contacts for a user (one-time fetch)
  Future<List<EmergencyContact>> getEmergencyContacts(String userId) async {
    try {
      print('📞 Fetching emergency contacts for user: $userId');
      
      QuerySnapshot snapshot = await _firestore
          .collection('emergencyContacts')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: false)
          .get();

      List<EmergencyContact> contacts = snapshot.docs
          .map((doc) => EmergencyContact.fromMap({
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              }))
          .toList();

      print('✅ Found ${contacts.length} emergency contacts');
      return contacts;
    } catch (e) {
      print('❌ Error fetching emergency contacts: $e');
      return [];
    }
  }

  /// Get enabled emergency contacts for a user (for notifications)
  Future<List<EmergencyContact>> getEnabledContacts(String userId) async {
    try {
      print('📞 Fetching enabled emergency contacts for user: $userId');
      
      QuerySnapshot snapshot = await _firestore
          .collection('emergencyContacts')
          .where('userId', isEqualTo: userId)
          .where('enabled', isEqualTo: true)
          .orderBy('priority', descending: true)
          .get();

      List<EmergencyContact> contacts = snapshot.docs
          .map((doc) => EmergencyContact.fromMap({
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              }))
          .toList();

      print('✅ Found ${contacts.length} enabled emergency contacts');
      return contacts;
    } catch (e) {
      print('❌ Error fetching enabled emergency contacts: $e');
      return [];
    }
  }
}
