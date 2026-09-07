// BU Gate2Eat — Canonical Authenticated Identity
// Checkpoint 1.1: Canonical CurrentIdentity model originating strictly from Firebase Auth.

import 'auth_status.dart';

/// Immutable canonical model representing the verified caller identity.
///
/// Security Contract:
/// - Authenticated identity MUST originate from an authenticated Firebase session.
/// - SharedPreferences, route parameters, local phone strings, and client role variables
///   are NOT authoritative identity.
/// - In the canonical architecture: `customerId == uid`.
class CurrentIdentity {
  const CurrentIdentity({
    required this.uid,
    required this.phone,
    required this.authStatus,
    required this.role,
    this.shopId,
    required this.customerId,
    this.accountStatus = AccountStatus.active,
    this.displayName,
  });

  /// Authoritative Firebase UID.
  final String uid;

  /// Verified phone number associated with the session.
  final String phone;

  /// Current authentication state.
  final AuthStatus authStatus;

  /// Application role resolved from backend custom claims or verification.
  final AuthRole role;

  /// Assigned shop ID if the caller is an authorized shopkeeper.
  final String? shopId;

  /// Canonical customer ID. In the target architecture, `customerId == uid`.
  final String customerId;

  /// Account operational status (active / deactivated / unknown).
  final AccountStatus accountStatus;

  /// Optional display name or profile name.
  final String? displayName;

  /// Standard unauthenticated identity instance.
  static const CurrentIdentity unauthenticated = CurrentIdentity(
    uid: '',
    phone: '',
    authStatus: AuthStatus.unauthenticated,
    role: AuthRole.none,
    shopId: null,
    customerId: '',
    accountStatus: AccountStatus.unknown,
    displayName: null,
  );

  /// Helper properties
  bool get isAuthenticated =>
      authStatus == AuthStatus.authenticated && uid.isNotEmpty;
  bool get isCustomer => role == AuthRole.customer;
  bool get isShopkeeper =>
      role == AuthRole.shopkeeper && shopId != null && shopId!.isNotEmpty;
  bool get isAdmin => role == AuthRole.admin;
  bool get isActive => accountStatus == AccountStatus.active;

  /// Creates a copy of this identity with specific fields updated.
  CurrentIdentity copyWith({
    String? uid,
    String? phone,
    AuthStatus? authStatus,
    AuthRole? role,
    String? shopId,
    String? customerId,
    AccountStatus? accountStatus,
    String? displayName,
  }) {
    return CurrentIdentity(
      uid: uid ?? this.uid,
      phone: phone ?? this.phone,
      authStatus: authStatus ?? this.authStatus,
      role: role ?? this.role,
      shopId: shopId ?? this.shopId,
      customerId: customerId ?? this.customerId,
      accountStatus: accountStatus ?? this.accountStatus,
      displayName: displayName ?? this.displayName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrentIdentity &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          phone == other.phone &&
          authStatus == other.authStatus &&
          role == other.role &&
          shopId == other.shopId &&
          customerId == other.customerId &&
          accountStatus == other.accountStatus &&
          displayName == other.displayName;

  @override
  int get hashCode =>
      uid.hashCode ^
      phone.hashCode ^
      authStatus.hashCode ^
      role.hashCode ^
      shopId.hashCode ^
      customerId.hashCode ^
      accountStatus.hashCode ^
      displayName.hashCode;

  @override
  String toString() =>
      'CurrentIdentity(uid: $uid, phone: $phone, authStatus: $authStatus, role: $role, shopId: $shopId, customerId: $customerId, accountStatus: $accountStatus)';
}
