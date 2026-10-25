import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/network/api_config.dart';
import '../data/backend_session_client.dart';
import '../data/firebase_auth_repository.dart';
import '../domain/auth_repository.dart';
import '../domain/mysic_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(FirebaseAuth.instance, GoogleSignIn.instance);
});

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
}, retry: (retryCount, error) => null);

final backendSessionClientProvider = Provider<BackendSessionClient>((ref) {
  final client = BackendSessionClient(
    ref.watch(authRepositoryProvider),
    baseUrl: ApiConfig.baseUrl,
  );
  ref.onDispose(client.close);
  return client;
});

final verifiedSessionProvider = FutureProvider.autoDispose<MysicProfile>((
  ref,
) async {
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) throw const AuthFailure('Inicia sesión con Google.');
  return ref.watch(backendSessionClientProvider).syncProfile();
}, retry: (retryCount, error) => null);

final authActionsProvider = NotifierProvider<AuthActions, AsyncValue<void>>(
  AuthActions.new,
);

class AuthActions extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> signIn() =>
      _run(ref.read(authRepositoryProvider).signInWithGoogle);
  Future<void> signOut() => _run(ref.read(authRepositoryProvider).signOut);

  Future<void> _run(Future<void> Function() action) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    try {
      await action();
      if (ref.mounted) state = const AsyncData(null);
    } catch (error, stack) {
      if (!ref.mounted) return;
      if (error is AuthFailure && error.cancelled) {
        state = const AsyncData(null);
      } else {
        state = AsyncError(
          error is AuthFailure
              ? error
              : const AuthFailure('No se pudo completar la operación.'),
          stack,
        );
      }
    }
  }
}
