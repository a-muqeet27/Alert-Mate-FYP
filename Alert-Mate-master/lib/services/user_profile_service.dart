import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart' as app_models;

class UserProfileService {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<app_models.User> updateProfile({
    required String userId,
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final trimmedFirst = firstName.trim();
    final trimmedLast = lastName.trim();
    final trimmedPhone = phone.trim();

    if (trimmedFirst.isEmpty || trimmedLast.isEmpty) {
      throw Exception('First and last name are required.');
    }
    if (trimmedPhone.isEmpty) {
      throw Exception('Phone number is required.');
    }

    await _firestore.collection('users').doc(userId).update({
      'firstName': trimmedFirst,
      'lastName': trimmedLast,
      'name': '$trimmedFirst $trimmedLast',
      'phone': trimmedPhone,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data();
    if (data == null) {
      throw Exception('User profile not found.');
    }

    return app_models.User.fromMap({...data, 'id': userId});
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('You must be signed in to change your password.');
    }

    if (newPassword.length < 8) {
      throw Exception('New password must be at least 8 characters.');
    }

    try {
      final credential = firebase_auth.EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e.code));
    }
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Current password is incorrect.';
      case 'requires-recent-login':
        return 'Please sign out and sign in again, then retry changing your password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Could not update password. Please try again.';
    }
  }
}