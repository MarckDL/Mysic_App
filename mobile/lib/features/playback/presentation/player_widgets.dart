import 'dart:async';
import 'package:flutter/material.dart';
import '../application/track_playback_controller.dart';
import '../domain/track_audio_engine.dart';
import '../../search/presentation/catalog_widgets.dart';

String audioTime(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key, required this.controller});
  final TrackPlaybackController controller;
  @override
  Widget build(BuildContext context) {
    final busy = controller.phase == TrackAudioPhase.loading;
    final playing = controller.phase == TrackAudioPhase.playing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Anterior',
          onPressed: controller.hasPrevious
              ? () => unawaited(controller.previous())
              : null,
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
          tooltip: playing ? 'Pausar' : 'Reproducir',
          onPressed: busy
              ? null
              : () => unawaited(
                  playing ? controller.pause() : controller.resume(),
                ),
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Siguiente',
          onPressed: controller.hasNext
              ? () => unawaited(controller.next())
              : null,
          icon: const Icon(Icons.skip_next),
        ),
        IconButton(
          tooltip: 'Detener',
          onPressed: () => unawaited(controller.stop()),
          icon: const Icon(Icons.stop),
        ),
      ],
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller, required this.open});
  final TrackPlaybackController controller;
  final VoidCallback open;
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
      final playing = controller.phase == TrackAudioPhase.playing;
      return Material(
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.phase == TrackAudioPhase.loading)
                const LinearProgressIndicator(minHeight: 2),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: open,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            TrackArtwork(url: current.thumbnailUrl, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    current.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    current.artistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: playing ? 'Pausar audio' : 'Continuar audio',
                    onPressed: controller.phase == TrackAudioPhase.loading
                        ? null
                        : () => unawaited(
                            playing ? controller.pause() : controller.resume(),
                          ),
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    tooltip: 'Siguiente pista',
                    onPressed: controller.hasNext
                        ? () => unawaited(controller.next())
                        : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                  IconButton(
                    tooltip: 'Abrir reproductor',
                    onPressed: open,
                    icon: const Icon(Icons.expand_less),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
