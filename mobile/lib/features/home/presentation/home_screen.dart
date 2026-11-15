import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/mysic_profile.dart';
import '../../history/data/history_client.dart';
import '../../playback/presentation/open_player.dart';
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
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.graphic_eq_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Flexible(
              child: Text('Mysic', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [accountAction],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Text(
              'Bienvenido, $name',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            const _DiscoverCard(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recientes',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/history'),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Ver todo'),
                ),
              ],
            ),
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
                              contentPadding: EdgeInsets.zero,
                              leading: TrackArtwork(
                                url: item.track.thumbnailUrl,
                                size: 52,
                                borderRadius: 10,
                              ),
                              title: Text(
                                item.track.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  item.track.artistName,
                                  ?item.track.durationLabel,
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: 'Detalles de la canción',
                                icon: const Icon(Icons.more_horiz),
                                onPressed: () => context.push(
                                  '/tracks/${Uri.encodeComponent(item.track.id)}',
                                ),
                              ),
                              onTap: () =>
                                  playAndOpenPlayer(context, ref, item.track),
                            ),
                        ],
                ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFF24213A),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/discover-mountains.webp',
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xC4161427)],
                  stops: [0.3, 1],
                ),
              ),
            ),
          ),
          InkWell(
            onTap: () => context.go('/search'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 172),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Descubre nuevas canciones',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const CircleAvatar(
                      backgroundColor: Color(0xFFC7A9F6),
                      foregroundColor: Color(0xFF26163D),
                      child: Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
