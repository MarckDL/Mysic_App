import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.accountAction});

  final Widget accountAction;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tu biblioteca'),
      actions: [accountAction],
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: const [
          _LibraryLink(
            title: 'Playlists',
            icon: Icons.queue_music_rounded,
            path: '/playlists',
          ),
          _LibraryLink(
            title: 'Favoritos',
            icon: Icons.favorite_outline,
            path: '/favorites',
          ),
          _LibraryLink(
            title: 'Historial',
            icon: Icons.history,
            path: '/history',
          ),
        ],
      ),
    ),
  );
}

class _LibraryLink extends StatelessWidget {
  const _LibraryLink({
    required this.title,
    required this.icon,
    required this.path,
  });

  final String title;
  final IconData icon;
  final String path;

  @override
  Widget build(BuildContext context) => Card.filled(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(path),
    ),
  );
}
