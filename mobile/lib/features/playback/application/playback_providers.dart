import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../authentication/application/auth_providers.dart';
import '../../radio/data/now_playing_client.dart';
import '../../connected_library/domain/music_mode.dart' show MusicTrack;
import '../../authentication/domain/auth_repository.dart';
import '../../history/application/listening_tracker.dart';
import '../../history/data/local_listens.dart';
import '../../ytm/data/liked_tracks.dart';
import '../../ytm/data/ytm_client.dart';
import '../data/just_audio_track_engine.dart';
import '../data/mysic_audio_handler.dart';
import '../domain/track_audio_engine.dart';
import 'track_playback_controller.dart';

final mediaHandlerProvider = Provider<MysicAudioHandler?>((ref) => null);

/// Las canciones con Me gusta de la cuenta de YouTube Music; null sin sesión.
final likedTracksProvider = Provider.autoDispose<LikedTracks?>((ref) {
  final session = ref.watch(ytmAuthProvider).session;
  if (session == null) return null;
  final client = YtmClient(session);
  final likes = LikedTracks(client);
  unawaited(likes.load());
  ref.onDispose(() {
    likes.dispose();
    client.close();
  });
  return likes;
});

final trackAudioEngineFactoryProvider = Provider<TrackAudioEngine Function()>(
  (ref) =>
      () => JustAudioTrackEngine(keepAudio: () => ref.read(keepAudioProvider)),
);

final trackPlaybackControllerProvider =
    Provider.autoDispose<TrackPlaybackController>((ref) {
      // El controlador escucha el cierre de sesión; no reconstruirlo sin
      // usuario al salir.
      final auth = ref.watch(authRepositoryProvider);
      final uid = auth.currentUser?.uid;
      if (uid == null) {
        throw const AuthFailure('Inicia sesión en YouTube Music.');
      }
      final controller = TrackPlaybackController(
        auth,
        ref.watch(trackAudioEngineFactoryProvider)(),
        uid,
        liveInfo: fetchLiveNowPlaying,
        hlsInfo: fetchHlsTrackInfo,
        moodsFetcher: fetchRadioMoods,
        radio: (videoId, {cursor}) async {
          final session = ref.read(ytmAuthProvider).session;
          if (session == null) throw const AuthFailure('Sin sesión.');
          final client = YtmClient(session);
          try {
            final page = await client.radio(videoId, cursor: cursor);
            return RadioBatch([
              for (final json in page.tracks)
                MusicTrack.fromJson(json).toPlaybackTrack(),
            ], page.next);
          } finally {
            client.close();
          }
        },
        history: ListeningTracker(
          () => auth.currentUser?.uid == uid,
          // Cada escucha que cuenta queda en la base del teléfono, de donde
          // salen Recientes y Lo más oído.
          onListened: (track, ms, at) {
            final listen = LocalListen.of(track, ms, at);
            if (listen != null) {
              unawaited(ref.read(localListensProvider(uid)).record(listen));
            }
          },
        ),
      );
      final handler = ref.watch(mediaHandlerProvider);
      final likes = ref.watch(likedTracksProvider);
      handler?.bind(controller);
      if (handler != null && likes != null) {
        handler.bindLikes(
          isLiked: likes.isLiked,
          toggle: likes.toggle,
          changes: likes,
        );
      }
      ref.onDispose(() {
        handler?.unbindLikes();
        handler?.unbind(controller);
        controller.dispose();
      });
      return controller;
    });
