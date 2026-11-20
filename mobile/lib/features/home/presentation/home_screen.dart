import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/mysic_profile.dart';
import '../../history/data/history_client.dart';
import '../../favorites/application/favorite_providers.dart';
import '../../playlists/application/playlist_providers.dart';
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
            const SizedBox(height: 4),
            Text(
              '¿Qué escuchamos hoy?',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            const _DiscoverCard(),
            const SizedBox(height: 24),
            Text(
              'Acceso rápido',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const _QuickLinks(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Volver a escuchar',
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
                          SizedBox(
                            height:
                                200 +
                                MediaQuery.textScalerOf(context).scale(32),
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final track = items[index].track;
                                return SizedBox(
                                  width: 124,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () =>
                                        playAndOpenPlayer(context, ref, track),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Stack(
                                          children: [
                                            TrackArtwork(
                                              url: track.thumbnailUrl,
                                              size: 124,
                                              borderRadius: 14,
                                            ),
                                            const Positioned(
                                              right: 8,
                                              bottom: 8,
                                              child: CircleAvatar(
                                                radius: 14,
                                                backgroundColor: Colors.white,
                                                child: Icon(
                                                  Icons.play_arrow,
                                                  size: 20,
                                                  color: Color(0xFF745096),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          track.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          track.artistName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                ),
            ...ref
                .watch(favoritesProvider)
                .maybeWhen(
                  data: (items) => items.isEmpty
                      ? <Widget>[]
                      : [
                          const SizedBox(height: 16),
                          Text(
                            'Tus favoritos',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          for (final item in items.take(3))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: TrackArtwork(
                                url: item.track.thumbnailUrl,
                                size: 48,
                              ),
                              title: Text(
                                item.track.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(item.track.artistName),
                              trailing: Text(item.track.durationLabel ?? ''),
                              onTap: () =>
                                  playAndOpenPlayer(context, ref, item.track),
                            ),
                        ],
                  orElse: () => <Widget>[],
                ),
            ...ref
                .watch(playlistsProvider)
                .maybeWhen(
                  data: (items) => items.isEmpty
                      ? <Widget>[]
                      : [
                          const SizedBox(height: 20),
                          Text(
                            'Tus playlists',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          for (final playlist in items.take(3))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: TrackArtwork(
                                url: playlist.thumbnailUrl,
                                size: 56,
                                fallbackIcon: Icons.queue_music,
                              ),
                              title: Text(playlist.name),
                              subtitle: Text(
                                '${playlist.trackCount} canciones',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.push('/playlists/${playlist.id}'),
                            ),
                        ],
                  orElse: () => <Widget>[],
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

class _QuickLinks extends StatelessWidget {
  const _QuickLinks();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 6,
      runSpacing: 8,
      children: [
        for (final (label, icon, path) in [
          ('Favoritos', Icons.favorite_border, '/favorites'),
          ('Playlists', Icons.queue_music, '/playlists'),
          ('Descargas', Icons.download_outlined, ''),
          ('Historial', Icons.history, '/history'),
        ])
          SizedBox(
            width:
                (constraints.maxWidth - 18) /
                (MediaQuery.textScalerOf(context).scale(1) > 1.5 ? 2 : 4),
            child: Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: path.isEmpty ? null : () => context.push(path),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        icon,
                        color: path.isEmpty
                            ? Theme.of(context).disabledColor
                            : Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      if (path.isEmpty)
                        Text(
                          'Próximamente',
                          style: Theme.of(context).textTheme.labelSmall,
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
