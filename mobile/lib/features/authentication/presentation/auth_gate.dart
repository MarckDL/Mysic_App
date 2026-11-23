import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/catalog_navigator.dart';
import '../application/auth_providers.dart';
import '../domain/auth_repository.dart';
import '../../playback/application/playback_providers.dart';
import 'login_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(profileCacheProvider);
    // El perfil guardado sigue a la sesión: se borra al cerrarla o si el
    // servidor la rechaza, y se renueva con cada verificación correcta.
    ref.listen(authStateProvider, (_, next) {
      if (next.hasValue && next.value == null) unawaited(cache.clear());
    });
    ref.listen(verifiedSessionProvider, (_, next) {
      final profile = next.asData?.value;
      if (profile != null) {
        unawaited(cache.write(profile));
      } else if (next.hasError && !_unreachable(next.error)) {
        unawaited(cache.clear());
      }
    });
    final auth = ref.watch(authStateProvider);
    // No se reutilizan datos de la cuenta anterior durante un cambio de sesión.
    if (auth.isLoading) return const _LoadingScreen();
    if (auth.hasError) {
      return _SessionError(onRetry: () => ref.invalidate(authStateProvider));
    }
    final user = auth.asData?.value;
    if (user == null) return const LoginScreen();
    final verified = ref.watch(verifiedSessionProvider);
    var profile = verified.asData?.value;
    // Mientras el servidor verifica (puede tardar un minuto en despertar), o
    // si no responde, la app abre con el perfil guardado de esta misma
    // cuenta. Un rechazo del servidor nunca usa el perfil guardado.
    if (profile == null &&
        (verified.isLoading || _unreachable(verified.error))) {
      final cached = ref.watch(cachedProfileProvider(user.uid));
      if (cached.isLoading) return const _LoadingScreen();
      profile = cached.asData?.value;
    }
    if (profile == null) {
      if (verified.isLoading) return const _LoadingScreen();
      return _SessionError(
        onRetry: () => ref.invalidate(verifiedSessionProvider),
      );
    }
    // La sesión mantiene un único motor caliente durante la navegación.
    ref.watch(trackPlaybackControllerProvider);
    return CatalogNavigator(key: ValueKey(user.uid), profile: profile);
  }
}

bool _unreachable(Object? error) => error is AuthFailure && error.unreachable;

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: CircularProgressIndicator(semanticsLabel: 'Verificando sesión'),
    ),
  );
}

class _SessionError extends ConsumerWidget {
  const _SessionError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authActionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mysic')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No pudimos verificar tu sesión.'),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
            TextButton(
              onPressed: action.isLoading
                  ? null
                  : () => ref.read(authActionsProvider.notifier).signOut(),
              child: const Text('Cerrar sesión'),
            ),
            if (action.hasError)
              const Text('No se pudo cerrar la sesión. Inténtalo de nuevo.'),
          ],
        ),
      ),
    );
  }
}
