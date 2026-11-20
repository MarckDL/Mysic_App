import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../favorites/application/favorite_providers.dart';
import '../../search/domain/catalog_track.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/track_playback_controller.dart';
import '../domain/track_audio_engine.dart';

class PlayerQueueSheet extends ConsumerStatefulWidget {
  const PlayerQueueSheet({
    super.key,
    required this.controller,
    this.openMusicLikes,
  });

  final TrackPlaybackController controller;
  final VoidCallback? openMusicLikes;

  @override
  ConsumerState<PlayerQueueSheet> createState() => _PlayerQueueSheetState();
}

class _PlayerQueueSheetState extends ConsumerState<PlayerQueueSheet> {
  var _tab = 0;
  late List<CatalogTrack> _queue;
  late int _index;
  late TrackAudioPhase _phase;

  TrackPlaybackController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _queue = _controller.queue;
    _index = _controller.index;
    _phase = _controller.phase;
    _controller.addListener(_update);
  }

  void _update() {
    final queue = _controller.queue;
    final index = _controller.index;
    final phase = _controller.phase;
    if (_index == index && _phase == phase && listEquals(_queue, queue)) return;
    setState(() {
      _queue = queue;
      _index = index;
      _phase = phase;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .66,
      minChildSize: .32,
      maxChildSize: 1,
      snap: true,
      snapSizes: const [.66],
      builder: (context, scrollController) => DefaultTabController(
        length: 3,
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Container(
                      height: 4,
                      width: 36,
                      decoration: BoxDecoration(
                        color: colors.onSurfaceVariant.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    onTap: (tab) {
                      if (scrollController.hasClients) {
                        scrollController.jumpTo(0);
                      }
                      setState(() => _tab = tab);
                    },
                    tabs: [
                      const Tab(text: 'Cola'),
                      const Tab(text: 'Artistas'),
                      Tab(
                        text: widget.openMusicLikes == null
                            ? 'Favoritos'
                            : 'Me gusta',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                12,
                10,
                12,
                MediaQuery.viewPaddingOf(context).bottom + 12,
              ),
              sliver: switch (_tab) {
                0 => _queueList(),
                1 => _artists(),
                _ =>
                  widget.openMusicLikes == null
                      ? _favorites()
                      : _message(
                          TextButton(
                            onPressed: widget.openMusicLikes,
                            child: const Text(
                              'Ver mis Me gusta de YouTube Music',
                            ),
                          ),
                        ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _queueList() {
    if (_queue.isEmpty) return _message(const Text('La cola está vacía'));
    return SliverList.builder(
      itemCount: _queue.length + 1,
      itemBuilder: (context, index) {
        if (index == _queue.length) {
          return TextButton(
            onPressed: () => unawaited(_controller.clear()),
            child: const Text('Vaciar cola'),
          );
        }
        return _queuedTrack(index, allowRemoval: true);
      },
    );
  }

  Widget _artists() {
    if (_queue.isEmpty) return _message(const Text('La cola está vacía'));
    final groups = <String, List<int>>{};
    for (final (index, track) in _queue.indexed) {
      groups.putIfAbsent(track.artistName, () => []).add(index);
    }
    final artists = groups.entries.toList(growable: false);
    return SliverList.builder(
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        final count = artist.value.length;
        return ExpansionTile(
          key: PageStorageKey(artist.key),
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(artist.key),
          subtitle: Text(count == 1 ? '1 canción' : '$count canciones'),
          children: [for (final index in artist.value) _queuedTrack(index)],
        );
      },
    );
  }

  Widget _favorites() => ref
      .watch(favoritesProvider)
      .when(
        loading: () => _message(const CircularProgressIndicator()),
        error: (_, _) => _message(
          TextButton(
            onPressed: () => ref.invalidate(favoritesProvider),
            child: const Text('Reintentar favoritos'),
          ),
        ),
        data: (items) => items.isEmpty
            ? _message(const Text('Aún no tienes favoritos'))
            : SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final track = items[index].track;
                  final current = _controller.current?.id == track.id;
                  return _QueueTrackTile(
                    track: track,
                    phase: current ? _phase : null,
                    onTap: current
                        ? null
                        : () => unawaited(_controller.playTrack(track)),
                  );
                },
              ),
      );

  Widget _queuedTrack(int index, {bool allowRemoval = false}) {
    final current = _index == index;
    return _QueueTrackTile(
      track: _queue[index],
      phase: current ? _phase : null,
      onTap: current ? null : () => unawaited(_controller.jump(index)),
      onRemove: allowRemoval && !current
          ? () => _controller.remove(index)
          : null,
    );
  }

  Widget _message(Widget content) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Center(child: content),
    ),
  );
}

class _QueueTrackTile extends StatelessWidget {
  const _QueueTrackTile({
    required this.track,
    this.phase,
    this.onTap,
    this.onRemove,
  });

  final CatalogTrack track;
  final TrackAudioPhase? phase;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = switch (phase) {
      TrackAudioPhase.playing => (Icons.equalizer_rounded, 'Reproduciendo'),
      TrackAudioPhase.loading => (Icons.hourglass_top_rounded, 'Cargando'),
      TrackAudioPhase.paused => (Icons.pause_circle_outline, 'En pausa'),
      TrackAudioPhase.error => (Icons.error_outline, 'Error de reproducción'),
      _ => (Icons.music_note_rounded, 'Pista actual'),
    };
    final selected = phase != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        selected: selected,
        selectedTileColor: colors.primary.withValues(alpha: .13),
        leading: TrackArtwork(url: track.thumbnailUrl, size: 44),
        title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            track.artistName,
            if (track.durationLabel case final duration?) duration,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
        trailing: selected
            ? Tooltip(
                message: status.$2,
                child: Icon(status.$1, color: colors.primary),
              )
            : onRemove == null
            ? null
            : IconButton(
                tooltip: 'Quitar de la cola',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
      ),
    );
  }
}
