import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../connected_library/presentation/connected_screen.dart';
import '../../connected_library/presentation/music_mode_host.dart';
import '../../favorites/application/favorite_providers.dart';
import '../../playlists/application/playlist_providers.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, required this.accountAction});

  final Widget accountAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).asData?.value.length;
    final playlists = ref.watch(playlistsProvider).asData?.value.length;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca'), actions: [accountAction]),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            ListTile(
              leading: Icon(
                Icons.favorite_border_rounded,
                color: colors.primary,
              ),
              title: const Text('Favoritos'),
              subtitle: favorites == null
                  ? null
                  : Text(
                      '$favorites ${favorites == 1 ? 'canción' : 'canciones'}',
                    ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/favorites'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.queue_music_rounded, color: colors.primary),
              title: const Text('Playlists'),
              subtitle: playlists == null
                  ? null
                  : Text(
                      '$playlists ${playlists == 1 ? 'playlist' : 'playlists'}',
                    ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/playlists'),
            ),
            const Divider(height: 1),
            if (MusicModeScope.of(context) == null)
              const ConnectedTile()
            else
              ListTile(
                leading: const Icon(Icons.headphones),
                title: const Text('YouTube Music'),
                onTap: () => context.push('/account'),
              ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.download_outlined),
              title: Text('Descargas'),
              subtitle: Text('Próximamente'),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }
}
