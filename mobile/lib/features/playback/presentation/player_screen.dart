import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../favorites/application/favorite_providers.dart';
import '../../connected_library/presentation/music_mode_host.dart';
import '../../ratings/application/rating_providers.dart';
import '../../search/domain/catalog_track.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/playback_providers.dart';
import '../application/track_playback_controller.dart';
import '../domain/track_audio_engine.dart';
import 'playback_progress.dart';
import 'player_backdrop.dart';
import 'player_queue_sheet.dart';
import '../../lyrics/presentation/lyrics_sheet.dart';
import 'package:flutter/services.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final track = controller.current;
        final musicMode = MusicModeScope.of(context)?.showMusic == true;
        final ImageProvider<Object>? artwork = controller.isBundledTrack
            ? const AssetImage('assets/images/discover-mountains.webp')
            : switch (track?.thumbnailUrl) {
                final String url => NetworkImage(url),
                _ => null,
              };
        return PlayerBackdrop(
          artwork: artwork,
          builder: (context, theme, backdrop) => Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: theme.colorScheme.surface,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: theme.colorScheme.onSurface,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              centerTitle: true,
              title: const Text('Reproductor'),
              titleTextStyle: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
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
                    itemBuilder: (context) => [
                      if (!controller.isBundledTrack && !musicMode)
                        const PopupMenuItem(
                          value: 'details',
                          child: Text('Detalles de la canción'),
                        ),
                      const PopupMenuItem(
                        value: 'stop',
                        child: Text('Detener reproducción'),
                      ),
                    ],
                  ),
              ],
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: backdrop),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
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
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.spaceEvenly,
                            runSpacing: 8,
                            spacing: 12,
                            children: [
                              _PlayerShortcut(
                                icon: Icons.lyrics_outlined,
                                label: 'Letra',
                                onPressed:
                                    track == null || controller.isBundledTrack
                                    ? null
                                    : () => showModalBottomSheet<void>(
                                        context: context,
                                        isScrollControlled: true,
                                        useSafeArea: true,
                                        showDragHandle: true,
                                        constraints: BoxConstraints(
                                          maxHeight:
                                              MediaQuery.sizeOf(
                                                context,
                                              ).height *
                                              .76,
                                        ),
                                        backgroundColor:
                                            theme.colorScheme.surfaceContainer,
                                        builder: (_) => Theme(
                                          data: theme,
                                          child: LyricsSheet(
                                            controller: controller,
                                          ),
                                        ),
                                      ),
                              ),
                              _PlayerShortcut(
                                icon: Icons.queue_music_rounded,
                                label: 'Cola',
                                onPressed: controller.queue.isEmpty
                                    ? null
                                    : () => showModalBottomSheet<void>(
                                        context: context,
                                        useSafeArea: true,
                                        isScrollControlled: true,
                                        enableDrag: false,
                                        clipBehavior: Clip.antiAlias,
                                        constraints: BoxConstraints(
                                          maxHeight:
                                              MediaQuery.sizeOf(
                                                context,
                                              ).height *
                                              .91,
                                        ),
                                        backgroundColor:
                                            theme.colorScheme.surfaceContainer,
                                        builder: (sheetContext) => Theme(
                                          data: theme,
                                          child: PlayerQueueSheet(
                                            controller: controller,
                                            musicLikesLabel: MusicModeScope.of(
                                              context,
                                            )?.connection?.likesActionLabel,
                                            openMusicLikes: musicMode
                                                ? () {
                                                    Navigator.of(
                                                      sheetContext,
                                                    ).pop();
                                                    context.push(
                                                      '/music/liked',
                                                    );
                                                  }
                                                : null,
                                          ),
                                        ),
                                      ),
                              ),
                              _PlayerShortcut(
                                icon: Icons.devices_outlined,
                                label: 'Dispositivos',
                                onPressed: () async {
                                  try {
                                    await const MethodChannel(
                                      'com.mysic/audio_output',
                                    ).invokeMethod<void>('open');
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Configura la salida de audio desde los ajustes del dispositivo.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayerShortcut extends StatelessWidget {
  const _PlayerShortcut({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colors.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(15),
            ),
            child: SizedBox.square(dimension: 48, child: Icon(icon, size: 22)),
          ),
          const SizedBox(height: 5),
          Text(label, textAlign: TextAlign.center),
        ],
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
    final playing = controller.phase == TrackAudioPhase.playing;
    final loading = controller.phase == TrackAudioPhase.loading;
    final musicMode = MusicModeScope.of(context)?.showMusic == true;
    final interactions = controller.isBundledTrack || musicMode
        ? null
        : ref.watch(trackInteractionsProvider(track.id)).asData?.value;
    final favoriteAction = musicMode
        ? null
        : ref.watch(favoriteActionsProvider);
    final favorite = interactions?.isFavorite == true;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final height = MediaQuery.sizeOf(context).height;
            final size = constraints.maxWidth
                .clamp(0, (height * 0.40).clamp(150, 290))
                .toDouble();
            return Align(
              child: controller.isBundledTrack
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/images/discover-mountains.webp',
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                      ),
                    )
                  : TrackArtwork(
                      url: track.thumbnailUrl,
                      size: size,
                      borderRadius: 24,
                    ),
            );
          },
        ),
        const SizedBox(height: 20),
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
            if (musicMode)
              IconButton(
                tooltip: MusicModeScope.of(
                  context,
                )?.connection?.likesActionLabel,
                icon: const Icon(Icons.library_music_outlined),
                onPressed: () => context.push('/music/liked'),
              )
            else if (!controller.isBundledTrack)
              IconButton(
                tooltip: favorite
                    ? 'Quitar de favoritos'
                    : 'Añadir a favoritos',
                icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                color: theme.colorScheme.primary,
                onPressed: interactions == null || favoriteAction!.isLoading
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
        const SizedBox(height: 8),
        PlaybackProgress(key: ValueKey(track.id), controller: controller),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              IconButton(
                tooltip: 'Aleatorio',
                color: controller.shuffleEnabled
                    ? theme.colorScheme.primary
                    : null,
                onPressed: controller.queue.length < 2
                    ? null
                    : controller.toggleShuffle,
                icon: const Icon(Icons.shuffle),
              ),
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
                style: IconButton.styleFrom(minimumSize: const Size.square(58)),
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
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
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
              IconButton(
                tooltip: switch (controller.repeat) {
                  PlaybackRepeat.off => 'Repetir desactivado',
                  PlaybackRepeat.all => 'Repetir cola',
                  PlaybackRepeat.one => 'Repetir canción',
                },
                color: controller.repeat == PlaybackRepeat.off
                    ? null
                    : theme.colorScheme.primary,
                onPressed: controller.cycleRepeat,
                icon: Icon(
                  controller.repeat == PlaybackRepeat.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                ),
              ),
            ],
          ),
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
