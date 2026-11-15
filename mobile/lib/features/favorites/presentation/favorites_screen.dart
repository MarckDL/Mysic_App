import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../playback/presentation/open_player.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/favorite_providers.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final action = ref.watch(favoriteActionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: SafeArea(
        child: favorites.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No se pudieron cargar tus favoritos.'),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(favoritesProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
          data: (items) => RefreshIndicator(
            onRefresh: () => ref.refresh(favoritesProvider.future),
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 160),
                      Icon(Icons.favorite_border, size: 48),
                      SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Todavía no tienes favoritos.\nAgrégalos desde el detalle de una canción.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length + 1,
                    separatorBuilder: (context, index) => index == 0
                        ? const SizedBox(height: 8)
                        : const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final tracks = items.map((item) => item.track).toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${items.length} ${items.length == 1 ? 'canción' : 'canciones'}',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => playTracksAndOpenPlayer(
                                      context,
                                      ref,
                                      tracks,
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: Text(
                                      tracks.length <= 100
                                          ? 'Reproducir todo'
                                          : 'Reproducir primeras 100',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filledTonal(
                                  tooltip: tracks.length <= 100
                                      ? 'Reproducción aleatoria'
                                      : 'Reproducir 100 al azar',
                                  onPressed: () => playTracksAndOpenPlayer(
                                    context,
                                    ref,
                                    tracks.toList()..shuffle(),
                                  ),
                                  icon: const Icon(Icons.shuffle_rounded),
                                ),
                              ],
                            ),
                          ],
                        );
                      }
                      final item = items[index - 1];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: TrackArtwork(
                          url: item.track.thumbnailUrl,
                          size: 56,
                        ),
                        title: Text(item.track.title),
                        subtitle: Text(
                          [
                            item.track.artistName,
                            ?item.track.durationLabel,
                          ].join(' · '),
                        ),
                        onTap: () =>
                            playAndOpenPlayer(context, ref, item.track),
                        trailing: IconButton(
                          tooltip: 'Quitar de favoritos',
                          onPressed: action.isLoading
                              ? null
                              : () async {
                                  final removed = await ref
                                      .read(favoriteActionsProvider.notifier)
                                      .setFavorite(item.track.id, false);
                                  if (!removed && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'No se pudo quitar de favoritos.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          color: Theme.of(context).colorScheme.primary,
                          icon: const Icon(Icons.favorite),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
