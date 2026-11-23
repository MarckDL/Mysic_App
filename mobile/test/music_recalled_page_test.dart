import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';

import 'support/ytm_test_client.dart';

MusicConnection _linked(String generation) => MusicConnection(
  status: MusicLinkStatus.linked,
  provider: 'youtubeOAuth',
  personalization: 'verified',
  accounts: const [],
  account: const MusicAccount('a', 'Cuenta', false),
  generation: generation,
  libraryId: 'library-a',
  capabilities: const {'playlists', 'liked', 'history'},
);

/// Un servidor que responde una página con el título de lo que se le pidió.
class _Pages extends MusicModeClient {
  _Pages() : super(ytm: ytmTestClient(), ytmAccount: () => null);

  String generation = 'g-1';
  int requests = 0;

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async =>
      _linked(generation);

  @override
  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
    bool remember = false,
  }) async {
    requests++;
    return MusicPage(const [], null, null, 0, playlistId ?? surface.name);
  }
}

void main() {
  Future<(MusicModeController, _Pages)> mount() async {
    final client = _Pages();
    final controller = MusicModeController(client, () => true, () async {});
    addTearDown(controller.dispose);
    await controller.refresh();
    return (controller, client);
  }

  test('la primera página vista de cada pantalla se recuerda', () async {
    final (controller, _) = await mount();
    expect(
      controller.recalledPage('g-1', MusicSurface.playlist, playlistId: 'p1'),
      isNull,
    );
    await controller.page('g-1', MusicSurface.playlist, playlistId: 'p1');
    await controller.page('g-1', MusicSurface.playlist, playlistId: 'p2');
    await controller.page('g-1', MusicSurface.liked);
    expect(
      controller
          .recalledPage('g-1', MusicSurface.playlist, playlistId: 'p1')
          ?.title,
      'p1',
    );
    expect(
      controller
          .recalledPage('g-1', MusicSurface.playlist, playlistId: 'p2')
          ?.title,
      'p2',
    );
    expect(controller.recalledPage('g-1', MusicSurface.liked)?.title, 'liked');
  });

  test('ni las búsquedas ni las páginas siguientes se recuerdan', () async {
    final (controller, _) = await mount();
    await controller.page('g-1', MusicSurface.search, query: 'hola');
    await controller.page(
      'g-1',
      MusicSurface.playlist,
      playlistId: 'p1',
      cursor: 'siguiente',
    );
    expect(controller.recalledPage('g-1', MusicSurface.search), isNull);
    expect(
      controller.recalledPage('g-1', MusicSurface.playlist, playlistId: 'p1'),
      isNull,
    );
  });

  test('al cambiar de conexión lo recordado deja de servir', () async {
    final (controller, client) = await mount();
    await controller.page('g-1', MusicSurface.liked);
    client.generation = 'g-2';
    await controller.refresh();
    // Ni con la conexión vieja ni con la nueva.
    expect(controller.recalledPage('g-1', MusicSurface.liked), isNull);
    expect(controller.recalledPage('g-2', MusicSurface.liked), isNull);
  });
}
