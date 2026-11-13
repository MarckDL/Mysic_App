import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../favorites/application/favorite_providers.dart';
import '../../playlists/application/playlist_providers.dart';
import '../../youtube_library/application/youtube_library_providers.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistCount = ref.watch(playlistsProvider).asData?.value.length;
    final favoriteCount = ref.watch(favoritesProvider).asData?.value.length;
    final youtube = ref.watch(youtubeConnectionStatusProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Tu música guardada en Mysic.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            _LibraryTile(
              icon: Icons.favorite_border,
              title: 'Favoritos',
              subtitle: _count(favoriteCount, 'canción', 'canciones'),
              onTap: () => context.push('/favorites'),
            ),
            const Divider(),
            _LibraryTile(
              icon: Icons.queue_music,
              title: 'Playlists',
              subtitle: _count(playlistCount, 'playlist', 'playlists'),
              onTap: () => context.push('/playlists'),
            ),
            if (youtube?.connected == true) ...[
              const Divider(),
              _LibraryTile(
                icon: Icons.play_circle_outline,
                title: 'YouTube',
                subtitle:
                    '${youtube!.playlistCount} playlists · ${youtube.likedTrackCount} Me gusta · solo lectura',
                onTap: () => context.push('/youtube-library'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _count(int? value, String singular, String plural) =>
      value == null ? 'Cargando…' : '$value ${value == 1 ? singular : plural}';
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 68,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
