// BU Gate2Eat — Authentication Service
// Clean Firebase Authentication foundation wrapper and IAuthenticationProvider implementation.
// Encapsulates FirebaseAuth interactions for future custom-token (WhatsApp OTP) transition.

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/auth/auth_provider_interface.dart';
import '../core/auth/auth_status.dart';
import '../core/auth/current_identity.dart';

/// Minimal, decoupled service wrapper around [FirebaseAuth] implementing [IAuthenticationProvider].
/// Keeps authentication foundation separate from role, Firestore state, and specific OTP providers.
class AuthService implements IAuthenticationProvider {
  AuthService({FirebaseAuth? firebaseAuth}) : _customAuth = firebaseAuth;

  final FirebaseAuth? _customAuth;

  FirebaseAuth? get _auth {
    if (_customAuth != null) return _customAuth;
    try {
      return FirebaseAuth.instance;
    } catch (e) {
      debugPrint('⚠️ [AuthService] FirebaseAuth instance unavailable: $e');
      return null;
    }
  }

  /// Exposes the underlying [FirebaseAuth] instance.
  FirebaseAuth? get firebaseAuth => _auth;

  /// Gets the currently authenticated Firebase user, or null if unauthenticated.
  User? get currentUser => _auth?.currentUser;

  /// Whether a Firebase user is currently authenticated.
  @override
  bool get isSignedIn => currentUser != null;

  /// Current authentication status snapshot.
  @override
  AuthStatus get authStatus {
    final user = currentUser;
    if (user == null) return AuthStatus.unauthenticated;
    return AuthStatus.authenticated;
  }

  /// Gets the snapshot of the current authenticated identity.
  @override
  CurrentIdentity get currentIdentity {
    final user = currentUser;
    if (user == null) return CurrentIdentity.unauthenticated;
    return mapUserToIdentity(user, const {});
  }

  /// Stream of authentication state changes (fires on login / logout).
  Stream<User?> authStateChanges() =>
      _auth?.authStateChanges() ?? Stream<User?>.value(null);

  /// Stream of ID token changes (fires on login, logout, or token refresh).
  Stream<User?> idTokenChanges() =>
      _auth?.idTokenChanges() ?? Stream<User?>.value(null);

  /// Stream of raw authentication status changes.
  @override
  Stream<AuthStatus> get authStatusChanges {
    final auth = _auth;
    if (auth == null) {
      return Stream<AuthStatus>.value(AuthStatus.unauthenticated);
    }
    return auth.authStateChanges().map((user) {
      if (user == null) return AuthStatus.unauthenticated;
      return AuthStatus.authenticated;
    });
  }

  /// Stream of canonical [CurrentIdentity] changes.
  @override
  Stream<CurrentIdentity> get identityChanges {
    final auth = _auth;
    if (auth == null) {
      return Stream<CurrentIdentity>.value(CurrentIdentity.unauthenticated);
    }
    return auth.idTokenChanges().asyncMap((user) async {
      if (user == null) return CurrentIdentity.unauthenticated;
      final claims = await getCustomClaims();
      return mapUserToIdentity(user, claims);
    });
  }

  /// Helper to convert a Firebase [User] and Custom Claims into canonical [CurrentIdentity].
  /// Authentication (who the caller is = uid) is strictly separated from
  /// Authorization (what the caller can do = role & shopId claims).
  static CurrentIdentity mapUserToIdentity(User? user, Map<String, dynamic> claims) {
    if (user == null) {
      return CurrentIdentity.unauthenticated;
    }

    final rawRole = claims['role']?.toString().toLowerCase().trim() ?? '';
    final AuthRole role;
    if (rawRole == 'admin') {
      role = AuthRole.admin;
    } else if (rawRole == 'shopkeeper') {
      role = AuthRole.shopkeeper;
    } else if (rawRole == 'customer') {
      role = AuthRole.customer;
    } else {
      role = AuthRole.customer; // Default safe client role when authenticated
    }

    final rawShopId = claims['shopId']?.toString().trim();
    final shopId = (role == AuthRole.shopkeeper && rawShopId != null && rawShopId.isNotEmpty)
        ? rawShopId
        : null;

    final rawStatus = claims['status']?.toString().toLowerCase().trim() ?? '';
    final AccountStatus accountStatus;
    if (rawStatus == 'deactivated' || rawStatus == 'disabled' || rawStatus == 'revoked') {
      accountStatus = AccountStatus.deactivated;
    } else {
      accountStatus = AccountStatus.active;
    }

    // Phone: prioritize claims['phone'] if present, then user.phoneNumber
    final phone = (claims['phone'] ?? user.phoneNumber ?? '').toString().trim();

    return CurrentIdentity(
      uid: user.uid,
      phone: phone,
      authStatus: accountStatus == AccountStatus.deactivated
          ? AuthStatus.deactivated
          : AuthStatus.authenticated,
      role: role,
      shopId: shopId,
      customerId: user.uid, // Canonical customerId == uid
      accountStatus: accountStatus,
      displayName: user.displayName,
    );
  }

  /// Refreshes the active session and re-evaluates identity and claims.
  @override
  Future<CurrentIdentity> refreshIdentity() async {
    final user = currentUser;
    if (user == null) return CurrentIdentity.unauthenticated;
    final claims = await getCustomClaims(forceRefresh: true);
    return mapUserToIdentity(user, claims);
  }

  /// Signs in using a server-minted Firebase Custom Token.
  /// Used when the backend verifies WhatsApp OTP and returns a custom token.
  /// The client must NEVER generate custom tokens.
  Future<UserCredential> signInWithCustomToken(String token) async {
    final auth = _auth;
    if (auth == null) {
      throw StateError('FirebaseAuth is not initialized');
    }
    try {
      final credential = await auth.signInWithCustomToken(token);
      debugPrint('🔥 [AuthService] Signed in with custom token: ${credential.user?.uid}');
      return credential;
    } catch (e) {
      debugPrint('❌ [AuthService] signInWithCustomToken error: $e');
      rethrow;
    }
  }

  /// Signs out of Firebase Auth.
  @override
  Future<void> signOut() async {
    try {
      final auth = _auth;
      if (auth != null) {
        await auth.signOut();
        debugPrint('🔥 [AuthService] Signed out of Firebase Auth');
      }
    } catch (e) {
      debugPrint('⚠️ [AuthService] signOut note: $e');
      // Do not throw; failsafe so caller session clearing is never blocked
    }
  }

  /// Retrieves the current user's ID token, optionally forcing a refresh.
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  /// Retrieves custom claims associated with the current user's ID token.
  /// Returns empty map if unauthenticated or on error.
  @override
  Future<Map<String, dynamic>> getCustomClaims({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return const {};
    try {
      final tokenResult = await user.getIdTokenResult(forceRefresh);
      return tokenResult.claims ?? const {};
    } catch (e) {
      debugPrint('⚠️ [AuthService] getCustomClaims error: $e');
      return const {};
    }
  }
}
