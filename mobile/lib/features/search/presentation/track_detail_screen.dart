import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/catalog_providers.dart';
import 'catalog_widgets.dart';
import '../../comments/presentation/comment_feed_panel.dart';
import '../../playback/presentation/playback_availability_panel.dart';
import '../../playlists/presentation/add_to_playlist_button.dart';
import '../../ratings/presentation/track_preferences_panel.dart';

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
                TrackHeading(track: track),
                if (track.durationLabel case final duration?)
                  Text(duration, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                AddToPlaylistButton(trackId: track.id),
                if (track.id == 'youtube:aqz-KE-bpKQ')
                  const Text(
                    'Big Buck Bunny · © 2008 Blender Foundation · bigbuckbunny.org · CC BY 3.0',
                  ),
                PlaybackAvailabilityPanel(
                  key: ValueKey(track.id),
                  track: track,
                ),
                const SizedBox(height: 12),
                TrackPreferencesPanel(trackId: track.id),
                const SizedBox(height: 24),
                CommentFeedPanel(key: ValueKey(track.id), trackId: track.id),
              ],
            ),
          ),
    ),
  );
}
