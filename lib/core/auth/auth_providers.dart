// BU Gate2Eat — Authentication Providers
// Checkpoint 1.1: Provider-independent Riverpod providers for authentication.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart' show authServiceProvider;
import 'auth_provider_interface.dart';
import 'auth_status.dart';
import 'current_identity.dart';

/// Provider for the active authentication abstraction contract.
final authProvider = Provider<IAuthenticationProvider>((ref) {
  return ref.watch(authServiceProvider);
});

/// Stream provider emitting reactive updates whenever [CurrentIdentity] changes.
final currentIdentityStreamProvider = StreamProvider<CurrentIdentity>((ref) {
  final provider = ref.watch(authProvider);
  return provider.identityChanges;
});

/// Reactive provider exposing the current snapshot of [CurrentIdentity].
final currentIdentityProvider = Provider<CurrentIdentity>((ref) {
  final streamState = ref.watch(currentIdentityStreamProvider);
  return streamState.asData?.value ?? ref.watch(authProvider).currentIdentity;
});

/// Reactive provider exposing the current [AuthStatus].
final authStatusProvider = Provider<AuthStatus>((ref) {
  final identity = ref.watch(currentIdentityProvider);
  return identity.authStatus;
});
