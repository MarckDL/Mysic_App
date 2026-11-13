import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/favorite_providers.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final action = ref.watch(favoriteActionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mis favoritos')),
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
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: TrackArtwork(
                          url: item.track.thumbnailUrl,
                          size: 56,
                        ),
                        title: Text(item.track.title),
                        subtitle: Text(item.track.artistName),
                        onTap: () => context.push('/tracks/${item.track.id}'),
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
