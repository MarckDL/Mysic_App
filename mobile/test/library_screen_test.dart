import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/presentation/library_screen.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_host.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_screen.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';

import 'support/ytm_test_client.dart';

class _Library extends MusicModeClient {
  _Library(this.capabilities)
    : super(ytm: ytmTestClient(), ytmAccount: () => null);

  final Set<String> capabilities;
  final requested = <MusicSurface>[];

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async =>
      MusicConnection(
        status: MusicLinkStatus.linked,
        generation: 'library',
        account: const MusicAccount('channel', 'Cuenta A', false),
        provider: 'youtubeOAuth',
        personalization: 'full',
        capabilities: capabilities,
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
  }) async {
    requested.add(surface);
    return switch (surface) {
      MusicSurface.playlists => const MusicPage(
        [MusicPlaylist('p1', 'Para correr', true)],
        null,
        null,
        0,
      ),
      _ => const MusicPage([], null, null, 0),
    };
  }
}

Future<_Library> _pump(WidgetTester tester, Set<String> capabilities) async {
  final client = _Library(capabilities);
  final controller = MusicModeController(client, () => true, () async {});
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
  return client;
}

Finder _chip(String label) => find.widgetWithText(LibraryChip, label);

void main() {
  setUpAll(() => NowPlayingBars.animationsEnabled = false);

  testWidgets('los chips salen según lo que la cuenta puede mostrar', (
    tester,
  ) async {
    await _pump(tester, {'playlists', 'liked'});
    expect(_chip('Todo'), findsOneWidget);
    expect(_chip('Playlists'), findsOneWidget);
    expect(_chip('Canciones'), findsOneWidget);
    expect(_chip('Descargas'), findsOneWidget);
    // Sin esas capacidades no hay pestaña.
    expect(_chip('Álbumes'), findsNothing);
    expect(_chip('Artistas'), findsNothing);
    expect(tester.widget<LibraryChip>(_chip('Todo')).selected, isTrue);
  });

  testWidgets('Todo muestra teselas, estante de playlists y recientes', (
    tester,
  ) async {
    final client = await _pump(tester, {
      'playlists',
      'liked',
      'artists',
      'albums',
    });
    expect(find.text('Tus Me gusta'), findsOneWidget);
    expect(find.text('Los que sigues'), findsOneWidget);
    expect(find.text('Para correr'), findsOneWidget);
    expect(find.text('Añadido recientemente'), findsOneWidget);
    // Los álbumes no se piden hasta abrir su pestaña.
    expect(client.requested, isNot(contains(MusicSurface.albums)));
    await tester.tap(_chip('Álbumes'));
    await tester.pumpAndSettle();
    expect(client.requested, contains(MusicSurface.albums));
    expect(find.text('Aún no has guardado álbumes.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Ver todo» y la tesela Artistas cambian de pestaña', (
    tester,
  ) async {
    final client = await _pump(tester, {'playlists', 'liked', 'artists'});
    await tester.tap(find.text('Ver todo'));
    await tester.pumpAndSettle();
    expect(tester.widget<LibraryChip>(_chip('Playlists')).selected, isTrue);
    expect(find.text('Para correr'), findsOneWidget);
    // La lista ya estaba: cambiar de pestaña no la vuelve a pedir.
    expect(
      client.requested.where((s) => s == MusicSurface.playlists).length,
      1,
    );
    await tester.tap(_chip('Todo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Los que sigues'));
    await tester.pumpAndSettle();
    expect(tester.widget<LibraryChip>(_chip('Artistas')).selected, isTrue);
    expect(find.text('Aún no sigues a ningún artista.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Descargas explica cómo descargar cuando no hay ninguna', (
    tester,
  ) async {
    await _pump(tester, {'playlists'});
    await tester.tap(_chip('Descargas'));
    await tester.pumpAndSettle();
    expect(find.text('Solo canciones descargadas'), findsOneWidget);
    expect(find.textContaining('Mantén pulsada una canción'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
