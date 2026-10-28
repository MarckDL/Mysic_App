import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/catalog_providers.dart';
import 'catalog_widgets.dart';
import '../../playback/presentation/playback_availability_panel.dart';

class TrackDetailScreen extends ConsumerWidget {
  const TrackDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Detalle de canción')),
    body: SafeArea(
      child: ref
          .watch(trackDetailProvider(id))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => CatalogError(
              error: error,
              retry: () => ref.invalidate(trackDetailProvider(id)),
            ),
            data: (track) => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(child: TrackArtwork(url: track.thumbnailUrl, size: 200)),
                const SizedBox(height: 24),
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(track.artistName),
                if (track.durationLabel != null)
                  Text('Duración: ${track.durationLabel}'),
                const SizedBox(height: 24),
                const Text('Fuente: YouTube Music · Catálogo experimental'),
                const SizedBox(height: 8),
                const Text('Reproducción aún no disponible en Mysic.'),
                PlaybackAvailabilityPanel(
                  key: ValueKey(track.id),
                  sourceId: track.id.substring(8),
                ),
              ],
            ),
          ),
    ),
  );
}
