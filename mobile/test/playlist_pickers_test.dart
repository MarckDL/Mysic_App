import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/presentation/home_sheets.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_host.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_screen.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';
import 'package:mysic/features/ytm/data/ytm_client.dart';
import 'package:mysic/features/ytm/data/ytm_parser.dart';
import 'package:mysic/features/ytm/data/ytm_session.dart';

/// YouTube Music de mentira: responde al cuadro «Guardar en playlist» y a las
/// ediciones, y recuerda lo que se le pidió.
class _Server implements HttpClientAdapter {
  /// Las playlists que ya contienen la canción (`containsSelectedVideos`).
  final contains = <String>{};

  /// Si es true, YouTube rechaza las ediciones.
  var refuse = false;

  /// Las ediciones recibidas: (playlist, acciones).
  final edits = <(String, List<Map<String, dynamic>>)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.data is Map
        ? Map<String, dynamic>.from(options.data as Map)
        : <String, dynamic>{};
    Object answer = <String, dynamic>{};
    if (options.path.endsWith('playlist/get_add_to_playlist')) {
      answer = {
        'contents': [
          {
            'addToPlaylistRenderer': {
              'playlists': [
                for (final (id, title, line) in const [
                  ('PLaaaaaaaaaa', 'Para correr', 'Privada • 12 canciones'),
                  ('PLbbbbbbbbbb', 'Para dormir', 'Privada • 1 canción'),
                ])
                  {
                    'playlistAddToOptionRenderer': {
                      'playlistId': id,
                      'title': {
                        'runs': [
                          {'text': title},
                        ],
                      },
                      'containsSelectedVideos': contains.contains(id)
                          ? 'ALL'
                          : 'NONE',
                      'shortBylineText': {
                        'runs': [
                          {'text': line},
                        ],
                      },
                    },
                  },
              ],
            },
          },
        ],
      };
    } else if (options.path.endsWith('browse/edit_playlist')) {
      edits.add((
        body['playlistId'] as String,
        [for (final a in body['actions'] as List) Map<String, dynamic>.from(a)],
      ));
      answer = {'status': refuse ? 'STATUS_FAILED' : 'STATUS_SUCCEEDED'};
    }
    return ResponseBody.fromString(
      jsonEncode(answer),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Account extends MusicModeClient {
  _Account(this.server)
    : super(
        ytm: YtmClient(
          const YtmSession('SAPISID=test'),
          dio: Dio()..httpClientAdapter = server,
        ),
        ytmAccount: () => null,
      );

  final _Server server;

  /// Cuántas playlists devuelve la biblioteca: la primera página trae dos y la
  /// siguiente, el resto.
  var extra = 1;

  final prefs = <String, Map<String, dynamic>>{};

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async =>
      const MusicConnection(
        status: MusicLinkStatus.linked,
        generation: 'pickers',
        account: MusicAccount('channel', 'Cuenta A', false),
        provider: 'youtubeOAuth',
        personalization: 'full',
        capabilities: {'playlists', 'albums', 'liked', 'playback'},
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
  }) async => switch (surface) {
    MusicSurface.playlists =>
      cursor == null
          ? const MusicPage(
              [
                MusicPlaylist(
                  'PLaaaaaaaaaa',
                  'Para correr',
                  true,
                  trackCount: 12,
                ),
                MusicPlaylist('PLbbbbbbbbbb', 'Para dormir', true),
              ],
              'p2',
              null,
              0,
            )
          : MusicPage(
              [
                for (var i = 0; i < extra; i++)
                  MusicPlaylist('PLcccccccc$i', 'Canción de cuna $i', false),
              ],
              null,
              null,
              0,
            ),
    MusicSurface.albums => const MusicPage(
      [MusicAlbum('MPREbbbbbbbb', 'Álbum de prueba')],
      null,
      null,
      0,
    ),
    MusicSurface.liked => const MusicPage(
      [
        MusicTrack(
          'aaaaaaaaaaa',
          'Around the World',
          'Daft Punk',
          430,
          false,
          null,
          nativePlayback: true,
        ),
      ],
      null,
      null,
      0,
    ),
    _ => const MusicPage([], null, null, 0),
  };

  @override
  Future<Map<String, dynamic>?> rememberedPrefs(String key) async => prefs[key];

  @override
  void rememberPrefs(String key, Map<String, dynamic> value) =>
      prefs[key] = value;
}

Future<(_Account, _Server, MusicModeController)> _pump(
  WidgetTester tester, {
  Widget? body,
}) async {
  final server = _Server();
  final client = _Account(server);
  final controller = MusicModeController(client, () => true, () async {});
  addTearDown(controller.dispose);
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: MusicModeHost(
          controller: controller,
          child: body ?? const MusicModeSurface(surface: MusicSurface.songs),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (client, server, controller);
}

Future<void> _openSaveSheet(WidgetTester tester) async {
  await tester.longPress(find.text('Around the World'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Guardar en playlist'));
  await tester.pumpAndSettle();
}

Finder get _checkboxes => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.byType(Checkbox),
);

void main() {
  setUpAll(() => NowPlayingBars.animationsEnabled = false);

  group('«Guardar en playlist»: varias a la vez, con casilla', () {
    testWidgets('lista todas las playlists con su casilla y sin aceptar', (
      tester,
    ) async {
      await _pump(tester);
      await _openSaveSheet(tester);
      final sheet = find.byType(BottomSheet);
      // Las dos de la primera página y la de la segunda.
      for (final name in ['Para correr', 'Para dormir', 'Canción de cuna 0']) {
        expect(
          find.descendant(of: sheet, matching: find.text(name)),
          findsOneWidget,
          reason: name,
        );
      }
      // Una casilla a la derecha de cada una…
      expect(_checkboxes, findsNWidgets(3));
      // …y ningún botón de aceptar.
      expect(find.widgetWithText(FilledButton, 'Aceptar'), findsNothing);
      expect(find.text('Aceptar'), findsNothing);
      expect(find.text('Listo'), findsNothing);
      // Cuántas canciones tiene (la que no lo dice, el tipo).
      expect(find.text('12 canciones'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('marcar dos guarda en las dos sin cerrar la hoja', (
      tester,
    ) async {
      final (_, server, _) = await _pump(tester);
      await _openSaveSheet(tester);

      await tester.tap(_checkboxes.at(0));
      await tester.pumpAndSettle();
      await tester.tap(_checkboxes.at(1));
      await tester.pumpAndSettle();

      // Cada una recibió su orden de añadir la canción.
      expect(server.edits.map((e) => e.$1), ['PLaaaaaaaaaa', 'PLbbbbbbbbbb']);
      for (final (_, actions) in server.edits) {
        expect(actions.single, {
          'action': 'ACTION_ADD_VIDEO',
          'addedVideoId': 'aaaaaaaaaaa',
        });
      }
      // La hoja sigue abierta y las dos casillas marcadas.
      expect(find.text('Guardar en playlist'), findsWidgets);
      final values = tester
          .widgetList<Checkbox>(_checkboxes)
          .map((c) => c.value)
          .toList();
      expect(values, [true, true, false]);
      // El recuento sube: 12 → 13.
      expect(find.text('13 canciones'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tocar la fila entera también marca', (tester) async {
      final (_, server, _) = await _pump(tester);
      await _openSaveSheet(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Canción de cuna 0'),
        ),
      );
      await tester.pumpAndSettle();
      expect(server.edits.single.$1, 'PLcccccccc0');
      expect(tester.widgetList<Checkbox>(_checkboxes).last.value, isTrue);
    });

    testWidgets('las que ya la tienen salen marcadas y desmarcar la quita', (
      tester,
    ) async {
      final (_, server, _) = await _pump(tester);
      server.contains.add('PLaaaaaaaaaa');
      await _openSaveSheet(tester);
      expect(tester.widgetList<Checkbox>(_checkboxes).first.value, isTrue);

      await tester.tap(_checkboxes.first);
      await tester.pumpAndSettle();
      expect(server.edits.single.$1, 'PLaaaaaaaaaa');
      expect(server.edits.single.$2.single, {
        'action': 'ACTION_REMOVE_VIDEO_BY_VIDEO_ID',
        'removedVideoId': 'aaaaaaaaaaa',
      });
      expect(tester.widgetList<Checkbox>(_checkboxes).first.value, isFalse);
      // El recuento baja: 12 → 11.
      expect(find.text('11 canciones'), findsOneWidget);
    });

    testWidgets('si YouTube lo rechaza, la casilla vuelve y lo dice', (
      tester,
    ) async {
      final (_, server, _) = await _pump(tester);
      server.refuse = true;
      await _openSaveSheet(tester);
      await tester.tap(_checkboxes.first);
      await tester.pumpAndSettle();
      expect(tester.widgetList<Checkbox>(_checkboxes).first.value, isFalse);
      // El error sustituye, en esa fila y en rojo, al número de canciones.
      expect(find.text('YouTube Music no aceptó el cambio.'), findsOneWidget);
      expect(find.text('12 canciones'), findsNothing);
      // Y nada se guardó: volver a tocar lo reintenta.
      server.refuse = false;
      await tester.tap(_checkboxes.first);
      await tester.pumpAndSettle();
      expect(tester.widgetList<Checkbox>(_checkboxes).first.value, isTrue);
      expect(find.text('13 canciones'), findsOneWidget);
    });

    testWidgets('una biblioteca larga: llegan todas las páginas', (
      tester,
    ) async {
      final (client, _, _) = await _pump(tester);
      client.extra = 30;
      await _openSaveSheet(tester);
      // La lista se desplaza; la última de la segunda página está en ella.
      await tester.scrollUntilVisible(
        find.text('Canción de cuna 29'),
        400,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Canción de cuna 29'), findsOneWidget);
    });
  });

  group('«Añadir atajo»: todas las playlists y un buscador', () {
    Future<void> openPicker(WidgetTester tester) async {
      late BuildContext context;
      late MusicModeController music;
      await tester.pumpWidget(const SizedBox());
      // Se abre desde un botón dentro del propio árbol de la prueba.
      final (_, _, controller) = await _pump(
        tester,
        body: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      music = controller;
      unawaited(showShortcutPicker(context, music, 'pickers'));
      await tester.pumpAndSettle();
    }

    testWidgets('ofrece las playlists de todas las páginas', (tester) async {
      await openPicker(tester);
      expect(find.text('Añadir atajo'), findsOneWidget);
      expect(find.text('Para correr'), findsOneWidget);
      // De la segunda página (antes solo se pedía la primera).
      expect(find.text('Canción de cuna 0'), findsOneWidget);
    });

    testWidgets('el buscador: línea con lupa que filtra sin mirar acentos', (
      tester,
    ) async {
      await openPicker(tester);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // Escribir «cancion» (sin tilde) deja «Canción de cuna 0».
      await tester.enterText(find.byType(TextField), 'cancion');
      await tester.pumpAndSettle();
      expect(find.text('Canción de cuna 0'), findsOneWidget);
      expect(find.text('Para correr'), findsNothing);
      // Algo que no existe: se avisa.
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('No hay resultados'), findsOneWidget);
      // La «x» borra lo escrito y vuelve todo.
      await tester.tap(find.byTooltip('Borrar'));
      await tester.pumpAndSettle();
      expect(find.text('Para correr'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('lo que se lee de YouTube Music', () {
    test('cuántas canciones dice un subtítulo', () {
      expect(songCount('Playlist • 36 canciones'), 36);
      expect(songCount('Playlist · 1.234 canciones'), 1234);
      expect(songCount('12 songs'), 12);
      expect(songCount('1 canción'), 1);
      expect(songCount('Privada'), isNull);
      expect(songCount(''), isNull);
      // Un número enorme no es un recuento creíble.
      expect(songCount('9999999 canciones'), isNull);
    });

    test('las opciones de «Guardar en playlist» con su casilla', () {
      final options = parseYtmSaveOptions({
        'contents': [
          {
            'addToPlaylistRenderer': {
              'playlists': [
                {
                  'playlistAddToOptionRenderer': {
                    'playlistId': 'PLaaaaaaaaaa',
                    'title': {
                      'runs': [
                        {'text': 'Una'},
                      ],
                    },
                    'containsSelectedVideos': 'ALL',
                    'shortBylineText': {
                      'runs': [
                        {'text': 'Privada • 7 canciones'},
                      ],
                    },
                  },
                },
                {
                  'playlistAddToOptionRenderer': {
                    'playlistId': 'PLbbbbbbbbbb',
                    'title': {'simpleText': 'Dos'},
                    'containsSelectedVideos': 'NONE',
                  },
                },
                // Sin título o con id raro: se salta.
                {
                  'playlistAddToOptionRenderer': {'playlistId': 'PLcccccccccc'},
                },
                {
                  'playlistAddToOptionRenderer': {
                    'playlistId': '../mal',
                    'title': {'simpleText': 'Mala'},
                  },
                },
              ],
            },
          },
        ],
      });
      expect(options.map((o) => o.id), ['PLaaaaaaaaaa', 'PLbbbbbbbbbb']);
      expect(options.first.contains, isTrue);
      expect(options.first.count, 7);
      expect(options.last.contains, isFalse);
      expect(options.last.count, isNull);
      // Una respuesta vacía no rompe nada.
      expect(parseYtmSaveOptions(<String, dynamic>{}), isEmpty);
    });

    test('la playlist guarda y enseña cuántas canciones tiene', () {
      final playlist = MusicPlaylist.fromJson({
        'id': 'PLaaaaaaaaaa',
        'title': 'Mi lista',
        'private': true,
        'count': 36,
      });
      expect(playlist.trackCount, 36);
      expect(playlist.countLabel, '36 canciones');
      expect(
        MusicPlaylist.fromJson({
          'id': 'x',
          'title': 'Y',
          'count': 1,
        }).countLabel,
        '1 canción',
      );
      // Sin recuento (o uno absurdo), no se inventa.
      expect(
        MusicPlaylist.fromJson({'id': 'x', 'title': 'Y'}).countLabel,
        isNull,
      );
      expect(
        MusicPlaylist.fromJson({
          'id': 'x',
          'title': 'Y',
          'count': -3,
        }).countLabel,
        isNull,
      );
    });
  });
}
