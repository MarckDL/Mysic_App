import 'package:mysic/features/search/presentation/music_tiles.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/api_failure.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/ytm/data/ytm_client.dart';
import 'package:mysic/features/ytm/data/ytm_session.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_screen.dart';
import 'package:mysic/features/connected_library/presentation/tab_top_bar.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_host.dart';

const a = MusicAccount('a', 'Cuenta A', false);
const a2 = MusicAccount('a2', 'Canal alterno A', true);
const b = MusicAccount('b', 'Cuenta B', false);
const capabilities = {
  'home',
  'songs',
  'playlists',
  'playlist',
  'search',
  'history',
  'playback',
  'recordListen',
};

class _SessionFixture extends MusicModeClient {
  _SessionFixture(this.accounts, {this.direct = false})
    : super(
        ytm: YtmClient(const YtmSession('SAPISID=t')),
        ytmAccount: () => null,
      );
  final bool direct;
  bool channelOnly = false;
  int explicitChecks = 0;
  final List<MusicAccount> accounts;
  MusicAccount? account;
  int links = 0;
  int writes = 0;
  bool loseResponse = false;
  bool expired = false;
  int epoch = 4;
  int? recordedEpoch;
  Completer<MusicPage>? pending;
  Completer<MusicConnection>? pendingConnection;
  final recorded = <String, MusicTrack>{};

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async {
    if (recheckMusic) explicitChecks++;
    final pending = pendingConnection;
    if (pending != null) {
      pendingConnection = null;
      return pending.future;
    }
    return MusicConnection(
      status: account == null
          ? MusicLinkStatus.unlinked
          : expired
          ? MusicLinkStatus.expired
          : MusicLinkStatus.linked,
      provider: direct ? 'youtubeOAuth' : 'preview',
      personalization: direct
          ? (channelOnly ? 'channelOnly' : 'verified')
          : null,
      accounts: direct ? [] : accounts,
      account: account,
      generation: account == null ? null : '${account!.id}-$links',
      libraryId: direct && account != null ? 'library-${account!.id}' : null,
      activityEpoch: epoch,
      capabilities: channelOnly
          ? {
              'channelLiked',
              'playlists',
              'playlist',
              'search',
              'playback',
              'artists',
              'artist',
            }
          : direct
          ? {
              'home',
              'albums',
              'album',
              'songs',
              'liked',
              'playlists',
              'playlist',
              'playback',
              'search',
              'recordInMysic',
              'mysicRecents',
              'onRepeat',
              'artists',
              'artist',
            }
          : capabilities,
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
  }) async {
    // Recientes y Lo más oído salen de la base local, no de la página que
    // se está probando.
    if (surface == MusicSurface.onRepeat ||
        surface == MusicSurface.mysicRecents) {
      return const MusicPage([], null, null, 0);
    }
    if (pending case final pending?) return pending.future;
    final current = account!;
    final playlist = MusicPlaylist(
      current.id,
      'Lista de ${current.name}',
      true,
    );
    final one = MusicTrack(
      direct ? '9xgftPjTz7c' : '${current.id}-1',
      'Canción de ${current.name}',
      'Mysic',
      8,
      !direct,
      null,
      audioUri: direct
          ? Uri.https('media.example.test', '/recording.mp3')
          : null,
    );
    final two = MusicTrack(
      direct ? 'k1HtSmS4Tc4' : '${current.id}-2',
      'Siguiente de ${current.name}',
      'Mysic',
      8,
      !direct,
      null,
    );
    return switch (surface) {
      MusicSurface.home => MusicPage(
        [
          if (direct)
            MusicTrack(
              'aaaaaaaaaaa',
              'Recomendado para ${current.name}',
              'Artista',
              150,
              false,
              null,
              nativePlayback: true,
            )
          else
            one,
          playlist,
        ],
        null,
        null,
        0,
      ),
      MusicSurface.playlists => MusicPage([playlist], null, null, 0),
      MusicSurface.playlist =>
        playlistId == current.id
            ? MusicPage([one, two], null, playlist, 2)
            : throw const ApiFailure(
                'No disponible.',
                code: 'MUSIC_PLAYLIST_NOT_FOUND',
              ),
      MusicSurface.songs ||
      MusicSurface.channelLiked ||
      MusicSurface.liked => MusicPage([one, two], null, null, 0),
      MusicSurface.search => MusicPage(
        [one, playlist].where((item) => item.title.contains(query!)).toList(),
        null,
        null,
        0,
      ),
      MusicSurface.albums => const MusicPage(
        [MusicAlbum('MPREb1', 'Disco guardado')],
        null,
        null,
        0,
      ),
      MusicSurface.album => MusicPage([one], null, null, 0, 'Disco guardado'),

      MusicSurface.artists ||
      MusicSurface.onRepeat ||
      MusicSurface.artist ||
      MusicSurface.mysicRecents => const MusicPage([], null, null, 0),
      MusicSurface.history => MusicPage(
        recorded.values.toList(),
        null,
        null,
        0,
      ),
    };
  }

