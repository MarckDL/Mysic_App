import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/playback_providers.dart';
import '../domain/track_audio_engine.dart';
import '../../search/presentation/catalog_widgets.dart';
import 'player_widgets.dart';
import '../../../app/mysic_theme.dart';
import '../../favorites/application/favorite_providers.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    return Theme(
      data: buildMysicPlayerTheme(),
      child: Scaffold(
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
                      child: TrackArtwork(url: track.thumbnailUrl, size: 280),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            track.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        ref
                            .watch(favoriteStatusProvider(track.id))
                            .when(
                              loading: () => const SizedBox.square(
                                dimension: 48,
                                child: Padding(
                                  padding: EdgeInsets.all(14),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              error: (_, _) => IconButton(
                                tooltip: 'Reintentar favorito',
                                onPressed: () => ref.invalidate(
                                  favoriteStatusProvider(track.id),
                                ),
                                icon: const Icon(Icons.favorite_border),
                              ),
                              data: (favorite) => IconButton(
                                tooltip: favorite
                                    ? 'Quitar de favoritos'
                                    : 'Añadir a favoritos',
                                onPressed: () => ref
                                    .read(favoriteActionsProvider.notifier)
                                    .set(track.id, !favorite),
                                icon: Icon(
                                  favorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                ),
                              ),
                            ),
                      ],
                    ),
                    Text(track.artistName),
                    const SizedBox(height: 16),
                    Slider(
                      value: duration == null || duration.inMilliseconds <= 0
                          ? 0
                          : controller.position.inMilliseconds
                                .clamp(0, duration.inMilliseconds)
                                .toDouble(),
                      max: duration == null || duration.inMilliseconds <= 0
                          ? 1
                          : duration.inMilliseconds.toDouble(),
                      onChanged:
                          duration == null || duration.inMilliseconds <= 0
                          ? null
                          : (value) => unawaited(
                              controller.seek(
                                Duration(milliseconds: value.round()),
                              ),
                            ),
                    ),
                    Text(
                      '${audioTime(controller.position)} / ${duration == null ? '—' : audioTime(duration)}',
                      textAlign: TextAlign.center,
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
                  ] else
                    const Text(
                      'Añade canciones desde la búsqueda para empezar.',
                    ),
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
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: controller.queue.length,
                    onReorderItem: controller.reorder,
                    itemBuilder: (context, itemIndex) {
                      final item = controller.queue[itemIndex];
                      return ListTile(
                        key: ValueKey(item.id),
                        selected: itemIndex == controller.index,
                        leading: Text('${itemIndex + 1}'),
                        title: Text(item.title),
                        subtitle: Text(item.artistName),
                        onTap: () => unawaited(controller.jump(itemIndex)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (itemIndex == controller.index)
                              const Icon(Icons.equalizer)
                            else
                              IconButton(
                                tooltip: 'Quitar de la cola',
                                onPressed: () => controller.remove(itemIndex),
                                icon: const Icon(Icons.close),
                              ),
                            ReorderableDragStartListener(
                              index: itemIndex,
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
