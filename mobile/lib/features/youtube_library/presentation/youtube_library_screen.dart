import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/application/playback_providers.dart';
import '../application/youtube_library_providers.dart';

class YoutubeLibraryScreen extends ConsumerWidget {
  const YoutubeLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(youtubeLibraryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca de YouTube')),
      body: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                const Text('No se pudo cargar la biblioteca.'),
                TextButton(
                  onPressed: () => ref.invalidate(youtubeLibraryProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
        data: (library) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const _ReadOnlyNotice(),
            const SizedBox(height: 24),
            Text('Playlists', style: Theme.of(context).textTheme.titleLarge),
            if (library.playlists.isEmpty)
              const ListTile(title: Text('No hay playlists importadas.')),
            ...library.playlists.map(
              (playlist) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.playlist_play)),
                title: Text(playlist.title),
                subtitle: Text('${playlist.itemCount} canciones · YouTube'),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Opciones de playlist',
                  onSelected: (_) async {
                    final ok = await ref
                        .read(youtubeLibraryActionsProvider.notifier)
                        .duplicate(playlist.id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Playlist duplicada en Mysic.'
                              : 'No se pudo duplicar la playlist.',
                        ),
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Text('Duplicar en Mysic'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Me gusta en YouTube',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ...library.likes.map(
              (track) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: track.thumbnailUrl == null
                      ? const SizedBox.square(
                          dimension: 48,
                          child: ColoredBox(color: Color(0xFFEDE9F5)),
                        )
                      : Image.network(
                          track.thumbnailUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Reproducir',
                  onPressed: () => ref
                      .read(trackPlaybackControllerProvider)
                      .playTrack(track),
                  icon: const Icon(Icons.play_arrow),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Datos importados en modo de solo lectura. Mysic no guarda tu autorización de YouTube.',
            ),
          ),
        ],
      ),
    ),
  );
}