  @override
  Future<void> activityPreference(String generation, {bool? paused}) async {
    final current = account!;
    if (paused == null) {
      recorded.clear();
    } else {
      account = MusicAccount(current.id, current.name, paused);
    }
    epoch++;
  }
}

void main() {
  setUpAll(() => NowPlayingBars.animationsEnabled = false);
  testWidgets(
    'Actualizar Inicio vuelve a pedir la página y conserva el reproductor',
    (tester) async {
      final fixture = _SessionFixture([a], direct: true)..account = a;
      var clears = 0;
      final model = MusicModeController(fixture, () => true, () async {
        clears++;
      });
      addTearDown(model.dispose);
      await model.refresh();
      final initialClears = clears;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MusicModeScope(
              controller: model,
              child: const MusicModeSurface(surface: MusicSurface.home),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recomendado para Cuenta A'), findsOneWidget);
      await tester.tap(find.byTooltip('Actualizar'));
      await tester.pumpAndSettle();
      expect(find.text('Recomendado para Cuenta A'), findsOneWidget);
      // Recargar la página no detiene lo que suena.
      expect(clears, initialClears);
    },
  );
  testWidgets('el collage de Inicio se compone una vez y no cambia solo', (
    tester,
  ) async {
    final fixture = _SessionFixture([a], direct: true)..account = a;
    final model = MusicModeController(fixture, () => true, () async {});
    addTearDown(model.dispose);
    await model.refresh();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MusicModeScope(
            controller: model,
            child: const MusicModeSurface(surface: MusicSurface.home),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Llegan los datos secundarios y el collage se compone.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Accesos directos'), findsOneWidget);
    expect(find.text('Recomendado para Cuenta A'), findsOneWidget);
    // Aunque pase el tiempo (antes rotaba solo), sigue siendo el mismo.
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    expect(find.text('Accesos directos'), findsOneWidget);
    expect(find.text('Recomendado para Cuenta A'), findsOneWidget);
  });
  testWidgets(
    'el contenido de la pantalla de música empieza bajo la barra superior, también con barra de estado',
    (tester) async {
      final fixture = _SessionFixture([a], direct: true)..account = a;
      final model = MusicModeController(fixture, () => true, () async {});
      addTearDown(model.dispose);
      await model.refresh();
      fixture.pending = Completer<MusicPage>()
        ..complete(
          const MusicPage(
            [
              MusicTrack(
                'aaaaaaaaaaa',
                'Primera canción',
                'Artista',
                160,
                false,
                null,
                nativePlayback: true,
              ),
            ],
            null,
            null,
            0,
          ),
        );
      const status = 40.0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            // Una barra de estado simulada de 40 px, como la de un teléfono.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: const EdgeInsets.only(top: status)),
              child: child!,
            ),
            // Igual que en la app: la pantalla vive en el cuerpo de un
            // Scaffold con barra de pestañas.
            home: Scaffold(
              body: MusicModeScope(
                controller: model,
                child: const MusicModeSurface(surface: MusicSurface.home),
              ),
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home),
                    label: 'Inicio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search),
                    label: 'Buscar',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(TabTopBar));
      final greeting = tester.getTopLeft(
        find.byWidgetPredicate(
          // El saludo lleva detrás el nombre de pila de la cuenta.
          (widget) =>
              widget is Text &&
              const [
                'Buenos días',
                'Buenas tardes',
                'Buenas noches',
              ].any((greeting) => widget.data?.startsWith(greeting) ?? false),
        ),
      );
      // La barra ocupa la barra de estado más la altura de la barra...
      expect(bar.top, 0);
      expect(bar.height, closeTo(status + TabTopBar.height, 1));
      // ...y el primer elemento queda por debajo de ella, no debajo del título.
      expect(greeting.dy, greaterThanOrEqualTo(bar.bottom));

      // La barra es transparente arriba del todo y también al desplazar: ya no
      // desenfoca nada (solo baja un velo que se desvanece).
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, -120));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(BackdropFilter), findsNothing);
      // Y sigue fija en su sitio.
      final fixed = tester.getRect(find.byType(TabTopBar));
      expect(fixed.top, 0);
      expect(fixed.height, closeTo(status + TabTopBar.height, 1));
    },
  );
  testWidgets('Inicio respeta el orden y los títulos de YouTube Music', (
    tester,
  ) async {
    final fixture = _SessionFixture([a], direct: true)..account = a;
    final model = MusicModeController(fixture, () => true, () async {});
    addTearDown(model.dispose);
    await model.refresh();
    fixture.pending = Completer<MusicPage>()
      ..complete(
        const MusicPage(
          [
            MusicAlbum(
              'album',
              'Disco de prueba',
              shelfTitle: 'Vuelve a escuchar',
            ),
            MusicPlaylist(
              'mix',
              'Mix de prueba',
              false,
              shelfTitle: 'Vuelve a escuchar',
            ),
            MusicTrack(
              'aaaaaaaaaaa',
              'Primera canción',
              'Artista',
              160,
              false,
              null,
              nativePlayback: true,
              shelfTitle: 'Selecciones rápidas',
            ),
          ],
          null,
          null,
          0,
        ),
      );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MusicModeScope(
            controller: model,
            child: const MusicModeSurface(surface: MusicSurface.home),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final order = [
      'Vuelve a escuchar',
      'Disco de prueba',
      'Mix de prueba',
      'Selecciones rápidas',
      'Primera canción',
    ];
    // Orden de lectura: cada sección va debajo de la anterior y, dentro de su
    // carrusel horizontal, cada tarjeta queda a la derecha de la previa.
    Offset? previous;
    for (final text in order) {
      // El Inicio es más alto que la pantalla de prueba: las últimas
      // secciones existen fuera de la vista.
      // Una playlist de la cuenta aparece también en los accesos "De one pe"
      // del principio; el orden de las secciones se comprueba con la última.
      final label = find.text(text, skipOffstage: false);
      expect(label, findsAtLeastNWidgets(1));
      final at = tester.getTopLeft(label.last);
      if (previous != null) {
        expect(
          at.dy > previous.dy || (at.dy == previous.dy && at.dx > previous.dx),
          isTrue,
          reason: '"$text" debe ir después del elemento anterior',
        );
      }
      previous = at;
    }
    expect(find.text('Recomendaciones de YouTube Music'), findsNothing);
    expect(find.text('Lo más oído'), findsNothing);
  });

  testWidgets(
    'el acceso a Me gusta del reproductor abre la colección de la fuente activa',
    (tester) async {
      final fixture = _SessionFixture([a], direct: true)
        ..account = a
        ..channelOnly = true;
      final model = MusicModeController(fixture, () => true, () async {});
      addTearDown(model.dispose);
      await model.refresh();
      expect(
        model.connection!.likesActionLabel,
        'Ver los Me gusta de mi canal',
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MusicModeScope(
              controller: model,
              child: const MusicModeSurface(surface: MusicSurface.liked),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Con cabecera propia: título grande, no el de la barra.
      expect(find.text('Tus Me gusta'), findsOneWidget);
      expect(find.text('LISTA AUTOMÁTICA'), findsOneWidget);
      // Ninguna pantalla repite la línea de la cuenta bajo la barra.
      expect(find.textContaining('Canal de YouTube ·'), findsNothing);
      expect(find.text('Canción de Cuenta A'), findsOneWidget);
      expect(find.text('Opciones de conexión'), findsNothing);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MusicModeScope(
              controller: model,
              child: const MusicModeSurface(surface: MusicSurface.songs),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Me gusta de mi canal'), findsOneWidget);
      // La Biblioteca no repite la línea de la cuenta arriba.
      expect(find.text('Canal de YouTube · Cuenta A'), findsNothing);
      expect(find.textContaining('Google autorizó'), findsNothing);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MusicModeScope(
              controller: model,
              child: const MusicModeSurface(surface: MusicSurface.home),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Inicio ya no lleva ese texto de cabecera.
      expect(find.text('Música que te gusta en YouTube'), findsNothing);
      expect(find.text('Tus playlists musicales'), findsNothing);
      expect(find.text('Recomendaciones de YouTube Music'), findsNothing);
    },
  );
  test('la biblioteca conserva las portadas de playlists y canales', () {
    const cover = 'https://i.ytimg.com/vi/ABCDEFGHIJK/default.jpg';
    final page = MusicPage.fromJson({
      'items': [
        {
          'id': 'PL1',
          'kind': 'playlist',
          'title': 'Lista',
          'private': true,
          'thumbnailUrl': cover,
        },
        {
          'id': 'UC1',
          'kind': 'artist',
          'title': 'Grupo',
          'thumbnailUrl': cover,
        },
      ],
    });
    expect((page.items.first as MusicPlaylist).thumbnailUrl, cover);
    expect((page.items.last as MusicArtist).thumbnailUrl, cover);
  });
}
