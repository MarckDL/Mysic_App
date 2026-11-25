import 'dart:async';
import 'package:flutter/material.dart';
import '../application/track_playback_controller.dart';
import '../domain/track_audio_engine.dart';
import 'artwork_prefetch.dart';
import 'live_cover.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../../ytm/data/liked_tracks.dart';

String audioTime(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.controller,
    required this.open,
    this.likes,
  });
  final TrackPlaybackController controller;
  final VoidCallback open;

  /// Los Me gusta de la cuenta, para el corazón; sin ellos no se pinta.
  final LikedTracks? likes;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final current = controller.current;
      if (current == null) {
        if (controller.queue.isEmpty) return const SizedBox.shrink();
        return Material(
          child: SafeArea(
            top: false,
            bottom: false,
            child: ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text('Cola (${controller.queue.length})'),
              subtitle: const Text('Elige una canción para empezar'),
              onTap: open,
              trailing: IconButton(
                tooltip: 'Abrir reproductor',
                onPressed: open,
                icon: const Icon(Icons.expand_less),
              ),
            ),
          ),
        );
      }
      // Las portadas de alrededor de la que suena se precargan ya, para que
      // al abrir el reproductor (y al deslizar en él) no se vean cargar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ArtworkPrefetch.around(context, controller);
      });
      final playing = controller.phase == TrackAudioPhase.playing;
      final loading = controller.phase == TrackAudioPhase.loading;
      final theme = Theme.of(context), colors = theme.colorScheme;
      final length = controller.duration?.inMilliseconds ?? 0;
      // Tarjeta separada sobre las pestañas, como el mini reproductor de
      // Limusic: deslizar a los lados cambia de pista y hacia arriba lo abre.
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -250) open();
          },
          onHorizontalDragEnd: (details) {
            final speed = details.primaryVelocity ?? 0;
            if (speed < -350 && controller.hasNext) {
              unawaited(controller.next());
            } else if (speed > 350 && controller.hasPrevious) {
              unawaited(controller.previous());
            }
          },
          child: Material(
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            color: colors.surfaceContainerHigh,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: open,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                          child: Row(
                            children: [
                              if (current.isLive &&
                                  controller.liveArtwork != null)
                                TrackArtwork(
                                  url: controller.liveArtwork,
                                  size: 42,
                                  borderRadius: 6,
                                )
                              else if (current.isLive)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LiveCover(
                                    size: 42,
                                    colors: current.liveColors,
                                    logo: current.liveLogo,
                                  ),
                                )
                              else
                                TrackArtwork(
                                  url: current.thumbnailUrl,
                                  size: 42,
                                  borderRadius: 6,
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      current.isLive
                                          ? controller.liveTitle ??
                                                current.title
                                          : current.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    Text(
                                      current.isLive &&
                                              controller.liveTitle != null
                                          ? controller.liveArtist ??
                                                current.title
                                          : current.artistName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // El corazón de la canción que suena (Limusic lo lleva
                    // aquí, antes de reproducir).
                    if (likes != null && current.id.startsWith('youtube:'))
                      ListenableBuilder(
                        listenable: likes!,
                        builder: (context, _) {
                          final id = current.id.substring(8);
                          final liked = likes!.isLiked(id);
                          return IconButton(
                            tooltip: liked ? 'Quitar Me gusta' : 'Me gusta',
                            iconSize: 22,
                            color: liked ? colors.primary : colors.onSurface,
                            icon: Icon(
                              liked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                            ),
                            onPressed: () => unawaited(likes!.toggle(id)),
                          );
                        },
                      ),
                    IconButton.filled(
                      tooltip: current.isLive
                          ? (playing ? 'Detener radio' : 'Sintonizar radio')
                          : playing
                          ? 'Pausar audio'
                          : 'Continuar audio',
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(38),
                        maximumSize: const Size.square(38),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      iconSize: 22,
                      onPressed: loading
                          ? null
                          : () => unawaited(
                              playing
                                  ? controller.pause()
                                  : controller.resume(),
                            ),
                      icon: loading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              // Una radio se detiene (como en la web), no se
                              // pausa.
                              playing
                                  ? (current.isLive
                                        ? Icons.stop_rounded
                                        : Icons.pause_rounded)
                                  : Icons.play_arrow_rounded,
                            ),
                    ),
                    // Una radio en directo no tiene «siguiente».
                    if (!current.isLive)
                      IconButton(
                        tooltip: 'Siguiente pista',
                        onPressed: controller.hasNext
                            ? () => unawaited(controller.next())
                            : null,
                        icon: const Icon(Icons.skip_next_rounded),
                      )
                    else
                      const SizedBox(width: 8),
                    const SizedBox(width: 4),
                  ],
                ),
                // Avance de la pista en el borde inferior de la tarjeta.
                // Solo esta línea se redibuja con cada avance. Una radio en
                // directo no tiene avance que mostrar.
                if (!current.isLive)
                  ValueListenableBuilder<Duration>(
                    valueListenable: controller.positionListenable,
                    builder: (context, _, _) => LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: colors.onSurface.withValues(alpha: .12),
                      value: length > 0
                          ? (controller.position.inMilliseconds / length).clamp(
                              0.0,
                              1.0,
                            )
                          : 0,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
