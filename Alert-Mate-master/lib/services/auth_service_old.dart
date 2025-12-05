// Legacy in-memory auth service kept for reference only.
// Not used in the current Flutter + Firebase implementation.
// (Implementation commented out to avoid conflicts with the new User model.)
/*
import '../models/user.dart';

class AuthService {
  static final Map<String, List<User>> _usersByRole = {
    'driver': [],
    'passenger': [],
    'owner': [],
    'admin': [],
  };

  static bool signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String role,
  }) {
    bool userExists = _usersByRole[role]!.any((user) => user.email == email);
    if (userExists) return false;

    _usersByRole[role]!.add(User(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      role: role,
    ));
    return true;
  }

  static User? signIn({
    required String email,
    required String password,
    required String role,
  }) {
    try {
      return _usersByRole[role]!.firstWhere(
        (user) => user.email == email,
      );
    } catch (e) {
      return null;
    }
  }

  static bool isUserRegisteredForRole({
    required String email,
    required String role,
  }) {
    return _usersByRole[role]!.any((user) => user.email == email);
  }
}
*/