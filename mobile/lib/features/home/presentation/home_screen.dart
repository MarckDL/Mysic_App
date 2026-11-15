import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/mysic_profile.dart';
import '../../history/data/history_client.dart';
import '../../search/presentation/catalog_widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.profile,
    required this.accountAction,
  });

  final MysicProfile profile;
  final Widget accountAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editedProfile = ref.watch(editedProfileProvider);
    final name = editedProfile?.firebaseUid == profile.firebaseUid
        ? editedProfile!.preferredName
        : profile.preferredName;
    final recent = recentListeningProvider(profile.firebaseUid);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mysic'), actions: [accountAction]),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card.filled(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.graphic_eq_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 32,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Bienvenido, $name',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.go('/search'),
                      icon: const Icon(Icons.search),
                      label: const Text('Buscar música'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Escuchadas recientemente', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            ...ref
                .watch(recent)
                .when(
                  loading: () => [
                    const LinearProgressIndicator(
                      semanticsLabel: 'Cargando escuchas recientes',
                    ),
                  ],
                  error: (error, stack) => [
                    const Text('No se pudieron cargar tus escuchas recientes.'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => ref.invalidate(recent),
                        child: const Text('Reintentar'),
                      ),
                    ),
                  ],
                  data: (items) => items.isEmpty
                      ? [
                          const Text('Aquí aparecerá la música que escuches.'),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => context.go('/search'),
                              child: const Text('Explorar catálogo'),
                            ),
                          ),
                        ]
                      : [
                          for (final item in items)
                            ListTile(
                              leading: TrackArtwork(
                                url: item.track.thumbnailUrl,
                              ),
                              title: Text(item.track.title),
                              subtitle: Text(item.track.artistName),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push(
                                '/tracks/${Uri.encodeComponent(item.track.id)}',
                              ),
                            ),
                        ],
                ),
          ],
        ),
      ),
    );
  }
}
