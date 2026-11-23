import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/domain/music_search.dart';
import 'package:mysic/features/connected_library/presentation/library_screen.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_host.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_screen.dart';
import 'package:mysic/features/connected_library/presentation/search_screen.dart';
import 'package:mysic/features/connected_library/presentation/tab_top_bar.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';

import 'support/ytm_test_client.dart';

const _song = MusicTrack(
  'aaaaaaaaaaa',
  'Around the World',
  'Daft Punk',
  430,
  false,
  null,
  nativePlayback: true,
);

class _Search extends MusicModeClient {
  _Search() : super(ytm: ytmTestClient(), ytmAccount: () => null);

  final searched = <String>[];
  final kinds = <SearchKind>[];
  final suggested = <String>[];
  var saved = <String>[];
  var fail = false;

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async =>
      const MusicConnection(
        status: MusicLinkStatus.linked,
        generation: 'search',
        account: MusicAccount('channel', 'Cuenta A', false),
        provider: 'youtubeOAuth',
        personalization: 'full',
        capabilities: {'search', 'playlists', 'playback'},
      );

  @override
  Future<SearchResults> searchAll(
    String query, {
    CancelToken? cancelToken,
  }) async {
    searched.add(query);
    if (fail) throw Exception('sin red');
    return const SearchResults(
      top: MusicArtist('UCaaaaaaaaaaaaaaaaaaaaaa', 'Daft Punk'),
      topSubtitle: 'Artista • 20 M de oyentes mensuales',
      topSongs: [_song],
      songs: [
        MusicTrack(
          'bbbbbbbbbbb',
          'One More Time',
          'Daft Punk',
          320,
          false,
          null,
          nativePlayback: true,
        ),
      ],
      albums: [MusicAlbum('MPREb_aaaaaaaa', 'Discovery', detail: '2001')],
    );
  }

  @override
  Future<List<MusicItem>> searchKind(
    String query,
    SearchKind kind, {
    CancelToken? cancelToken,
  }) async {
    kinds.add(kind);
    return const [
      MusicAlbum('MPREb_aaaaaaaa', 'Discovery', detail: '2001'),
      MusicAlbum('MPREb_bbbbbbbb', 'Homework', detail: '1997'),
    ];
  }

  @override
  Future<SearchSuggestions> suggest(
    String input, {
    CancelToken? cancelToken,
  }) async {
    suggested.add(input);
    return const SearchSuggestions(queries: ['daft punk discovery']);
  }

  @override
  Future<List<MoodSection>?> rememberedMoods() async => null;

  @override
  Future<List<MoodSection>> moods({CancelToken? cancelToken}) async => const [
    MoodSection('Ambientes y momentos', [
      MoodItem('Relax', 'ggMPOg1uX1', 0xFF3366CC),
    ]),
    MoodSection('Géneros', [MoodItem('Rock', 'ggMPOg1uX2', 0xFFCC3333)]),
  ];

  @override
  Future<String?> moodArtwork(String params) async => null;

  @override
  Future<List<String>> rememberedSearches() async => saved;

  @override
  void rememberSearches(List<String> queries) => saved = [...queries];
}

Future<_Search> _pump(WidgetTester tester) async {
  final client = _Search();
  final controller = MusicModeController(client, () => true, () async {});
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: MusicModeHost(
          controller: controller,
          child: const MusicModeSurface(surface: MusicSurface.search),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  // La pausa entre teclas antes de pedir sugerencias.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => NowPlayingBars.animationsEnabled = false);

  testWidgets('con el campo vacío salen la cabecera común y los géneros', (
    tester,
  ) async {
    await _pump(tester);
    // La misma cabecera que Inicio y Biblioteca.
    expect(
      find.descendant(
        of: find.byType(TabTopBar),
        matching: find.text('Buscar'),
      ),
      findsOneWidget,
    );
    expect(find.text('Ambientes y momentos'), findsOneWidget);
    expect(find.text('Relax'), findsOneWidget);
    expect(find.text('Géneros'), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);
    // Sin búsquedas hechas no hay recientes ni chips de tipo.
    expect(find.text('Búsquedas recientes'), findsNothing);
    expect(find.byType(LibraryChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('escribir propone, y la sugerencia busca y enseña resultados', (
    tester,
  ) async {
    final client = await _pump(tester);
    await _type(tester, 'daft');
    expect(client.suggested, ['daft']);
    expect(find.text('daft punk discovery'), findsOneWidget);
    // Aún no se ha buscado nada.
    expect(client.searched, isEmpty);

    await tester.tap(find.text('daft punk discovery'));
    await tester.pumpAndSettle();
    expect(client.searched, ['daft punk discovery']);
    // Resultado principal con su línea y su canción, y una sección por tipo.
    expect(find.text('Artista • 20 M de oyentes mensuales'), findsOneWidget);
    expect(find.text('Around the World'), findsOneWidget);
    expect(find.text('One More Time'), findsOneWidget);
    expect(find.text('Discovery'), findsOneWidget);
    expect(find.widgetWithText(LibraryChip, 'Todo'), findsOneWidget);
    expect(
      tester
          .widget<LibraryChip>(find.widgetWithText(LibraryChip, 'Todo'))
          .selected,
      isTrue,
    );
    // Los álbumes completos no se piden hasta abrir su chip.
    expect(client.kinds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el chip Álbumes pide su lista una sola vez', (tester) async {
    final client = await _pump(tester);
    await _type(tester, 'daft punk');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(client.searched, ['daft punk']);

    await tester.tap(find.widgetWithText(LibraryChip, 'Álbumes'));
    await tester.pumpAndSettle();
    expect(client.kinds, [SearchKind.albums]);
    expect(find.text('Homework'), findsOneWidget);
    expect(find.text('Around the World'), findsNothing);

    await tester.tap(find.widgetWithText(LibraryChip, 'Todo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LibraryChip, 'Álbumes'));
    await tester.pumpAndSettle();
    // Volver al chip no repite la petición.
    expect(client.kinds, [SearchKind.albums]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('las recientes se guardan, se olvidan una a una y se borran', (
    tester,
  ) async {
    final client = await _pump(tester);
    for (final query in ['daft punk', 'air']) {
      await _type(tester, query);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }
    expect(client.saved, ['air', 'daft punk']);
    // Vaciar el campo vuelve a recientes y géneros.
    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    expect(find.text('Búsquedas recientes'), findsOneWidget);
    expect(find.text('air'), findsOneWidget);
    expect(find.text('daft punk'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Olvidar air'));
    await tester.pumpAndSettle();
    expect(find.text('air'), findsNothing);
    expect(client.saved, ['daft punk']);

    // «Borrar» de la sección (el del campo ya no está: el campo está vacío).
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();
    expect(find.text('Búsquedas recientes'), findsNothing);
    expect(client.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('si la búsqueda falla se ofrece reintentar', (tester) async {
    final client = await _pump(tester)
      ..fail = true;
    await _type(tester, 'daft punk');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Ocurrió un error'), findsOneWidget);

    client.fail = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(client.searched, ['daft punk', 'daft punk']);
    expect(find.text('Around the World'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('volver a tocar la pestaña empieza una búsqueda nueva', (
    tester,
  ) async {
    await _pump(tester);
    await _type(tester, 'daft punk');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Around the World'), findsOneWidget);

    searchTabReselected.value++;
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('Around the World'), findsNothing);
    expect(find.text('Búsquedas recientes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
