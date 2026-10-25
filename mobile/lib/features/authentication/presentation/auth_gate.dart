import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/home_screen.dart';
import '../application/auth_providers.dart';
import 'login_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    // No se reutilizan datos de la cuenta anterior durante un cambio de sesión.
    if (auth.isLoading) return const _LoadingScreen();
    if (auth.hasError) {
      return _SessionError(onRetry: () => ref.invalidate(authStateProvider));
    }
    final user = auth.asData?.value;
    if (user == null) return const LoginScreen();
    final verified = ref.watch(verifiedSessionProvider);
    if (verified.isLoading) return const _LoadingScreen();
    if (verified.hasError) {
      return _SessionError(
          onRetry: () => ref.invalidate(verifiedSessionProvider));
    }
    return HomeScreen(displayName: user.displayName);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
            child: CircularProgressIndicator(
                semanticsLabel: 'Verificando sesión')),
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
