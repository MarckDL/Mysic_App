import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/playback_providers.dart';
import '../domain/track_audio_engine.dart';
import '../../search/presentation/catalog_widgets.dart';
import 'player_widgets.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Reproductor')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final track = controller.current;
            final duration = controller.duration;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (track != null) ...[
                  Center(
                    child: TrackArtwork(url: track.thumbnailUrl, size: 180),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    track.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(track.artistName),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: duration == null || duration.inMilliseconds <= 0
                        ? 0
                        : (controller.position.inMilliseconds /
                                  duration.inMilliseconds)
                              .clamp(0.0, 1.0),
                  ),
                  Text(
                    '${audioTime(controller.position)} / ${duration == null ? '—' : audioTime(duration)}',
                  ),
                  if (controller.phase == TrackAudioPhase.loading)
                    const Text('Preparando audio…'),
                  if (controller.phase == TrackAudioPhase.error)
                    const Text(
                      'Esta pista no se pudo reproducir. Reintenta o elige la siguiente.',
                    ),
                  if (controller.phase == TrackAudioPhase.completed)
                    const Text('Fin de la cola.'),
                  PlayerControls(controller: controller),
                  const Text(
                    'Este origen todavía no permite adelantar o retroceder.',
                  ),
                ] else
                  const Text('Añade canciones desde la búsqueda para empezar.'),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Cola (${controller.queue.length}/100)',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: controller.queue.isEmpty
                          ? null
                          : () => unawaited(controller.clear()),
                      child: const Text('Vaciar'),
                    ),
                  ],
                ),
                ...controller.queue.indexed.map(
                  (entry) => ListTile(
                    selected: entry.$1 == controller.index,
                    leading: Text('${entry.$1 + 1}'),
                    title: Text(entry.$2.title),
                    subtitle: Text(entry.$2.artistName),
                    onTap: () => unawaited(controller.jump(entry.$1)),
                    trailing: entry.$1 == controller.index
                        ? const Icon(Icons.equalizer)
                        : IconButton(
                            tooltip: 'Quitar de la cola',
                            onPressed: () => controller.remove(entry.$1),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
