import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_providers.dart';
import '../domain/auth_repository.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authActionsProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.graphic_eq,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text('Mysic', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 32),
                Text(
                  'Tu música, contigo',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text('Inicia sesión con Google para acceder a Mysic.'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: action.isLoading
                      ? null
                      : () => ref.read(authActionsProvider.notifier).signIn(),
                  icon: const Icon(Icons.login),
                  label: Text(
                    action.isLoading
                        ? 'Iniciando sesión…'
                        : 'Continuar con Google',
                  ),
                ),
                if (action.hasError) ...[
                  const SizedBox(height: 16),
                  Text(
                    (action.error as AuthFailure).message,
                    semanticsLabel: 'Error de autenticación',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
