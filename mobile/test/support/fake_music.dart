import 'package:dio/dio.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';

import 'ytm_test_client.dart';

/// Un cliente de música sin red: la cuenta ya vinculada y páginas vacías.
class FakeMusicClient extends MusicModeClient {
  FakeMusicClient() : super(ytm: ytmTestClient(), ytmAccount: () => null);

  @override
  Future<MusicConnection?> rememberedConnection() async => null;

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async =>
      const MusicConnection(
        status: MusicLinkStatus.linked,
        provider: 'youtubeOAuth',
        personalization: 'verified',
        account: MusicAccount('a', 'Ana', false),
        accounts: [MusicAccount('a', 'Ana', false)],
        generation: MusicModeClient.ytmGeneration,
        capabilities: MusicModeClient.ytmCapabilities,
      );

  @override
  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
    bool remember = false,
  }) async => const MusicPage([], null, null, 0);
}

/// Sustituye el controlador de música por uno sin red.
final fakeMusicOverride = musicModeControllerProvider.overrideWith((ref, uid) {
  final controller = MusicModeController(
    FakeMusicClient(),
    () => true,
    () async {},
  );
  ref.onDispose(controller.dispose);
  return controller;
});
