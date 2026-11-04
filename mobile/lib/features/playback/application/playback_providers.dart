import '../data/mysic_audio_handler.dart';
import '../data/just_audio_track_engine.dart';
import '../domain/track_audio_engine.dart';
import 'track_playback_controller.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../data/playback_repository.dart';
import '../data/just_audio_demo_engine.dart';
import '../domain/demo_audio_engine.dart';
import '../domain/playback_resolution.dart';
import 'demo_controller.dart';

final playbackRepositoryProvider = Provider.autoDispose<PlaybackRepository>((
  ref,
) {
  final api = AuthenticatedApiClient(
    ref.watch(authRepositoryProvider),
    baseUrl: ApiConfig.baseUrl,
  );
  ref.onDispose(api.close);
  return ApiPlaybackRepository(api);
});
final demoEngineFactoryProvider = Provider<DemoAudioEngine Function()>(
  (ref) => JustAudioDemoEngine.new,
);
final demoControllerProvider = Provider.autoDispose<DemoController>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) throw const AuthFailure('Inicia sesión con Google.');
  final auth = ref.watch(authRepositoryProvider);
  final controller = DemoController(
    ref.watch(playbackRepositoryProvider),
    ref.watch(demoEngineFactoryProvider)(),
    uid,
    () => auth.currentUser?.uid,
  );
  ref.onDispose(() => unawaited(controller.dispose()));
  return controller;
});
final playbackAvailabilityProvider = FutureProvider.autoDispose
    .family<PlaybackResolution, String>((ref, sourceId) async {
      final uid = ref.watch(authStateProvider).asData?.value?.uid;
      if (uid == null) throw const AuthFailure('Inicia sesión con Google.');
      final cancel = CancelToken();
      ref.onDispose(() => cancel.cancel());
      return ref
          .watch(playbackRepositoryProvider)
          .resolve('youtube', sourceId, cancelToken: cancel);
    }, retry: (count, error) => null);

final mediaHandlerProvider = Provider<MysicAudioHandler?>((ref) => null);

final trackAudioEngineFactoryProvider = Provider<TrackAudioEngine Function()>(
  (ref) =>
      () => JustAudioTrackEngine(ApiConfig.baseUrl),
);
final trackPlaybackControllerProvider =
    Provider.autoDispose<TrackPlaybackController>((ref) {
      // El controlador escucha logout; no reconstruirlo sin usuario al salir.
      final auth = ref.watch(authRepositoryProvider);
      final uid = auth.currentUser?.uid;
      if (uid == null) throw const AuthFailure('Inicia sesión con Google.');
      final controller = TrackPlaybackController(
        auth,
        ref.watch(trackAudioEngineFactoryProvider)(),
        uid,
      );
      final handler = ref.watch(mediaHandlerProvider);
      handler?.bind(controller);
      ref.onDispose(() {
        handler?.unbind(controller);
        controller.dispose();
      });
      return controller;
    });
