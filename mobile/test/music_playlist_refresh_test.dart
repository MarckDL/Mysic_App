import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_host.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_screen.dart';

import 'support/fake_auth_repository.dart';

class _Playlists extends MusicModeClient {
  _Playlists(super.api);

  final requests = <String?>[];
  String latest = 'Mi lista inicial';
  Completer<void>? pauseFirst;

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async =>
      const MusicConnection(
        status: MusicLinkStatus.linked,
        generation: 'same-source',
        account: MusicAccount('channel', 'Cuenta A', false),
        provider: 'youtubeOAuth',
        personalization: 'channelOnly',
        capabilities: {'playlists', 'channelLiked'},
      );

  @override
  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    if (surface != MusicSurface.playlists) {
      return const MusicPage([], null, null, 0);
    }
    requests.add(cursor);
    if (cursor == null) {
      await pauseFirst?.future;
      return const MusicPage(
        [MusicPlaylist('p1', 'Ya guardada', true)],
        'next',
        null,
        0,
      );
    }
    return MusicPage([MusicPlaylist('p2', latest, true)], null, null, 0);
  }
}

void main() {
  testWidgets(
    'volver recarga playlists nuevas y actualizar conserva la selección y las filas mientras carga',
    (tester) async {
      final api = AuthenticatedApiClient(
        FakeAuthRepository(),
        baseUrl: 'https://example.test',
      );
      final catalog = _Playlists(api);
      var playbackClears = 0;
      final controller = MusicModeController(catalog, () => true, () async {
        playbackClears++;
      });
      addTearDown(api.close);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MusicModeHost(
              controller: controller,
              child: const MusicModeSurface(surface: MusicSurface.songs),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      expect(catalog.requests, [null, 'next']);
      expect(find.text('Mi lista inicial'), findsOneWidget);
      final initialClears = playbackClears;
      catalog.latest = 'Creada en YouTube Music';
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(catalog.requests, [null, 'next', null, 'next']);
      expect(find.text('Creada en YouTube Music'), findsOneWidget);
      expect(find.text('Mi lista inicial'), findsNothing);
      catalog.latest = 'Renombrada en YouTube Music';
      catalog.pauseFirst = Completer<void>();
      await tester.tap(find.byTooltip('Actualizar'));
      await tester.pump();
      expect(find.text('Creada en YouTube Music'), findsOneWidget);
      catalog.pauseFirst!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Renombrada en YouTube Music'), findsOneWidget);
      expect(find.text('Creada en YouTube Music'), findsNothing);
      expect(playbackClears, initialClears);
      expect(tester.takeException(), isNull);
    },
  );
}
