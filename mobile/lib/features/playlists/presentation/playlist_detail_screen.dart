import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/playlist_providers.dart';
import '../domain/playlist.dart';
import 'playlist_form_dialog.dart';
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
          data: (playlist) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (playlist.description != null) ...[
                      const SizedBox(height: 6),
                      Text(playlist.description!),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${playlist.visibility == PlaylistVisibility.private ? 'Privada' : 'Pública'} · '
                      '${playlist.trackCount} ${playlist.trackCount == 1 ? 'canción' : 'canciones'}',
                    ),
                    if (playlist.ownedByCurrentUser) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: action.isLoading
                                ? null
                                : () => _edit(context, ref, playlist),
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
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: playlist.tracks.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Esta playlist está vacía. Añade canciones desde su detalle.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: playlist.tracks.length,
                        onReorderItem:
                            playlist.ownedByCurrentUser && !action.isLoading
                            ? (oldIndex, newIndex) => _reorder(
                                context,
                                ref,
                                playlist,
                                oldIndex,
                                newIndex,
                              )
                            : (_, _) {},
                        itemBuilder: (context, index) {
                          final item = playlist.tracks[index];
                          return ListTile(
                            key: ValueKey(item.id),
                            leading: TrackArtwork(url: item.track.thumbnailUrl),
                            title: Text(item.track.title),
                            subtitle: Text(item.track.artistName),
                            onTap: () => context.push(
                              '/tracks/${Uri.encodeComponent(item.track.id)}',
                            ),
                            trailing: playlist.ownedByCurrentUser
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Quitar de la playlist',
                                        onPressed: action.isLoading
                                            ? null
                                            : () => _remove(
                                                context,
                                                ref,
                                                item.id,
                                              ),
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                      ),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Icon(Icons.drag_handle),
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail playlist,
  ) async {
    final form = await showPlaylistFormDialog(context, initial: playlist);
    if (form == null || !context.mounted) return;
    final success = await ref
        .read(playlistActionsProvider.notifier)
        .update(
          id,
          name: form.name,
          description: form.description,
          visibility: form.visibility,
        );
    if (!success && context.mounted) {
      _message(
        context,
        playlistErrorText(
          ref.read(playlistActionsProvider).error ?? Exception(),
        ),
      );
    }
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
