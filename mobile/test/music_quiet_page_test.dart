import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/api_failure.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';

import 'support/ytm_test_client.dart';

/// Un servidor cuyas páginas fallan pidiendo reconectar: el caso en que el
/// controlador refresca la conexión.
class _Failing extends MusicModeClient {
  _Failing() : super(ytm: ytmTestClient(), ytmAccount: () => null);

  int connections = 0;

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async {
    connections++;
    return MusicConnection(
      status: MusicLinkStatus.linked,
      provider: 'youtubeOAuth',
      personalization: 'verified',
      accounts: const [],
      account: const MusicAccount('a', 'Cuenta', false),
      generation: 'g-1',
      libraryId: 'library-a',
      capabilities: const {'playlists', 'liked', 'history'},
    );
  }

  @override
  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
    bool remember = false,
  }) async => throw const ApiFailure('Reconecta', code: 'MUSIC_RECONNECT');
}

void main() {
  Future<(MusicModeController, _Failing)> mount() async {
    final client = _Failing();
    final controller = MusicModeController(client, () => true, () async {});
    addTearDown(controller.dispose);
    await controller.refresh();
    return (controller, client);
  }

  test('una consulta secundaria que falla no refresca la conexión', () async {
    final (controller, client) = await mount();
    expect(client.connections, 1);
    await expectLater(
      controller.page('g-1', MusicSurface.history, quiet: true),
      throwsA(isA<ApiFailure>()),
    );
    await Future<void>.delayed(Duration.zero);
    // Sin refresco: ni una consulta más de conexión ni cambio de revisión que
    // aborte la lista que se está cargando a la vez.
    expect(client.connections, 1);
  });

  test(
    'una consulta principal que falla sí pide refrescar la conexión',
    () async {
      final (controller, client) = await mount();
      await expectLater(
        controller.page('g-1', MusicSurface.history),
        throwsA(isA<ApiFailure>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.connections, greaterThan(1));
    },
  );
}
