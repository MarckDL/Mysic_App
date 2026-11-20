import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/playlist_providers.dart';
import '../domain/playlist.dart';
import 'playlist_form_dialog.dart';

String playlistErrorText(Object error) => error is ApiFailure
    ? error.message
    : 'No se pudo completar la operación. Inténtalo de nuevo.';

Future<void> editPlaylist(
  BuildContext context,
  WidgetRef ref,
  PlaylistSummary playlist,
) async {
  final form = await showPlaylistFormDialog(context, initial: playlist);
  if (form == null || !context.mounted) return;
  final success = await ref
      .read(playlistActionsProvider.notifier)
      .update(
        playlist.id,
        name: form.name,
        description: form.description,
        visibility: form.visibility,
      );
  if (!success && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          playlistErrorText(
            ref.read(playlistActionsProvider).error ?? Exception(),
          ),
        ),
      ),
    );
  }
}

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final action = ref.watch(playlistActionsProvider);
    final playlists = ref.watch(playlistsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: action.isLoading
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                final form = await showPlaylistFormDialog(context);
                if (form == null || !context.mounted) return;
                final created = await ref
                    .read(playlistActionsProvider.notifier)
                    .create(
                      name: form.name,
                      description: form.description,
                      visibility: form.visibility,
                    );
                if (!context.mounted) return;
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
          data: (allItems) {
            final items = allItems
                .where(
                  (item) =>
                      item.name.toLowerCase().contains(_query.toLowerCase()),
                )
                .toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Buscar playlist',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              allItems.isEmpty
                                  ? 'Todavía no tienes playlists. Crea una para guardar canciones.'
                                  : 'No se encontraron playlists.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () =>
                              ref.refresh(playlistsProvider.future),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                            itemCount: items.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: TrackArtwork(
                                  url: item.thumbnailUrl,
                                  size: 76,
                                  borderRadius: 12,
                                  fallbackIcon: Icons.queue_music_rounded,
                                ),
                                title: Text(item.name),
                                subtitle: Text(
                                  '${item.trackCount} ${item.trackCount == 1 ? 'canción' : 'canciones'} · '
                                  '${item.visibility == PlaylistVisibility.private ? 'Privada' : 'Pública'}',
                                ),
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Opciones de playlist',
                                  icon: const Icon(Icons.more_horiz),
                                  enabled: !action.isLoading,
                                  onSelected: (_) =>
                                      editPlaylist(context, ref, item),
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Editar playlist'),
                                    ),
                                  ],
                                ),
                                onTap: () =>
                                    context.push('/playlists/${item.id}'),
                              );
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
