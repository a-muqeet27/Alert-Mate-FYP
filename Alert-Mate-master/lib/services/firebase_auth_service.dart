import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../firebase_options.dart';
import '../models/user.dart' as app_models;

class FirebaseAuthService {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// Continue URL for verification links (must match Firebase Auth authorized domains).
  String get _emailActionContinueUrl {
    final o = DefaultFirebaseOptions.currentPlatform;
    final domain = o.authDomain ?? '${o.projectId}.firebaseapp.com';
    return 'https://$domain/';
  }

  /// Sends verification email with explicit action settings (more reliable across platforms).
  Future<void> _sendVerificationEmail(firebase_auth.User user) async {
    final settings = firebase_auth.ActionCodeSettings(
      url: _emailActionContinueUrl,
      handleCodeInApp: false,
      androidPackageName: 'com.example.alert_mate',
      androidInstallApp: true,
    );
    await user.sendEmailVerification(settings);
  }

  /// [ActionCodeSettings] for email-link messages (used when the address is already verified).
  firebase_auth.ActionCodeSettings get _signInLinkActionCodeSettings {
    return firebase_auth.ActionCodeSettings(
      url: _emailActionContinueUrl,
      handleCodeInApp: true,
      androidPackageName: 'com.example.alert_mate',
      androidInstallApp: true,
      iOSBundleId: 'com.example.alertMate',
    );
  }

