// BU Gate2Eat — Safe Authentication Exceptions
// Checkpoint 1.1: Error classification that never leaks credentials, tokens, or OTP secrets.

/// Safe error categories for authentication failures.
enum AuthErrorCode {
  unauthenticated,
  invalidCredentials,
  networkError,
  userDisabled,
  sessionExpired,
  unknown,
}

/// Generic, safe authentication exception for client and UI presentation.
/// Guarantees that internal backend details, tokens, secrets, or stack traces
/// are NEVER exposed to client screens.
class AuthException implements Exception {
  const AuthException({
    required this.code,
    required this.message,
    this.debugDetails,
  });

  /// Safe categorized error code.
  final AuthErrorCode code;

  /// User-safe message suitable for UI display.
  final String message;

  /// Development-only technical details. Must never be presented to end users.
  final String? debugDetails;

  @override
  String toString() => 'AuthException($code): $message';
}
