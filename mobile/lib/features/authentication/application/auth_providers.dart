import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ytm/data/ytm_auth_repository.dart';
import '../data/profile_cache.dart';
import '../domain/auth_repository.dart';
import '../domain/mysic_profile.dart';

/// La sesión de YouTube Music del teléfono: es la única identidad de la app.
final ytmAuthProvider = Provider<YtmAuthRepository>((ref) {
  final repository = YtmAuthRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ref.watch(ytmAuthProvider),
);

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  // Renovar un token de la misma cuenta no desmonta navegación ni audio.
  // Logout y cambio de UID sí deben invalidar la sesión verificada.
  return ref
      .watch(authRepositoryProvider)
      .authStateChanges()
      .distinct((previous, next) => previous?.uid == next?.uid);
}, retry: (retryCount, error) => null);

/// El perfil sale de la cuenta de YouTube Music (nombre del canal); el apodo
/// que elija el usuario se guarda en el teléfono. Sin servidor de por medio.
final verifiedSessionProvider = FutureProvider.autoDispose<MysicProfile>((
  ref,
) async {
  // Se espera a que la sesión termine de restaurarse. Si se mirara el valor
  // sin esperar, durante el arranque saldría «sin sesión», el AuthGate lo
  // tomaría por un rechazo y borraría el perfil guardado antes de leerlo: sin
  // internet la app no podría abrir con él.
  final user = await ref.watch(authStateProvider.future);
  if (user == null) throw const AuthFailure('Inicia sesión en YouTube Music.');
  final account = await ref.watch(ytmAuthProvider).verify();
  final uid = YtmAuthRepository.uidFor(account);
  final saved = await ref.watch(profileCacheProvider).read(uid);
  return MysicProfile(
    id: uid,
    uid: uid,
    displayName: account.name,
    nickname: saved?.nickname,
  );
}, retry: (retryCount, error) => null);
final profileCacheProvider = Provider<ProfileCache>(
  (ref) => const ProfileCache(),
);

/// El perfil guardado de la cuenta [uid], para abrir la app mientras
/// [verifiedSessionProvider] comprueba la sesión en segundo plano.
final cachedProfileProvider = FutureProvider.autoDispose
    .family<MysicProfile?, String>(
      (ref, uid) => ref.watch(profileCacheProvider).read(uid),
    );

final editedProfileProvider = NotifierProvider<EditedProfile, MysicProfile?>(
  EditedProfile.new,
);

class EditedProfile extends Notifier<MysicProfile?> {
  @override
  MysicProfile? build() {
    ref.watch(authStateProvider);
    return null;
  }

  Future<void> updateNickname(String uid, String? nickname) async {
    final auth = ref.read(authRepositoryProvider);
    final account = ref.read(ytmAuthProvider).account;
    if (auth.currentUser?.uid != uid || account == null) {
      throw const AuthFailure('La cuenta cambió.');
    }
    final profile = MysicProfile(
      id: uid,
      uid: uid,
      displayName: account.name,
      nickname: (nickname == null || nickname.trim().isEmpty)
          ? null
          : nickname.trim(),
    );
    // El apodo vive en el teléfono; el próximo arranque ya lo muestra.
    await ref.read(profileCacheProvider).write(profile);
    if (ref.mounted) state = profile;
  }
}

final authActionsProvider = NotifierProvider<AuthActions, AsyncValue<void>>(
  AuthActions.new,
);

class AuthActions extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> signIn() => _run(ref.read(authRepositoryProvider).signIn);
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
