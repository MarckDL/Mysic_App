import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/mysic_profile.dart';
import '../../youtube_library/application/youtube_library_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.profile});
  final MysicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authActionsProvider);
    final youtubeAction = ref.watch(youtubeLibraryActionsProvider);
    final youtube = ref.watch(youtubeConnectionStatusProvider);
    final initial = profile.displayName.trim().isEmpty
        ? 'M'
        : profile.displayName.trim()[0].toUpperCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  initial,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              profile.displayName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (profile.email != null)
              Text(
                profile.email!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 28),
            const Card(
              child: ListTile(
                leading: Icon(Icons.verified_user_outlined),
                title: Text('Cuenta de Mysic'),
                subtitle: Text('Sesión verificada con Google y Firebase'),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: youtube.when(
                  loading: () => const Row(
                    children: [
                      SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Consultando conexión con YouTube…'),
                    ],
                  ),
                  error: (error, _) => Row(
                    children: [
                      const Expanded(
                        child: Text('No se pudo consultar YouTube.'),
                      ),
                      IconButton(
                        onPressed: () =>
                            ref.invalidate(youtubeConnectionStatusProvider),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  data: (status) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              status.connected
                                  ? status.displayName ?? 'YouTube conectado'
                                  : 'Conectar YouTube',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (status.connected)
                            const Chip(label: Text('Solo lectura')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status.connected
                            ? '${status.playlistCount} playlists · ${status.likedTrackCount} Me gusta\nLa autorización temporal no se guarda.'
                            : 'Importa manualmente playlists y videos marcados con Me gusta. Es una sesión separada de Firebase.',
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: youtubeAction.isLoading
                              ? null
                              : () async {
                                  final ok = await ref
                                      .read(
                                        youtubeLibraryActionsProvider.notifier,
                                      )
                                      .connectAndSync();
                                  if (!context.mounted || ok) return;
                                  final failure = ref
                                      .read(youtubeLibraryActionsProvider)
                                      .error;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        failure is Exception
                                            ? failure.toString().replaceFirst(
                                                'Exception: ',
                                                '',
                                              )
                                            : 'No se pudo sincronizar YouTube.',
                                      ),
                                    ),
                                  );
                                },
                          icon: Icon(
                            status.connected ? Icons.sync : Icons.link,
                          ),
                          label: Text(
                            status.connected
                                ? 'Actualizar ahora'
                                : 'Conectar y sincronizar',
                          ),
                        ),
                      ),
                      if (status.connected)
                        TextButton(
                          onPressed: youtubeAction.isLoading
                              ? null
                              : () => ref
                                    .read(
                                      youtubeLibraryActionsProvider.notifier,
                                    )
                                    .disconnect(),
                          child: const Text('Desconectar datos importados'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: action.isLoading
                  ? null
                  : () => ref.read(authActionsProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}
