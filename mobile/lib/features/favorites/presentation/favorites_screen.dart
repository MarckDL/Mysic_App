import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../playback/application/playback_providers.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/favorite_providers.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mis favoritos')),
      body: SafeArea(
        child: favorites.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => CatalogError(
            error: error,
            retry: () => ref.invalidate(favoritesProvider),
          ),
          data: (items) => items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Todavía no tienes favoritos. Añade canciones desde su detalle.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(favoritesProvider.future),
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final track = items[index].track;
                      return ListTile(
                        leading: TrackArtwork(url: track.thumbnailUrl),
                        title: Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          track.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Reproducir canción',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => unawaited(
                            ref
                                .read(trackPlaybackControllerProvider)
                                .playTrack(track),
                          ),
                        ),
                        onTap: () => context.push(
                          '/tracks/${Uri.encodeComponent(track.id)}',
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
