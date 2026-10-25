import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.displayName});
  final String? displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authActionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mysic'),
        actions: [
          TextButton(
            onPressed: action.isLoading
                ? null
                : () => ref.read(authActionsProvider.notifier).signOut(),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(displayName == null
                    ? 'Bienvenido a Mysic'
                    : 'Bienvenido, $displayName'),
                const SizedBox(height: 12),
                const Text('Tu sesión con Google está verificada.'),
                if (action.hasError)
                  const Text(
                      'No se pudo cerrar la sesión. Inténtalo de nuevo.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
