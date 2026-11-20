import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../playback/presentation/open_player.dart';
import '../../playback/application/playback_providers.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/playlist_providers.dart';
import '../domain/playlist.dart';
import 'playlists_screen.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.id});
  final String id;

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(playlistDetailProvider(id));
    final action = ref.watch(playlistActionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Playlist')),
      body: SafeArea(
        child: value.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(playlistErrorText(error)),
                TextButton(
                  onPressed: () => ref.invalidate(playlistDetailProvider(id)),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
          data: (playlist) {
            final tracks = playlist.tracks.map((item) => item.track).toList();
            final knownDuration =
                tracks.isNotEmpty &&
                tracks.every((track) => track.durationSeconds != null);
            final seconds = tracks.fold<int>(
              0,
              (sum, track) => sum + (track.durationSeconds ?? 0),
            );
            final controller = ref.watch(trackPlaybackControllerProvider);
            return ListenableBuilder(
              listenable: controller,
              builder: (context, _) => ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: _PlaylistCover(playlist: playlist)),
                    const SizedBox(height: 16),
                    Text(
                      playlist.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      playlist.visibility == PlaylistVisibility.private
                          ? 'Playlist privada'
                          : 'Playlist pública',
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${playlist.trackCount} ${playlist.trackCount == 1 ? 'canción' : 'canciones'}'
                      '${knownDuration ? ' · ${seconds ~/ 3600} h ${(seconds % 3600) ~/ 60} min' : ''}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: tracks.isEmpty
                                ? null
                                : () => playTracksAndOpenPlayer(
                                    context,
                                    ref,
                                    tracks,
                                  ),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(
                              tracks.length > 100
                                  ? 'Reproducir 100'
                                  : 'Reproducir',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Reproducción aleatoria',
                          onPressed: tracks.isEmpty
                              ? null
                              : () => playTracksAndOpenPlayer(
                                  context,
                                  ref,
                                  tracks.toList()..shuffle(),
                                ),
                          icon: const Icon(Icons.shuffle),
                        ),
                      ],
                    ),
                    if (playlist.description != null) ...[
                      const SizedBox(height: 16),
                      Text(playlist.description!),
                    ],
                    if (playlist.ownedByCurrentUser)
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: action.isLoading
                                ? null
                                : () => editPlaylist(context, ref, playlist),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Editar'),
                          ),
                          TextButton.icon(
                            onPressed: action.isLoading
                                ? null
                                : () => _delete(context, ref, playlist),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Eliminar'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (tracks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Esta playlist está vacía. Añade canciones desde su detalle.',
                        ),
                      ),
                  ],
                ),
                buildDefaultDragHandles: false,
                itemCount: playlist.tracks.length,
                onReorderItem: playlist.ownedByCurrentUser && !action.isLoading
                    ? (oldIndex, newIndex) =>
                          _reorder(context, ref, playlist, oldIndex, newIndex)
                    : (_, _) {},
                itemBuilder: (context, index) {
                  final item = playlist.tracks[index];
                  final current = controller.current?.id == item.track.id;
                  return ListTile(
                    key: ValueKey(item.id),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    selected: current,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                    onTap: () => playAndOpenPlayer(context, ref, item.track),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.track.durationLabel != null)
                          Text(
                            item.track.durationLabel!,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        if (playlist.ownedByCurrentUser) ...[
                          IconButton(
                            tooltip: 'Quitar de la playlist',
                            onPressed: action.isLoading
                                ? null
                                : () => _remove(context, ref, item.id),
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 20,
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle, size: 20),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar playlist'),
        content: Text(
          '¿Eliminar “${playlist.name}”? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final success = await ref.read(playlistActionsProvider.notifier).delete(id);
    if (!context.mounted) return;
    if (success) {
      context.pop();
    } else {
      _message(
        context,
        playlistErrorText(
          ref.read(playlistActionsProvider).error ?? Exception(),
        ),
      );
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    String itemId,
  ) async {
    final success = await ref
        .read(playlistActionsProvider.notifier)
        .removeTrack(id, itemId);
    if (!success && context.mounted) {
      _message(
        context,
        playlistErrorText(
          ref.read(playlistActionsProvider).error ?? Exception(),
        ),
      );
    }
  }

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail playlist,
    int oldIndex,
    int newIndex,
  ) async {
    final ids = playlist.tracks.map((item) => item.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    final success = await ref
        .read(playlistActionsProvider.notifier)
        .reorder(id, ids);
    if (!success && context.mounted) {
      _message(
        context,
        playlistErrorText(
          ref.read(playlistActionsProvider).error ?? Exception(),
        ),
      );
    }
  }
}

class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.playlist});
  final PlaylistDetail playlist;

  @override
  Widget build(BuildContext context) {
    final tracks = playlist.tracks;
    if (tracks.length < 4) {
      return TrackArtwork(
        url: tracks.isEmpty ? null : tracks.first.track.thumbnailUrl,
        size: 196,
        borderRadius: 24,
        fallbackIcon: Icons.queue_music,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        width: 196,
        height: 196,
        child: Wrap(
          children: [
            for (final item in tracks.take(4))
              TrackArtwork(
                url: item.track.thumbnailUrl,
                size: 98,
                borderRadius: 0,
              ),
          ],
        ),
      ),
    );
  }
}
