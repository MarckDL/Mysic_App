import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../search/domain/catalog_track.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/track_playback_controller.dart';
import '../domain/track_audio_engine.dart';

class PlayerQueueSheet extends ConsumerStatefulWidget {
  const PlayerQueueSheet({
    super.key,
    required this.controller,
    this.embedded = false,
    this.openMusicLikes,
    this.musicLikesLabel,
  });

  final TrackPlaybackController controller;

  /// Va incrustada en el reproductor (sin tirador ni arrastre).
  final bool embedded;
  final VoidCallback? openMusicLikes;
  final String? musicLikesLabel;

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
    if (!mounted) return;
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
    // Dentro del reproductor la cola es una vista de la página, no una hoja
    // que se arrastra.
    if (widget.embedded) return _content(context, null);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .66,
      minChildSize: .32,
      maxChildSize: 1,
      snap: true,
      snapSizes: const [.66],
      builder: _content,
    );
  }

  Widget _content(BuildContext context, ScrollController? scrollController) {
    final colors = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                if (!widget.embedded)
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
                    if (scrollController?.hasClients ?? false) {
                      scrollController?.jumpTo(0);
                    }
                    setState(() => _tab = tab);
                  },
                  tabs: [
                    const Tab(text: 'Cola'),
                    const Tab(text: 'Artistas'),
                    const Tab(text: 'Me gusta'),
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
              _ => _message(
                TextButton(
                  onPressed: widget.openMusicLikes,
                  child: Text(
                    widget.musicLikesLabel ??
                        'Ver mis Me gusta de YouTube Music',
                  ),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }

  Widget _queueList() {
    if (_queue.isEmpty) return _message(const Text('La cola está vacía'));
    final colors = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final first = _index < 0 ? 0 : _index + 1;
    final upcoming = _queue.length - first;
    final past = _index < 0 ? 0 : _index;
    return SliverMainAxisGroup(
      slivers: [
        // Lo ya oído, plegado: se puede volver a cualquiera.
        if (past > 0)
          SliverToBoxAdapter(
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 10),
              title: Text(
                past == 1
                    ? '1 canción reproducida'
                    : '$past canciones reproducidas',
                style: label,
              ),
              children: [for (var i = 0; i < past; i++) _queuedTrack(i)],
            ),
          ),
        if (_index >= 0 && _index < _queue.length) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text('Reproduciendo ahora', style: label),
            ),
          ),
          SliverToBoxAdapter(child: _queuedTrack(_index)),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 0, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    upcoming == 0
                        ? 'A continuación'
                        : 'A continuación · $upcoming',
                    style: label,
                  ),
                ),
                if (_controller.hasRadio) ...[
                  if (_controller.loadingAutoplay)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Text('Autoplay', style: label),
                  Switch(
                    value: _controller.autoplay,
                    onChanged: _controller.setAutoplay,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (upcoming == 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Text(
                _controller.hasRadio && _controller.autoplay
                    ? 'Buscando canciones parecidas…'
                    : 'No hay más canciones en la cola.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          )
        else
          // Arrastrar una pista la reordena; lo que añadió la radio lleva su
          // marca y pasa a ser del usuario al moverlo entre sus canciones.
          SliverReorderableList(
            itemCount: upcoming,
            // onReorderItem ya descuenta la pista que se levantó.
            onReorderItem: (from, to) =>
                _controller.move(first + from, first + to),
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              elevation: 6,
              borderRadius: BorderRadius.circular(14),
              child: child,
            ),
            itemBuilder: (context, i) {
              final queueIndex = first + i;
              final track = _queue[queueIndex];
              return _QueueTrackTile(
                key: ValueKey('queue:${track.id}'),
                track: track,
                autoplay: _controller.isAutoplayTrack(track),
                dragIndex: i,
                onTap: () => unawaited(_controller.jump(queueIndex)),
                onRemove: () => _controller.remove(queueIndex),
              );
            },
          ),
        if (upcoming > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _controller.clearUpcoming,
                    child: const Text('Vaciar siguientes'),
                  ),
                  TextButton(
                    onPressed: () => unawaited(_controller.clear()),
                    child: const Text('Vaciar cola'),
                  ),
                ],
              ),
            ),
          ),
      ],
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
    super.key,
    required this.track,
    this.phase,
    this.onTap,
    this.onRemove,
    this.autoplay = false,
    this.dragIndex,
  });

  /// La añadió la radio, no el usuario.
  final bool autoplay;

  /// Posición en la lista reordenable; null si la fila no se arrastra.
  final int? dragIndex;

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
            if (autoplay) 'Radio',
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
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRemove != null)
                    IconButton(
                      tooltip: 'Quitar de la cola',
                      onPressed: onRemove,
                      icon: const Icon(Icons.close),
                    ),
                  if (dragIndex != null)
                    ReorderableDragStartListener(
                      index: dragIndex!,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_handle,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