  /// Firebase only verifies an email **once** per account; it will not send another
  /// `sendEmailVerification` after the address is verified. For "add another role" flows
  /// we still send **an email with a link** every time by using [sendSignInLinkToEmail]
  /// when the account is already verified (enable "Email link" under Email/Password in Firebase Console).
  Future<void> _sendRoleSignupEmail(String email, firebase_auth.User user) async {
    await user.reload();
    final current = _auth.currentUser;
    if (current == null) return;

    if (!current.emailVerified) {
      await _sendVerificationEmail(current);
      return;
    }

    try {
      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: _signInLinkActionCodeSettings,
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'operation-not-allowed') {
        throw Exception(
          'Email link sign-in is disabled in Firebase. In Firebase Console → Authentication → '
          'Sign-in method → Email/Password → enable "Email link (passwordless sign-in)" so we can send a confirmation link when your email is already verified.',
        );
      }
      rethrow;
    }
  }

  // Check if user exists with given email (checks all roles)
  Future<bool> userExists(String email) async {
    try {
      print('🔍 Checking if user exists: $email');
      
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();
      
      bool exists = querySnapshot.docs.isNotEmpty;
      print(exists ? '✅ User exists!' : '❌ No existing user found');
      return exists;
    } catch (e) {
      print('❌ Error checking user existence: $e');
      return false;
    }
  }

  // Sign up new user with multiple roles.
  // On success: verification email is sent and the session is ended so the user must verify, then sign in.
  Future<void> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required List<String> roles,
  }) async {
    try {
      if (roles.contains('admin')) {
        throw Exception(
          'Admin accounts cannot be registered in the app. Use credentials provided by your organization.',
        );
      }

      print('🚀 Starting sign up process for: $email with roles: $roles');
      
      // Create Firebase Auth user
      print('👤 Creating Firebase Auth user...');
      firebase_auth.UserCredential userCredential = 
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('✅ Firebase Auth user created: ${userCredential.user!.uid}');

      // Send email verification before Firestore so we fail fast if email cannot be sent.
      if (userCredential.user != null && !userCredential.user!.emailVerified) {
        print('📧 Sending verification email...');
        try {
          await _sendVerificationEmail(userCredential.user!);
          print('✅ Verification email sent to $email');
        } catch (e) {
          print('❌ sendEmailVerification failed: $e');
          await _auth.signOut();
          throw Exception(
            'Could not send verification email. Check Firebase Auth email settings and spam folder, then try again.',
          );
        }
      }

      // Set first role as active role
      String activeRole = roles.isNotEmpty ? roles.first : 'passenger';

      // Save user data to Firestore with roles array
      print('💾 Saving user data to Firestore...');
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'firstName': firstName,
        'lastName': lastName,
        'name': '$firstName $lastName', 
        'email': email,
        'phone': phone,
        'roles': roles, 
        'activeRole': activeRole, 
        'emailVerified': false,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ User data saved to Firestore successfully!');
      print('👥 Roles: $roles | Active Role: $activeRole');

      // Verify the data was saved
      var doc = await _firestore.collection('users').doc(userCredential.user!.uid).get();
      if (doc.exists) {
        print('📊 VERIFICATION: Data exists in Firestore!');
        print('📊 User data: ${doc.data()}');
      }

      // End session: user must open the verification link, then sign in (no "logged in" state after signup).
      await _auth.signOut();
      print('👋 Signed out after signup; user must verify email then sign in.');

      // Vehicle assignment is deferred until admin approves driver documents (see DriverVehicleSubmissionService).
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // If the email already exists, treat "signup" as "add this role",
        // but only after verifying the password by signing in.
        // Admin role should not be self-service.
        if (roles.contains('admin')) {
          throw Exception('Admin role cannot be self-registered. Please contact support.');
        }

        print('⚠️ Email already in use. Attempting role add after password verification...');
        try {
          // 1. Verify password by signing in (only this step maps to "wrong password")
          late firebase_auth.UserCredential credential;
          try {
            credential =
                await _auth.signInWithEmailAndPassword(email: email, password: password);
          } on firebase_auth.FirebaseAuthException {
            throw Exception('Account exists. Please enter the correct password to add this role.');
          }

          String uid = credential.user!.uid;
          
          // 2. Get existing roles
          DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
          if (!doc.exists) {
            await _auth.signOut();
            throw Exception('Account exists but profile is missing. Please contact support.');
          }

          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          List<String> existingRoles = List<String>.from(data['roles'] ?? []);

          // 3. Add requested roles (non-admin) if missing
          bool rolesUpdated = false;
          for (final role in roles) {
            if (role == 'admin') continue;
            if (!existingRoles.contains(role)) {
              existingRoles.add(role);
              rolesUpdated = true;
              print('➕ Adding new role: $role');
            }
          }

          final current = _auth.currentUser;
          if (current != null) {
            await current.reload();
          }
          final refreshed = _auth.currentUser;
          if (refreshed == null) {
            await _auth.signOut();
            throw Exception('Session lost. Please try again.');
          }

          // Send an email with a link every time a new role is added, or re-send verification if still pending.
          final shouldSendEmail = rolesUpdated || !refreshed.emailVerified;
          if (shouldSendEmail) {
            print('📧 Sending role / verification email to $email...');
            await _sendRoleSignupEmail(email, refreshed);
            print('✅ Email sent to $email');
          } else {
            print('ℹ️ No new role and email already verified — no email sent.');
          }

          if (rolesUpdated) {
            await _firestore.collection('users').doc(uid).update({
              'roles': existingRoles,
              'activeRole': roles.isNotEmpty ? roles.first : (data['activeRole'] ?? existingRoles.first),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            print('✅ Roles updated successfully: $existingRoles');
          } else {
            print('ℹ️ User already has these roles.');
          }

          await _auth.signOut();
          print('👋 Signed out after role add; user must sign in after verifying if needed.');
          return;
        } catch (signInError) {
          await _auth.signOut();
          rethrow;
        }
      }
      
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      throw Exception(_getAuthErrorMessage(e.code));
    } catch (e) {
      print('❌ Unexpected error during sign up: $e');
      rethrow;
    }
  }

  // Sign in existing user
  Future<app_models.User?> signIn(
    String email,
    String password, {
    bool skipEmailVerification = false,
  }) async {
    try {
      print('🔐 Attempting sign in for: $email');
      
      firebase_auth.UserCredential userCredential = 
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('✅ Sign in successful!');

      // Enforce email verification before allowing dashboard access (Auth is source of truth).
      // Do not sign out here when unverified: the session is needed for "Resend verification email".
      await userCredential.user!.reload();
      await userCredential.user!.getIdToken(true);
      await userCredential.user!.reload();
      final refreshed = _auth.currentUser;
      if (!skipEmailVerification &&
          (refreshed == null || !refreshed.emailVerified)) {
        throw Exception('EMAIL_NOT_VERIFIED');
      }
      
      // Sync email verification status from Firebase Auth to Firestore
      await syncEmailVerificationStatus();

      // Get user data from Firestore
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        
        // Handle both old (single role) and new (multiple roles) format
        List<String> roles;
        String activeRole;
        
        if (data.containsKey('roles')) {
          // New format with roles array
          roles = List<String>.from(data['roles'] ?? ['passenger']);
          activeRole = data['activeRole'] ?? roles.first;
        } else if (data.containsKey('role')) {
          // Old format with single role - migrate automatically
          String oldRole = data['role'] ?? 'passenger';
          roles = [oldRole];
          activeRole = oldRole;
          
          // Update to new format in background
          _migrateUserToNewFormat(userCredential.user!.uid, oldRole);
        } else {
          // Fallback
          roles = ['passenger'];
          activeRole = 'passenger';
        }
        
        print('📊 User roles: $roles | Active role: $activeRole');
        print('📧 Email verified: ${userCredential.user!.emailVerified}');
        
        return app_models.User(
          id: userCredential.user!.uid,
          firstName: data['firstName'],
          lastName: data['lastName'],
          email: data['email'],
          phone: data['phone'],
          role: activeRole,
          roles: roles,
        );
      }

      return null;
    } on firebase_auth.FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      throw Exception(_getAuthErrorMessage(e.code));
    } catch (e) {
      if (e.toString().contains('EMAIL_NOT_VERIFIED')) {
        throw Exception('Please verify your email before signing in.');
      }
      print('❌ Unexpected error during sign in: $e');
      rethrow;
    }
  }

  // Update active role for a user
  Future<void> updateActiveRole(String uid, String newActiveRole) async {
    try {
      print('🔄 Updating active role to: $newActiveRole');
      
      // First verify the user has this role
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        List<String> roles = List<String>.from(data['roles'] ?? []);
        
        if (roles.contains(newActiveRole)) {
          await _firestore.collection('users').doc(uid).update({
            'activeRole': newActiveRole,
          });
          print('✅ Active role updated to: $newActiveRole');
        } else {
          print('❌ User does not have the $newActiveRole role');
          throw Exception('User does not have the $newActiveRole role');
        }
      }
    } catch (e) {
      print('❌ Failed to update active role: $e');
      throw Exception('Failed to update active role: $e');
    }
  }

  // Add a new role to user
  Future<void> addRoleToUser(String uid, String role) async {
    try {
      print('➕ Adding role: $role to user: $uid');
      
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        List<String> roles = List<String>.from(data['roles'] ?? []);
        
        if (!roles.contains(role)) {
          roles.add(role);
          await _firestore.collection('users').doc(uid).update({
            'roles': roles,
          });
          print('✅ Role added successfully: $role');
        } else {
          print('⚠️ User already has this role');
        }
      }
    } catch (e) {
      print('❌ Failed to add role: $e');
      throw Exception('Failed to add role: $e');
    }
  }

  /// Restricted helper for owner -> driver edge case only.
  Future<void> addDriverRoleForOwner(String uid) async {
    DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      throw Exception('User profile not found');
    }

    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    List<String> roles = List<String>.from(data['roles'] ?? []);
    if (!roles.contains('owner')) {
      throw Exception('Only vehicle owners can use this driver access path.');
    }

    if (!roles.contains('driver')) {
      roles.add('driver');
      await _firestore.collection('users').doc(uid).update({
        'roles': roles,
        'activeRole': 'driver',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _firestore.collection('users').doc(uid).update({
        'activeRole': 'driver',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Remove a role from user
  Future<void> removeRoleFromUser(String uid, String role) async {
    try {
      print('➖ Removing role: $role from user: $uid');
      
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        List<String> roles = List<String>.from(data['roles'] ?? []);
        String activeRole = data['activeRole'] ?? '';
        
        if (roles.contains(role)) {
          roles.remove(role);
          
          // If removing the active role, switch to another role
          if (activeRole == role && roles.isNotEmpty) {
            await _firestore.collection('users').doc(uid).update({
              'roles': roles,
              'activeRole': roles.first,
            });
            print('✅ Role removed and switched active role to: ${roles.first}');
          } else if (roles.isEmpty) {
            print('❌ Cannot remove last role');
            throw Exception('Cannot remove last role');
          } else {
            await _firestore.collection('users').doc(uid).update({
              'roles': roles,
            });
            print('✅ Role removed successfully');
          }
        } else {
          print('⚠️ User does not have this role');
        }
      }
    } catch (e) {
      print('❌ Failed to remove role: $e');
      throw Exception('Failed to remove role: $e');
    }
  }

  // Get user's roles
  Future<List<String>> getUserRoles(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return List<String>.from(data['roles'] ?? ['passenger']);
      }
      
      return ['passenger'];
    } catch (e) {
      print('❌ Error getting user roles: $e');
      return ['passenger'];
    }
  }

  // Get user's active role
  Future<String> getUserActiveRole(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return data['activeRole'] ?? 'passenger';
      }
      
      return 'passenger';
    } catch (e) {
      print('❌ Error getting active role: $e');
      return 'passenger';
    }
  }

  // Migrate a single user from old format to new format
  Future<void> _migrateUserToNewFormat(String uid, String oldRole) async {
    try {
      print('🔄 Migrating user $uid to new format...');
      await _firestore.collection('users').doc(uid).update({
        'roles': [oldRole],
        'activeRole': oldRole,
        'role': FieldValue.delete(), // Remove old field
      });
      print('✅ User migrated successfully');
    } catch (e) {
      print('⚠️ Migration failed (non-critical): $e');
    }
  }

  // Migrate all existing users (run once)
  Future<void> migrateAllExistingUsers() async {
    try {
      print('🚀 Starting migration of all existing users...');
      
      QuerySnapshot users = await _firestore.collection('users').get();
      int migratedCount = 0;
      int skippedCount = 0;

      for (var doc in users.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        
        // Check if user has old 'role' field (string)
        if (data.containsKey('role') && data['role'] is String && !data.containsKey('roles')) {
          String oldRole = data['role'];
          
          // Update to new structure
          await _firestore.collection('users').doc(doc.id).update({
            'roles': [oldRole], // Convert to array
            'activeRole': oldRole,
            'role': FieldValue.delete(), // Delete old field
          });
          
          migratedCount++;
          print('✅ Migrated user: ${doc.id} with role: $oldRole');
        } else {
          skippedCount++;
          print('⏭️ Skipped user: ${doc.id} (already migrated or no role field)');
        }
      }
      
      print('🎉 Migration complete!');
      print('📊 Total users: ${users.docs.length}');
      print('✅ Migrated: $migratedCount');
      print('⏭️ Skipped: $skippedCount');
    } catch (e) {
      print('❌ Migration failed: $e');
      rethrow;
    }
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      print('✅ Password reset email sent to $email');
    } on firebase_auth.FirebaseAuthException catch (e) {
      print('❌ Password reset error: ${e.code}');
      throw Exception(_getAuthErrorMessage(e.code));
    }
  }

  // Google Sign-In
  Future<app_models.User?> signInWithGoogle({required List<String> roles}) async {
    try {
      print('🔐 Starting Google Sign-In...');
      
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        print('❌ Google Sign-In cancelled by user');
        return null;
      }

      print('✅ Google user selected: ${googleUser.email}');

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      firebase_auth.UserCredential userCredential = 
          await _auth.signInWithCredential(credential);

      print('✅ Firebase sign-in successful!');

      String uid = userCredential.user!.uid;
      String email = userCredential.user!.email!;
      
      // Check if user exists in Firestore
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) {
        // New user - create profile
        print('📝 Creating new user profile...');
        
        // Split display name into first and last name
        String displayName = userCredential.user!.displayName ?? email.split('@')[0];
        List<String> nameParts = displayName.split(' ');
        String firstName = nameParts.isNotEmpty ? nameParts[0] : displayName;
        String lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

        String activeRole = roles.isNotEmpty ? roles.first : 'passenger';

        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'firstName': firstName,
          'lastName': lastName,
          'name': displayName,
          'email': email,
          'phone': userCredential.user!.phoneNumber ?? '',
          'roles': roles,
          'activeRole': activeRole,
          'emailVerified': true, // Google accounts are pre-verified
          'isActive': true,
          'authProvider': 'google',
          'photoURL': userCredential.user!.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
        });

        print('✅ New user profile created with roles: $roles');

        return app_models.User(
          id: uid,
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: userCredential.user!.phoneNumber ?? '',
          role: activeRole,
          roles: roles,
        );
      } else {
        // Existing user - check if we need to add roles
        print('👤 Existing user found');
        
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        List<String> existingRoles = List<String>.from(data['roles'] ?? []);
        String activeRole = data['activeRole'] ?? existingRoles.first;

        // Add new roles if they don't exist
        bool rolesUpdated = false;
        for (final role in roles) {
          if (!existingRoles.contains(role)) {
            existingRoles.add(role);
            rolesUpdated = true;
            print('➕ Adding new role: $role');
          }
        }

        if (rolesUpdated) {
          await _firestore.collection('users').doc(uid).update({
            'roles': existingRoles,
            'activeRole': roles.first, // Set to the newly requested role
            'lastLogin': FieldValue.serverTimestamp(),
          });
          print('✅ Roles updated: $existingRoles');
          activeRole = roles.first;
        } else {
          // Just update last login
          await _firestore.collection('users').doc(uid).update({
            'lastLogin': FieldValue.serverTimestamp(),
          });
        }

        return app_models.User(
          id: uid,
          firstName: data['firstName'],
          lastName: data['lastName'],
          email: data['email'],
          phone: data['phone'] ?? '',
          role: activeRole,
          roles: existingRoles,
        );
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      throw Exception(_getAuthErrorMessage(e.code));
    } catch (e) {
      print('❌ Google Sign-In error: $e');
      throw Exception('Google Sign-In failed: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    print('👋 User signed out');
  }

  // Get current user
  firebase_auth.User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Resend verification email
  Future<void> resendVerificationEmail() async {
    try {
      firebase_auth.User? user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        print('📧 Resending verification email to ${user.email}...');
        await _sendVerificationEmail(user);
        print('✅ Verification email resent!');
      } else if (user?.emailVerified == true) {
        print('⚠️ Email already verified!');
        throw Exception('Email is already verified');
      } else {
        print('❌ No user logged in');
        throw Exception('No user logged in');
      }
    } catch (e) {
      print('❌ Error resending verification email: $e');
      rethrow;
    }
  }

  // Check if email is verified (refresh the user first)
  Future<bool> isEmailVerified() async {
    try {
      firebase_auth.User? user = _auth.currentUser;
      if (user != null) {
        await user.reload(); // Refresh user data
        user = _auth.currentUser; // Get updated user
        
        // If verified in Firebase Auth, update Firestore too
        if (user?.emailVerified == true) {
          await _firestore.collection('users').doc(user!.uid).update({
            'emailVerified': true,
          });
          print('✅ Firestore updated with email verification status');
        }
        
        return user?.emailVerified ?? false;
      }
      return false;
    } catch (e) {
      print('❌ Error checking email verification: $e');
      return false;
    }
  }
  
  // Sync email verification status from Firebase Auth to Firestore
  Future<void> syncEmailVerificationStatus() async {
    try {
      firebase_auth.User? user = _auth.currentUser;
      if (user != null) {
        await user.reload(); // Refresh user data
        user = _auth.currentUser; // Get updated user
        
        if (user != null) {
          await _firestore.collection('users').doc(user.uid).update({
            'emailVerified': user.emailVerified,
            'lastLogin': FieldValue.serverTimestamp(),
          });
          print('✅ Email verification status synced: ${user.emailVerified}');
        }
      }
    } catch (e) {
      print('❌ Error syncing verification status: $e');
    }
  }

  // Helper method for user-friendly error messages
  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled.';
      default:
        return 'Authentication error: $code';
    }
  }
}