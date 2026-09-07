// BU Gate2Eat — Authentication Provider Contract
// Checkpoint 1.1: Provider-independent abstraction decoupling app from auth mechanism.

import 'auth_status.dart';
import 'current_identity.dart';

/// Provider-independent contract for application authentication.
///
/// The application layer depends strictly on this abstraction.
/// The underlying authentication provider (WhatsApp OTP backend, SMS, Firebase Custom Token)
/// can be modified or replaced without rewriting downstream application layers.
abstract class IAuthenticationProvider {
  /// Stream of identity changes emitting whenever auth session or custom claims change.
  Stream<CurrentIdentity> get identityChanges;

  /// Current snapshot of authenticated identity.
  CurrentIdentity get currentIdentity;

  /// Stream of authentication status transitions.
  Stream<AuthStatus> get authStatusChanges;

  /// Current snapshot of authentication status.
  AuthStatus get authStatus;

  /// Whether an authenticated session currently exists.
  bool get isSignedIn;

  /// Signs out of the active session and resets identity to unauthenticated.
  Future<void> signOut();

  /// Retrieves the current user's session ID token.
  Future<String?> getIdToken({bool forceRefresh = false});

  /// Retrieves custom claims associated with the current session token.
  Future<Map<String, dynamic>> getCustomClaims({bool forceRefresh = false});

  /// Refreshes the active session and re-evaluates identity and claims.
  Future<CurrentIdentity> refreshIdentity();
}
