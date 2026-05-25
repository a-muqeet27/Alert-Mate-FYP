import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/emergency_contact.dart';

class EmergencyContactService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<EmergencyContact> _sortContacts(List<EmergencyContact> contacts) {
    contacts.sort((a, b) {
      final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
      if (aTime != bTime) return aTime.compareTo(bTime);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return contacts;
  }

  List<EmergencyContact> _docsToContacts(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final contacts = docs
        .map(
          (doc) => EmergencyContact.fromMap({
            'id': doc.id,
            ...doc.data(),
          }),
        )
        .toList();
    return _sortContacts(contacts);
  }

  /// Add a new emergency contact
  Future<String> addEmergencyContact({
    required String userId,
    required String userRole,
    required Map<String, dynamic> contactData,
  }) async {
    if (userId.trim().isEmpty) {
      throw Exception('Missing user account. Please sign in again.');
    }

    try {
      final priority =
          (contactData['priority'] as String? ?? contactData['contactType'] as String? ?? 'secondary')
              .toLowerCase()
              .trim();

      final DocumentReference<Map<String, dynamic>> contactRef =
          await _firestore.collection('emergencyContacts').add({
        'userId': userId,
        'userRole': userRole,
        'name': (contactData['name'] as String? ?? '').trim(),
        'relationship': (contactData['relationship'] as String? ?? '').trim(),
        'phone': (contactData['phone'] as String? ?? '').trim(),
        'email': (contactData['email'] as String? ?? '').trim(),
        'priority': priority,
        'methods': contactData['methods'] ?? ['call'],
        'contactType': priority,
        'enabled': contactData['enabled'] ?? true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return contactRef.id;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateEmergencyContact({
    required String contactId,
    required Map<String, dynamic> contactData,
  }) async {
    if (contactId.trim().isEmpty) {
      throw Exception('Invalid contact. Please refresh and try again.');
    }

    final priority =
        (contactData['priority'] as String? ?? contactData['contactType'] as String? ?? 'secondary')
            .toLowerCase()
            .trim();

    await _firestore.collection('emergencyContacts').doc(contactId).update({
      'name': (contactData['name'] as String? ?? '').trim(),
      'relationship': (contactData['relationship'] as String? ?? '').trim(),
      'phone': (contactData['phone'] as String? ?? '').trim(),
      'email': (contactData['email'] as String? ?? '').trim(),
      'priority': priority,
      'methods': contactData['methods'] ?? ['call'],
      'contactType': priority,
      'enabled': contactData['enabled'] ?? true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteEmergencyContact(String contactId) async {
    await _firestore.collection('emergencyContacts').doc(contactId).delete();
  }

  Stream<bool> watchEmergencyCallsEnabled(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map(
          (doc) => (doc.data()?['emergencyCallsEnabled'] as bool?) ?? true,
        );
  }

  Future<void> setEmergencyCallsEnabled(String userId, bool enabled) async {
    await _firestore.collection('users').doc(userId).set(
      {'emergencyCallsEnabled': enabled},
      SetOptions(merge: true),
    );
  }

  Future<bool> getEmergencyCallsEnabled(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return (doc.data()?['emergencyCallsEnabled'] as bool?) ?? true;
  }

  Future<void> toggleContactEnabled(String contactId, bool enabled) async {
    await _firestore.collection('emergencyContacts').doc(contactId).update({
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<EmergencyContact>> getEmergencyContactsStream(String userId) {
    if (userId.trim().isEmpty) {
      return Stream.value([]);
    }

    return _firestore
        .collection('emergencyContacts')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => _docsToContacts(snapshot.docs));
  }

  Future<List<EmergencyContact>> getEmergencyContacts(String userId) async {
    if (userId.trim().isEmpty) return [];

    final snapshot = await _firestore
        .collection('emergencyContacts')
        .where('userId', isEqualTo: userId)
        .get();

    return _docsToContacts(snapshot.docs);
  }

  Future<List<EmergencyContact>> getEnabledContacts(String userId) async {
    if (userId.trim().isEmpty) return [];

    final snapshot = await _firestore
        .collection('emergencyContacts')
        .where('userId', isEqualTo: userId)
        .where('enabled', isEqualTo: true)
        .get();

    return _docsToContacts(snapshot.docs);
  }
}
