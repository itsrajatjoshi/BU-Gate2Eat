// BU Gate2Eat — Core Utils
// Network Error Helper (Checkpoint 3 — Offline / Weak Internet)
// Converts raw Firebase/network exceptions into user-friendly YummBU feedback.

class NetworkErrorHelper {
  NetworkErrorHelper._();

  /// Determines if [error] represents a network connectivity or backend reachability issue.
  static bool isNetworkOrUnavailableError(Object? error) {
    if (error == null) return false;
    final str = error.toString().toLowerCase();
    return str.contains('unavailable') ||
        str.contains('network') ||
        str.contains('offline') ||
        str.contains('connection') ||
        str.contains('timeout') ||
        str.contains('socketexception') ||
        str.contains('client is offline');
  }

  /// Converts an exception into concise, user-friendly YummBU feedback.
  /// Example:
  /// - Firebase network exception -> "Couldn't update order. Please check your connection and try again."
  /// - Specific validation message -> "Couldn't update order: Order has already been accepted."
  static String toUserFriendlyMessage(
    Object? error, {
    required String defaultPrefix,
  }) {
    if (isNetworkOrUnavailableError(error)) {
      return '$defaultPrefix. Please check your connection and try again.';
    }

    var msg = error?.toString() ?? '';
    // Strip technical exception prefixes like "OrderServiceException: " or "FirebaseException: "
    msg = msg.replaceAll(RegExp(r'^[a-zA-Z0-9_]+Exception:\s*'), '');
    msg = msg.replaceAll(RegExp(r'^\[.*?\]\s*'), '');
    msg = msg.trim();

    if (msg.isEmpty) {
      return '$defaultPrefix. Please try again.';
    }
    return '$defaultPrefix: $msg';
  }
}
