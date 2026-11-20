import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../search/presentation/catalog_widgets.dart';
import '../data/music_discovery.dart';
import '../domain/music_mode.dart';
import 'music_mode_host.dart';
import 'play_discovery_queue.dart';

class CommunityPlaylistRail extends StatelessWidget {
  const CommunityPlaylistRail({
    super.key,
    required this.playlists,
    required this.open,
  });
  final List<MusicPlaylist> playlists;
  final ValueChanged<MusicItem> open;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final height = 88 + math.max(52.0, scale.scale(18) * 2 + 16) * 3;
    return LayoutBuilder(
      builder: (context, bounds) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: playlists.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, index) => SizedBox(
            width: math.min(336, bounds.maxWidth * .92),
            child: _CommunityCard(playlist: playlists[index], open: open),
          ),
        ),
      ),
    );
  }
}

class _CommunityCard extends ConsumerWidget {
  const _CommunityCard({required this.playlist, required this.open});
  final MusicPlaylist playlist;
  final ValueChanged<MusicItem> open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = discoveryPageProvider((
      path: 'playlist/${playlist.id}',
      query: null,
      filter: null,
    ));
    final generation = MusicModeScope.of(context)?.connection?.generation;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: TrackArtwork(
              url: playlist.thumbnailUrl,
              size: 48,
              fallbackIcon: Icons.queue_music,
            ),
            title: Text(
              playlist.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(playlist),
          ),
          const Divider(height: 1),
          Expanded(
            child: ref
                .watch(provider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  error: (_, _) => Center(
                    child: TextButton(
                      onPressed: () => ref.invalidate(provider),
                      child: const Text('Reintentar vista previa'),
                    ),
                  ),
                  data: (page) {
                    final queue = page.items
                        .whereType<MusicTrack>()
                        .where((track) => track.canPlayInMysic)
                        .toList();
                    if (queue.isEmpty) {
                      return const Center(
                        child: Text('Sin pistas disponibles'),
                      );
                    }
                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final track in queue.take(3))
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: TrackArtwork(
                              url: track.thumbnailUrl,
                              size: 36,
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            onTap: () => playDiscoveryQueue(
                              context,
                              ref,
                              queue,
                              track,
                              generation,
                            ),
                          ),
                      ],
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
