import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/playlist_providers.dart';
import 'playlist_form_dialog.dart';
import 'playlists_screen.dart';

class AddToPlaylistButton extends ConsumerWidget {
  const AddToPlaylistButton({super.key, required this.trackId});
  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _PlaylistPicker(trackId: trackId),
    ),
    icon: const Icon(Icons.playlist_add),
    label: const Text('Añadir a playlist'),
  );
}

class _PlaylistPicker extends ConsumerWidget {
  const _PlaylistPicker({required this.trackId});
  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final action = ref.watch(playlistActionsProvider);
    return SafeArea(
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Crear nueva playlist'),
              enabled: !action.isLoading,
              onTap: () async {
                final form = await showPlaylistFormDialog(context);
                if (form == null || !context.mounted) return;
                final created = await ref
                    .read(playlistActionsProvider.notifier)
                    .create(
                      name: form.name,
                      description: form.description,
                      visibility: form.visibility,
                    );
                if (created == null || !context.mounted) return;
                final added = await ref
                    .read(playlistActionsProvider.notifier)
                    .addTrack(created.id, trackId);
                if (added && context.mounted) Navigator.pop(context);
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: playlists.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    Center(child: Text(playlistErrorText(error))),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('No tienes playlists todavía.'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            leading: const Icon(Icons.queue_music),
                            title: Text(item.name),
                            subtitle: Text('${item.trackCount} canciones'),
                            enabled: !action.isLoading,
                            onTap: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(context);
                              final added = await ref
                                  .read(playlistActionsProvider.notifier)
                                  .addTrack(item.id, trackId);
                              if (!context.mounted) return;
                              if (added) {
                                navigator.pop();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Añadida a ${item.name}'),
                                  ),
                                );
                              } else {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      playlistErrorText(
                                        ref
                                                .read(playlistActionsProvider)
                                                .error ??
                                            Exception(),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
