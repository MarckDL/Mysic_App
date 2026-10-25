import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/mysic_profile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.profile});
  final MysicProfile profile;

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
                Text('Bienvenido, ${profile.displayName}'),
                if (profile.email != null) Text(profile.email!),
                const SizedBox(height: 12),
                const Text('Tu sesión con Google está verificada.'),
                const SizedBox(height: 12),
                const Text('Tu perfil está guardado en Mysic.'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.push('/search'),
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar música'),
                ),
                if (action.hasError)
                  const Text(
                    'No se pudo cerrar la sesión. Inténtalo de nuevo.',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
