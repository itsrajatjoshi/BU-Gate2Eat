// BU Gate2Eat — Authentication State & Role Enums
// Checkpoint 1.1: Provider-independent authentication states, application roles, and account statuses.

/// Canonical authentication states for the application.
enum AuthStatus {
  /// Session state is being determined / initializing.
  unknown,

  /// No active authenticated session.
  unauthenticated,

  /// Valid authenticated Firebase session exists.
  authenticated,

  /// User explicitly signed out.
  signedOut,

  /// User account is deactivated or revoked.
  deactivated,

  /// An unrecoverable authentication error occurred.
  error,
}

/// Canonical application roles recognized by the authorization layer.
enum AuthRole {
  /// Regular customer ordering food.
  customer,

  /// Shopkeeper managing an assigned shop.
  shopkeeper,

  /// Platform administrator.
  admin,

  /// No role assigned or unauthenticated.
  none,
}

/// Canonical account status for authorization checks.
enum AccountStatus {
  /// Account is active and in good standing.
  active,

  /// Account has been deactivated or revoked.
  deactivated,

  /// Account status is unknown / uninitialized.
  unknown,
}
