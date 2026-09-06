// BU Gate2Eat — Authentication Service
// Clean Firebase Authentication foundation wrapper.
// Encapsulates FirebaseAuth interactions for future custom-token (WhatsApp OTP) transition.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Minimal, decoupled service wrapper around [FirebaseAuth].
/// Keeps authentication foundation separate from role and Firestore state.
class AuthService {
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
  bool get isSignedIn => currentUser != null;

  /// Stream of authentication state changes (fires on login / logout).
  Stream<User?> authStateChanges() =>
      _auth?.authStateChanges() ?? Stream<User?>.value(null);

  /// Stream of ID token changes (fires on login, logout, or token refresh).
  Stream<User?> idTokenChanges() =>
      _auth?.idTokenChanges() ?? Stream<User?>.value(null);

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
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }
}
