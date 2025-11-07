import 'dart:developer' as developer;

/// Phone number validation utility for Kenyan phone numbers
class PhoneValidator {
  /// Validates Kenyan phone number format
  /// Accepts formats: 0712345678, +254712345678, 254712345678
  static bool isValidKenyanPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return false;
    }

    // Remove all whitespace and special characters except + and digits
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // Check for Kenyan phone number patterns
    // Pattern 1: +254XXXXXXXXX (12 digits after +254)
    // Pattern 2: 254XXXXXXXXX (12 digits starting with 254)
    // Pattern 3: 0XXXXXXXXX (10 digits starting with 0)
    final patterns = [
      RegExp(r'^\+254[17]\d{8}$'), // +254712345678
      RegExp(r'^254[17]\d{8}$'),   // 254712345678
      RegExp(r'^0[17]\d{8}$'),      // 0712345678
    ];

    return patterns.any((pattern) => pattern.hasMatch(cleaned));
  }

  /// Normalizes phone number to standard format (254XXXXXXXXX)
  static String? normalizePhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return null;
    }

    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    if (cleaned.startsWith('+254')) {
      return cleaned.substring(1); // Remove +
    } else if (cleaned.startsWith('254')) {
      return cleaned;
    } else if (cleaned.startsWith('0')) {
      return '254${cleaned.substring(1)}'; // Replace 0 with 254
    }
    
    return cleaned;
  }

  /// Gets validation error message
  static String? getValidationError(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return 'Phone number is required';
    }
    if (!isValidKenyanPhone(phone)) {
      return 'Enter a valid Kenyan phone number (e.g., 0712345678 or +254712345678)';
    }
    return null;
  }
}

/// Simple logging utility for production debugging
class AppLogger {
  static const bool _enableLogging = true; // Set to false in production if needed

  static void info(String message, [String? tag]) {
    if (_enableLogging) {
      developer.log(
        message,
        name: tag ?? 'BeautyBazaar',
        level: 800, // INFO level
      );
    }
  }

  static void warning(String message, [String? tag]) {
    if (_enableLogging) {
      developer.log(
        message,
        name: tag ?? 'BeautyBazaar',
        level: 900, // WARNING level
      );
    }
  }

  static void error(String message, [Object? error, StackTrace? stackTrace, String? tag]) {
    if (_enableLogging) {
      developer.log(
        message,
        name: tag ?? 'BeautyBazaar',
        error: error,
        stackTrace: stackTrace,
        level: 1000, // ERROR level
      );
    }
  }

  static void debug(String message, [String? tag]) {
    if (_enableLogging) {
      developer.log(
        message,
        name: tag ?? 'BeautyBazaar',
        level: 700, // DEBUG level
      );
    }
  }
}


