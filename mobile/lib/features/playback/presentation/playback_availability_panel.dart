import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/playback_providers.dart';
import '../domain/track_audio_engine.dart';
import '../../search/domain/catalog_track.dart';

class PlaybackAvailabilityPanel extends ConsumerWidget {
  const PlaybackAvailabilityPanel({super.key, required this.track});
  final CatalogTrack track;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.current?.id == track.id;
        final phase = selected ? controller.phase : TrackAudioPhase.idle;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton.icon(
              onPressed: phase == TrackAudioPhase.loading
                  ? null
                  : () {
                      if (phase == TrackAudioPhase.playing) {
                        unawaited(controller.pause());
                      } else if (phase == TrackAudioPhase.paused) {
                        unawaited(controller.resume());
                      } else {
                        unawaited(controller.playTrack(track));
                      }
                    },
              icon: Icon(
                phase == TrackAudioPhase.playing
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              label: Text(
                phase == TrackAudioPhase.playing
                    ? 'Pausar'
                    : phase == TrackAudioPhase.paused
                    ? 'Continuar'
                    : 'Reproducir audio',
              ),
            ),
            TextButton.icon(
              onPressed:
                  controller.queue.length >= 100 ||
                      controller.queue.any((item) => item.id == track.id)
                  ? null
                  : () => controller.enqueue(track),
              icon: const Icon(Icons.queue_music),
              label: const Text('Añadir a la cola'),
            ),
            if (phase == TrackAudioPhase.loading)
              const LinearProgressIndicator(),
            if (selected && phase != TrackAudioPhase.idle)
              TextButton(
                onPressed: () => unawaited(controller.stop()),
                child: const Text('Detener'),
              ),
            if (phase == TrackAudioPhase.error)
              const Text(
                'No se pudo reproducir esta pista. Puedes reintentar o elegir otra.',
              ),
            const Text(
              'El audio continúa al navegar o bloquear la pantalla. Puedes controlarlo desde el mini reproductor.',
            ),
          ],
        );
      },
    );
  }
}
