import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../favorites/application/favorite_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../../search/domain/catalog_track.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/playback_providers.dart';
import '../application/track_playback_controller.dart';
import '../domain/track_audio_engine.dart';
import 'player_widgets.dart';
import 'waveform_timeline.dart';

const _playerBackground = Color(0xFF15131B);
const _playerSurface = Color(0xFF282431);
const _playerAccent = Color(0xFFC6A5FF);

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    final appTheme = Theme.of(context);
    final theme = ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: _playerAccent,
        onPrimary: Color(0xFF221336),
        secondaryContainer: _playerSurface,
        onSecondaryContainer: Color(0xFFF1E6FF),
        surface: _playerBackground,
        surfaceContainerHigh: _playerSurface,
        surfaceContainerHighest: _playerSurface,
        onSurface: Color(0xFFF8F3FF),
        onSurfaceVariant: Color(0xFFC9BFDA),
      ),
    );
    return Theme(
      data: theme,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final track = controller.current;
          return Scaffold(
            backgroundColor: _playerBackground,
            appBar: AppBar(
              backgroundColor: _playerBackground,
              centerTitle: true,
              title: const Text('Reproductor'),
              actions: [
                if (track != null)
                  PopupMenuButton<String>(
                    tooltip: 'Opciones de la canción',
                    onSelected: (value) {
                      if (value == 'details') {
                        context.push(
                          '/tracks/${Uri.encodeComponent(track.id)}',
                        );
                      } else {
                        unawaited(controller.stop());
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'details',
                        child: Text('Detalles de la canción'),
                      ),
                      PopupMenuItem(
                        value: 'stop',
                        child: Text('Detener reproducción'),
                      ),
                    ],
                  ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                    children: [
                      if (track != null)
                        _NowPlaying(track: track, controller: controller)
                      else
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            'Elige una canción para empezar',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 24),
                      Align(
                        child: FilledButton.tonalIcon(
                          onPressed: controller.queue.isEmpty
                              ? null
                              : () {
                                  showModalBottomSheet<void>(
                                    context: context,
                                    useSafeArea: true,
                                    isScrollControlled: true,
                                    constraints: BoxConstraints(
                                      maxHeight:
                                          MediaQuery.sizeOf(context).height *
                                          0.72,
                                    ),
                                    backgroundColor:
                                        appTheme.colorScheme.surface,
                                    showDragHandle: true,
                                    builder: (context) => Theme(
                                      data: appTheme,
                                      child: _QueueSheet(
                                        controller: controller,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.queue_music_rounded),
                          label: Text('Cola (${controller.queue.length}/100)'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NowPlaying extends ConsumerWidget {
  const _NowPlaying({required this.track, required this.controller});

  final CatalogTrack track;
  final TrackPlaybackController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final duration = controller.duration;
    final playing = controller.phase == TrackAudioPhase.playing;
    final loading = controller.phase == TrackAudioPhase.loading;
    final interactions = ref
        .watch(trackInteractionsProvider(track.id))
        .asData
        ?.value;
    final favoriteAction = ref.watch(favoriteActionsProvider);
    final favorite = interactions?.isFavorite == true;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Align(
            child: TrackArtwork(
              url: track.thumbnailUrl,
              size: constraints.maxWidth.clamp(0, 360).toDouble(),
              borderRadius: 24,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artistName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: favorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
              icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
              color: _playerAccent,
              onPressed: interactions == null || favoriteAction.isLoading
                  ? null
                  : () async {
                      final updated = await ref
                          .read(favoriteActionsProvider.notifier)
                          .setFavorite(track.id, !favorite);
                      if (!updated && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No se pudo actualizar favoritos.'),
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
        const SizedBox(height: 12),
        WaveformTimeline(
          key: ValueKey(track.id),
          position: controller.position,
          duration: duration,
          onSeek: (value) => unawaited(controller.seek(value)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(audioTime(controller.position)),
            Text(
              duration == null
                  ? track.durationLabel ?? '—'
                  : audioTime(duration),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: 'Anterior',
              iconSize: 30,
              onPressed: controller.hasPrevious
                  ? () => unawaited(controller.previous())
                  : null,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton.filled(
              tooltip: playing ? 'Pausar' : 'Reproducir',
              style: IconButton.styleFrom(minimumSize: const Size.square(68)),
              iconSize: 34,
              onPressed: loading
                  ? null
                  : () => unawaited(
                      playing ? controller.pause() : controller.resume(),
                    ),
              icon: loading
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
            ),
            IconButton(
              tooltip: 'Siguiente',
              iconSize: 30,
              onPressed: controller.hasNext
                  ? () => unawaited(controller.next())
                  : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
        if (controller.phase == TrackAudioPhase.error)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Esta pista no se pudo reproducir. Reintenta o elige otra.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet({required this.controller});

  final TrackPlaybackController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final queue = controller.queue;
      final theme = Theme.of(context);
      return SafeArea(
        top: false,
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(
                'Cola de reproducción',
                style: theme.textTheme.titleLarge,
              ),
              subtitle: Text(
                '${queue.length} ${queue.length == 1 ? 'canción' : 'canciones'}',
              ),
              trailing: TextButton(
                onPressed: queue.isEmpty
                    ? null
                    : () => unawaited(controller.clear()),
                child: const Text('Vaciar'),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: queue.isEmpty
                  ? const Center(child: Text('La cola está vacía'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      itemCount: queue.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final track = queue[index];
                        final current = index == controller.index;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          selected: current,
                          selectedTileColor:
                              theme.colorScheme.secondaryContainer,
                          leading: TrackArtwork(
                            url: track.thumbnailUrl,
                            size: 48,
                          ),
                          title: Text(
                            track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (current) 'En reproducción',
                              track.artistName,
                              ?track.durationLabel,
                            ].join(' · '),
                          ),
                          onTap: current
                              ? null
                              : () => unawaited(controller.jump(index)),
                          trailing: current
                              ? Icon(
                                  Icons.equalizer,
                                  color: theme.colorScheme.primary,
                                )
                              : IconButton(
                                  tooltip: 'Quitar de la cola',
                                  onPressed: () => controller.remove(index),
                                  icon: const Icon(Icons.close),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
