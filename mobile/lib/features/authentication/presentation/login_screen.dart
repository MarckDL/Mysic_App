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
      appBar: AppBar(title: const Text('Mysic')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tu espacio musical',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text('Inicia sesión con Google para acceder a Mysic.'),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: action.isLoading
                      ? null
                      : () => ref.read(authActionsProvider.notifier).signIn(),
                  child: Text(
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
