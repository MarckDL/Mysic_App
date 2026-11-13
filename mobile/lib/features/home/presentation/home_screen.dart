import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/domain/mysic_profile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.profile});
  final MysicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Mysic'),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Abrir perfil',
          onPressed: () => context.go('/profile'),
          icon: const Icon(Icons.account_circle),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Hola, ${profile.displayName} 👋',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text('¿Qué escuchamos hoy?'),
          const SizedBox(height: 24),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => context.go('/search'),
            child: const IgnorePointer(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Canciones o artistas…',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text('Tu biblioteca', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HomeCard(
                  icon: Icons.queue_music,
                  title: 'Playlists',
                  onTap: () => context.push('/playlists'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HomeCard(
                  icon: Icons.favorite,
                  title: 'Favoritos',
                  onTap: () => context.push('/favorites'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Card(
            child: ListTile(
              minTileHeight: 72,
              leading: const Icon(Icons.explore_outlined),
              title: const Text('Explora el catálogo'),
              subtitle: const Text('Busca música disponible en YouTube Music'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/search'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ),
  );
}
