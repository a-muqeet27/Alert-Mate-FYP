import 'package:flutter/services.dart';

/// Formats Pakistani mobile numbers as 03XX-1234567 while typing.
class PakistaniPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 11; i++) {
      if (i == 4) buffer.write('-');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

bool isValidPakistaniMobile(String phone) {
  return RegExp(r'^03\d{2}-\d{7}$').hasMatch(phone.trim());
}

String sanitizePhoneForDial(String raw) => raw.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
