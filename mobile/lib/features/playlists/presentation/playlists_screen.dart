import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../application/playlist_providers.dart';
import '../domain/playlist.dart';
import 'playlist_form_dialog.dart';

String playlistErrorText(Object error) => error is ApiFailure
    ? error.message
    : 'No se pudo completar la operación. Inténtalo de nuevo.';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(playlistActionsProvider);
    final playlists = ref.watch(playlistsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mis playlists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: action.isLoading
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                final form = await showPlaylistFormDialog(context);
                if (form == null) return;
                final created = await ref
                    .read(playlistActionsProvider.notifier)
                    .create(
                      name: form.name,
                      description: form.description,
                      visibility: form.visibility,
                    );
                if (created != null) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Playlist “${created.name}” creada'),
                    ),
                  );
                } else {
                  final error = ref.read(playlistActionsProvider).error;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(playlistErrorText(error ?? Exception())),
                    ),
                  );
                }
              },
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: SafeArea(
        child: playlists.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(playlistErrorText(error)),
                TextButton(
                  onPressed: () => ref.invalidate(playlistsProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
          data: (items) => items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Todavía no tienes playlists. Crea una para guardar canciones.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(playlistsProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.queue_music),
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.trackCount} ${item.trackCount == 1 ? 'canción' : 'canciones'} · '
                          '${item.visibility == PlaylistVisibility.private ? 'Privada' : 'Pública'}',
                        ),
                        trailing: Icon(
                          item.visibility == PlaylistVisibility.private
                              ? Icons.lock_outline
                              : Icons.public,
                        ),
                        onTap: () => context.push('/playlists/${item.id}'),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
