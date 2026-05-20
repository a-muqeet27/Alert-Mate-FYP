/// Shared form validators for auth and profile fields.
class FormValidators {
  FormValidators._();

  static final RegExp _lettersOnly = RegExp(r'^[A-Za-z]+$');

  static String? validateFirstName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'First name is required';
    }
    final trimmed = value.trim();
    if (!_lettersOnly.hasMatch(trimmed)) {
      return 'First name can contain only letters';
    }
    return null;
  }

  static String? validateLastName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Last name is required';
    }
    final trimmed = value.trim();
    if (!_lettersOnly.hasMatch(trimmed)) {
      return 'Last name can contain only letters';
    }
    return null;
  }

  static String? validatePhone(String value, {String countryIso = 'PK'}) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) {
      return 'Please enter a valid phone number';
    }
    switch (countryIso.toUpperCase()) {
      case 'PK':
        if (!RegExp(r'^03\d{9}$').hasMatch(cleaned)) {
          return 'Phone number must contain 11 digits (e.g. 03XX-XXXXXXX)';
        }
        break;
      case 'US':
      case 'CA':
        if (!RegExp(r'^\d{10}$').hasMatch(cleaned)) {
          return 'Please enter a valid phone number (10 digits)';
        }
        break;
      default:
        if (cleaned.length < 7 || cleaned.length > 15) {
          return 'Please enter a valid phone number';
        }
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final email = value.trim();
    if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? validatePassword(String? value, {int minLength = 6}) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < minLength) {
      return 'Password must be at least $minLength characters';
    }
    return null;
  }
}